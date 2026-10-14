// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// rogaudiod: user-space half of the ROG audio stack (docs/AUDIO-ROG.md), the counterpart of RogAudio.driver.
//
//   built-in microphone -> RNNoise -> "ROG Mic Feed"  (apps record "ROG Clear Mic")
//   "ROG Speakers Tap"  -> sound chain -> built-in speakers  (apps play to "ROG Speakers")
//
// The microphone path only runs while an application has "ROG Clear Mic" open (so the microphone indicator does not
// stay on). The speaker path runs for as long as the daemon does. The sound profile is read from
// /Library/Application Support/RogAudio/profile (one word: off | balanced | movie | music | voice), re-read when it changes.
//
//   rogaudiod [-v] [--list] [--profile NAME] [--no-mic] [--no-speakers] [--mic-uid UID] [--out-uid UID] [--strength 0..1]
//
// RNNoise (BSD-3-Clause, Xiph.Org / Jean-Marc Valin): https://github.com/xiph/rnnoise, fetched by scripts/build-rogaudio.sh.
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <math.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "rnnoise.h"
#include "RogAudioSettings.h"

#define RATE 48000.0
#define UID_MIC "com.itlmt7925.rogaudio.mic"
#define UID_FEED "com.itlmt7925.rogaudio.micfeed"
#define UID_SPK "com.itlmt7925.rogaudio.speakers"
#define UID_TAP "com.itlmt7925.rogaudio.tap"
#define PROFILE_FILE "/Library/Application Support/RogAudio/profile"
#define MAXFRAMES 4096
#define MAXCH 8
#define SPK_HIST (MAXFRAMES * 2 + 16)

static int g_verbose;
static volatile sig_atomic_t g_quit;

// ---- ring buffer (single producer, single consumer), samples are floats ----------------------------------------------------
typedef struct {
    float *buf;
    size_t cap;                 // power of two, in floats
    _Atomic size_t w, r;
} Ring;

static void ring_init(Ring *q, size_t cap) { q->buf = calloc(cap, sizeof(float)); q->cap = cap; atomic_store(&q->w, 0); atomic_store(&q->r, 0); }
static size_t ring_fill(Ring *q) { return atomic_load(&q->w) - atomic_load(&q->r); }
static size_t ring_push(Ring *q, const float *p, size_t n)
{
    size_t w = atomic_load(&q->w), r = atomic_load(&q->r), room = q->cap - (w - r);
    if (n > room) n = room;
    for (size_t i = 0; i < n; i++) q->buf[(w + i) & (q->cap - 1)] = p[i];
    atomic_store(&q->w, w + n);
    return n;
}
static size_t ring_pop(Ring *q, float *p, size_t n)
{
    size_t w = atomic_load(&q->w), r = atomic_load(&q->r), have = w - r;
    if (n > have) n = have;
    for (size_t i = 0; i < n; i++) p[i] = q->buf[(r + i) & (q->cap - 1)];
    atomic_store(&q->r, r + n);
    return n;
}

// ---- device helpers -----------------------------------------------------------------------------------------------------
static AudioObjectPropertyAddress addr(AudioObjectPropertySelector s, AudioObjectPropertyScope sc)
{
    AudioObjectPropertyAddress a = { s, sc, kAudioObjectPropertyElementMain };
    return a;
}

static AudioObjectID dev_by_uid(const char *uid)
{
    CFStringRef s = CFStringCreateWithCString(NULL, uid, kCFStringEncodingUTF8);
    AudioObjectID id = kAudioObjectUnknown;
    AudioValueTranslation t = { &s, sizeof(s), &id, sizeof(id) };
    UInt32 size = sizeof(t);
    AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDeviceForUID, kAudioObjectPropertyScopeGlobal);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &t);
    CFRelease(s);
    return id;
}

static void cfstr(CFStringRef s, char *out, size_t n)
{
    out[0] = 0;
    if (s) { CFStringGetCString(s, out, n, kCFStringEncodingUTF8); CFRelease(s); }
}
static void dev_string(AudioObjectID d, AudioObjectPropertySelector sel, char *out, size_t n)
{
    CFStringRef s = NULL;
    UInt32 size = sizeof(s);
    AudioObjectPropertyAddress a = addr(sel, kAudioObjectPropertyScopeGlobal);
    if (AudioObjectGetPropertyData(d, &a, 0, NULL, &size, &s)) s = NULL;
    cfstr(s, out, n);
}
static UInt32 dev_channels(AudioObjectID d, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = addr(kAudioDevicePropertyStreamConfiguration, scope);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(d, &a, 0, NULL, &size) || size == 0) return 0;
    AudioBufferList *bl = malloc(size);
    UInt32 n = 0;
    if (!AudioObjectGetPropertyData(d, &a, 0, NULL, &size, bl))
        for (UInt32 i = 0; i < bl->mNumberBuffers; i++) n += bl->mBuffers[i].mNumberChannels;
    free(bl);
    return n;
}
static UInt32 dev_transport(AudioObjectID d)
{
    UInt32 t = 0, size = sizeof(t);
    AudioObjectPropertyAddress a = addr(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal);
    AudioObjectGetPropertyData(d, &a, 0, NULL, &size, &t);
    return t;
}
static int dev_running_somewhere(AudioObjectID d)
{
    UInt32 r = 0, size = sizeof(r);
    AudioObjectPropertyAddress a = addr(kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal);
    if (AudioObjectGetPropertyData(d, &a, 0, NULL, &size, &r)) return 0;
    return r != 0;
}

typedef struct { AudioObjectID id; char name[96], uid[160]; UInt32 in, out, transport; } DevInfo;
static int list_devices(DevInfo *v, int max)
{
    UInt32 size = 0;
    AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size)) return 0;
    AudioObjectID *ids = malloc(size);
    int n = 0;
    if (!AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, ids))
        for (UInt32 i = 0; i < size / sizeof(*ids) && n < max; i++) {
            DevInfo *d = &v[n++];
            d->id = ids[i];
            dev_string(ids[i], kAudioObjectPropertyName, d->name, sizeof(d->name));
            dev_string(ids[i], kAudioDevicePropertyDeviceUID, d->uid, sizeof(d->uid));
            d->in = dev_channels(ids[i], kAudioObjectPropertyScopeInput);
            d->out = dev_channels(ids[i], kAudioObjectPropertyScopeOutput);
            d->transport = dev_transport(ids[i]);
        }
    free(ids);
    return n;
}

static AudioObjectID pick_builtin(int wantInput, const char *uid)
{
    DevInfo v[64];
    int n = list_devices(v, 64);
    AudioObjectID best = kAudioObjectUnknown;
    for (int i = 0; i < n; i++) {
        if (uid && *uid) { if (!strcmp(v[i].uid, uid)) return v[i].id; continue; }
        if (strncmp(v[i].uid, "com.itlmt7925.rogaudio.", 23) == 0) continue;
        if (v[i].transport != kAudioDeviceTransportTypeBuiltIn) continue;
        if (wantInput ? v[i].in : v[i].out) { best = v[i].id; break; }
    }
    return best;
}

// ---- AUHAL ----------------------------------------------------------------------------------------------------------------
static AudioUnit make_unit(AudioObjectID dev, int input)
{
    AudioComponentDescription d = { kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponent c = AudioComponentFindNext(NULL, &d);
    AudioUnit au = NULL;
    if (!c || AudioComponentInstanceNew(c, &au)) return NULL;
    UInt32 on = 1, off = 0;
    if (input) {
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof(on));
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, sizeof(off));
    }
    if (AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, sizeof(dev))) {
        AudioComponentInstanceDispose(au);
        return NULL;
    }
    return au;
}

static AudioStreamBasicDescription fmt(UInt32 ch, int interleaved)
{
    AudioStreamBasicDescription f = { 0 };
    f.mSampleRate = RATE;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked |
                     (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved);
    f.mFramesPerPacket = 1;
    f.mChannelsPerFrame = ch;
    f.mBitsPerChannel = 32;
    f.mBytesPerFrame = interleaved ? 4 * ch : 4;
    f.mBytesPerPacket = f.mBytesPerFrame;
    return f;
}

static void set_buffer_frames(AudioObjectID dev, UInt32 frames)
{
    AudioObjectPropertyAddress a = addr(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal);
    AudioObjectSetPropertyData(dev, &a, 0, NULL, sizeof(frames), &frames);
}

// ---- microphone path -----------------------------------------------------------------------------------------------------
typedef struct {
    AudioObjectID inDev, feedDev;
    AudioUnit in, out;
    UInt32 inCh;
    DenoiseState *dn;
    Ring ring;                      // denoised mono samples, 48 kHz
    float acc[480];
    int accN;
    _Atomic float strength;
    float *scratch[MAXCH];
    AudioBufferList *abl;
    _Atomic unsigned long frames, underruns, cbs;
    _Atomic int lastErr;
    _Atomic float inLevel, outLevel;
} Mic;
static Mic g_mic;
static int g_mic_on;

static OSStatus mic_in_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *unused)
{
    (void)unused;
    Mic *m = ref;
    if (frames > MAXFRAMES) return 0;
    m->abl->mNumberBuffers = 1;
    m->abl->mBuffers[0].mNumberChannels = m->inCh;
    m->abl->mBuffers[0].mDataByteSize = frames * 4 * m->inCh;
    m->abl->mBuffers[0].mData = m->scratch[0];
    atomic_fetch_add(&m->cbs, 1);
    OSStatus rc = AudioUnitRender(m->in, flags, ts, bus, frames, m->abl);
    atomic_store(&m->lastErr, (int)rc);
    if (rc) return rc;
    float peakIn = 0, peakOut = 0;
    for (UInt32 i = 0; i < frames; i++) {
        float s = 0;
        for (UInt32 c = 0; c < m->inCh; c++) s += m->scratch[0][i * m->inCh + c];
        s /= (float)m->inCh;
        if (fabsf(s) > peakIn) peakIn = fabsf(s);
        m->acc[m->accN++] = s * 32768.0f;
        if (m->accN == 480) {
            float out[480];
            rnnoise_process_frame(m->dn, out, m->acc);
            for (int k = 0; k < 480; k++) {
                float dry = m->acc[k] / 32768.0f, wet = out[k] / 32768.0f;
                float strength = atomic_load(&m->strength);
                float y = wet * strength + dry * (1.0f - strength);
                if (fabsf(y) > peakOut) peakOut = fabsf(y);
                out[k] = y;
            }
            ring_push(&m->ring, out, 480);
            m->accN = 0;
        }
    }
    atomic_store(&m->inLevel, peakIn);
    atomic_store(&m->outLevel, peakOut);
    atomic_fetch_add(&m->frames, frames);
    return 0;
}

static OSStatus mic_out_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io)
{
    (void)flags; (void)ts; (void)bus;
    Mic *m = ref;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        float *p = io->mBuffers[b].mData;
        UInt32 n = io->mBuffers[b].mDataByteSize / 4;
        // keep latency bounded: if the producer ran ahead (> 40 ms) drop the oldest
        size_t fill = ring_fill(&m->ring);
        if (b == 0 && fill > 1920 + frames) { float junk[480]; size_t drop = fill - 960 - frames; while (drop) { size_t k = drop > 480 ? 480 : drop; ring_pop(&m->ring, junk, k); drop -= k; } }
        size_t got = (b == 0) ? ring_pop(&m->ring, p, n) : 0;
        if (b == 0) { if (got < n) atomic_fetch_add(&m->underruns, 1); for (size_t i = got; i < n; i++) p[i] = 0; }
        else memcpy(p, io->mBuffers[0].mData, n * 4);
    }
    return 0;
}

static int mic_start(const char *micUid)
{
    Mic *m = &g_mic;
    m->inDev = pick_builtin(1, micUid);
    m->feedDev = dev_by_uid(UID_FEED);
    if (m->inDev == kAudioObjectUnknown || m->feedDev == kAudioObjectUnknown) { fprintf(stderr, "mic: device missing (in %u feed %u)\n", (unsigned)m->inDev, (unsigned)m->feedDev); return -1; }
    m->inCh = dev_channels(m->inDev, kAudioObjectPropertyScopeInput);
    if (m->inCh == 0) return -1;
    if (m->inCh > MAXCH) m->inCh = MAXCH;
    if (!m->dn) m->dn = rnnoise_create(NULL);
    for (UInt32 c = 0; c < MAXCH; c++) if (!m->scratch[c]) m->scratch[c] = calloc((size_t)MAXFRAMES * MAXCH, sizeof(float));
    if (!m->abl) m->abl = malloc(sizeof(AudioBufferList) + (MAXCH - 1) * sizeof(AudioBuffer));
    if (!m->ring.buf) ring_init(&m->ring, 1 << 15);
    atomic_store(&m->ring.w, 0); atomic_store(&m->ring.r, 0);
    m->accN = 0;

    m->in = make_unit(m->inDev, 1);
    m->out = make_unit(m->feedDev, 0);
    if (!m->in || !m->out) return -1;
    AudioStreamBasicDescription fin = fmt(m->inCh, 1), fout = fmt(1, 1);
    AURenderCallbackStruct cin = { mic_in_cb, m }, cout = { mic_out_cb, m };
    OSStatus rc = 0;
    rc |= AudioUnitSetProperty(m->in, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fin, sizeof(fin));
    rc |= AudioUnitSetProperty(m->in, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cin, sizeof(cin));
    rc |= AudioUnitSetProperty(m->out, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fout, sizeof(fout));
    rc |= AudioUnitSetProperty(m->out, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cout, sizeof(cout));
    set_buffer_frames(m->feedDev, 480);
    rc |= AudioUnitInitialize(m->in);
    rc |= AudioUnitInitialize(m->out);
    if (rc) { fprintf(stderr, "mic: AudioUnit setup failed (%d)\n", (int)rc); return -1; }
    rc = AudioOutputUnitStart(m->out);
    if (!rc) rc = AudioOutputUnitStart(m->in);
    if (rc) { fprintf(stderr, "mic: start failed (%d); microphone permission?\n", (int)rc); return -1; }
    char n[96]; dev_string(m->inDev, kAudioObjectPropertyName, n, sizeof(n));
    char u[96]; dev_string(m->inDev, kAudioDevicePropertyDeviceUID, u, sizeof(u));
    fprintf(stderr, "mic: on (%s, uid %s, %u ch)\n", n, u, (unsigned)m->inCh);
    return 0;
}

static void mic_stop(void)
{
    Mic *m = &g_mic;
    if (m->in) { AudioOutputUnitStop(m->in); AudioUnitUninitialize(m->in); AudioComponentInstanceDispose(m->in); m->in = NULL; }
    if (m->out) { AudioOutputUnitStop(m->out); AudioUnitUninitialize(m->out); AudioComponentInstanceDispose(m->out); m->out = NULL; }
    fprintf(stderr, "mic: off\n");
}

// ---- sound chain ---------------------------------------------------------------------------------------------------------
typedef struct { float b0, b1, b2, a1, a2; float z1[2], z2[2]; } Biquad;
enum { BQ_HPF, BQ_PEAK, BQ_LOWSHELF, BQ_HIGHSHELF, BQ_NONE };

static void bq_set(Biquad *q, int type, float f0, float Q, float gainDb)
{
    memset(q, 0, sizeof(*q));
    if (type == BQ_NONE) { q->b0 = 1; return; }
    double A = pow(10.0, gainDb / 40.0), w = 2.0 * M_PI * f0 / RATE, cs = cos(w), sn = sin(w), al = sn / (2.0 * Q);
    double b0, b1, b2, a0, a1, a2, sq = 2.0 * sqrt(A) * al;
    switch (type) {
    case BQ_HPF:
        b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; break;
    case BQ_PEAK:
        b0 = 1 + al * A; b1 = -2 * cs; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * cs; a2 = 1 - al / A; break;
    case BQ_LOWSHELF:
        b0 = A * ((A + 1) - (A - 1) * cs + sq); b1 = 2 * A * ((A - 1) - (A + 1) * cs); b2 = A * ((A + 1) - (A - 1) * cs - sq);
        a0 = (A + 1) + (A - 1) * cs + sq; a1 = -2 * ((A - 1) + (A + 1) * cs); a2 = (A + 1) + (A - 1) * cs - sq; break;
    default: // BQ_HIGHSHELF
        b0 = A * ((A + 1) + (A - 1) * cs + sq); b1 = -2 * A * ((A - 1) + (A + 1) * cs); b2 = A * ((A + 1) + (A - 1) * cs - sq);
        a0 = (A + 1) - (A - 1) * cs + sq; a1 = 2 * ((A - 1) - (A + 1) * cs); a2 = (A + 1) - (A - 1) * cs - sq; break;
    }
    q->b0 = (float)(b0 / a0); q->b1 = (float)(b1 / a0); q->b2 = (float)(b2 / a0); q->a1 = (float)(a1 / a0); q->a2 = (float)(a2 / a0);
}
static inline float bq_run(Biquad *q, int ch, float x)
{
    float y = q->b0 * x + q->z1[ch];
    q->z1[ch] = q->b1 * x - q->a1 * y + q->z2[ch];
    q->z2[ch] = q->b2 * x - q->a2 * y;
    return y;
}

#define NBQ 6
typedef struct {
    const char *name;
    struct { int type; float f, q, g; } bq[NBQ];
    float width;          // 1 = unchanged, >1 widens (side gain)
    float preGainDb;
    float limitDb;        // limiter ceiling
} Profile;

static const Profile kProfiles[] = {
    { "off",      { { BQ_NONE, 0, 0, 0 } }, 1.0f, 0.0f, -0.3f },
    { "balanced", { { BQ_HPF, 70, 0.7f, 0 }, { BQ_LOWSHELF, 130, 0.7f, 3.0f }, { BQ_PEAK, 420, 1.0f, -2.0f },
                    { BQ_PEAK, 3000, 1.0f, 2.0f }, { BQ_HIGHSHELF, 9000, 0.7f, 2.0f } }, 1.15f, -1.5f, -1.0f },
    { "movie",    { { BQ_HPF, 60, 0.7f, 0 }, { BQ_LOWSHELF, 100, 0.7f, 5.0f }, { BQ_PEAK, 350, 1.0f, -2.5f },
                    { BQ_PEAK, 2500, 1.1f, 3.5f }, { BQ_HIGHSHELF, 8000, 0.7f, 3.0f } }, 1.35f, -2.5f, -1.0f },
    { "music",    { { BQ_HPF, 60, 0.7f, 0 }, { BQ_LOWSHELF, 110, 0.7f, 4.0f }, { BQ_PEAK, 500, 1.0f, -1.5f },
                    { BQ_PEAK, 2800, 1.0f, 1.0f }, { BQ_HIGHSHELF, 9000, 0.7f, 3.0f } }, 1.2f, -2.0f, -1.0f },
    { "voice",    { { BQ_HPF, 120, 0.7f, 0 }, { BQ_LOWSHELF, 220, 0.7f, -3.0f }, { BQ_PEAK, 2500, 1.0f, 4.0f },
                    { BQ_HIGHSHELF, 7000, 0.7f, 1.0f } }, 1.0f, -1.0f, -1.0f },
};
#define NPROFILES ((int)(sizeof(kProfiles) / sizeof(kProfiles[0])))

typedef struct {
    AudioObjectID tapDev, outDev;
    AudioUnit in, out;
    Ring ring;                                  // interleaved stereo
    float *scratch[2];
    AudioBufferList *abl;
    // chain state
    Biquad bq[NBQ];
    float width, preGain, ceiling, env;
    _Atomic int profileIdx;                     // set from the main thread
    int appliedIdx;
    _Atomic unsigned long frames, underruns, overruns;
    _Atomic float level;
    // drift control
    double pos;
    float hist[(MAXFRAMES * 2 + 16) * 2];       // interpolation history / not yet consumed input frames
    size_t hn;
    int starving;
} Spk;
static Spk g_spk;

static void spk_apply_profile(Spk *s, int idx)
{
    const Profile *p = &kProfiles[idx];
    for (int i = 0; i < NBQ; i++) {
        if (p->bq[i].f <= 0) bq_set(&s->bq[i], BQ_NONE, 0, 0, 0);       // unused table entry (zeroed) or the "off" profile
        else bq_set(&s->bq[i], p->bq[i].type, p->bq[i].f, p->bq[i].q > 0 ? p->bq[i].q : 0.7f, p->bq[i].g);
    }
    s->width = p->width;
    s->preGain = powf(10.0f, p->preGainDb / 20.0f);
    s->ceiling = powf(10.0f, p->limitDb / 20.0f);
    s->appliedIdx = idx;
}

static OSStatus spk_in_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *unused)
{
    (void)unused;
    Spk *s = ref;
    if (frames > MAXFRAMES) return 0;
    int want = atomic_load(&s->profileIdx);
    if (want != s->appliedIdx) spk_apply_profile(s, want);
    s->abl->mNumberBuffers = 2;
    for (int c = 0; c < 2; c++) {
        s->abl->mBuffers[c].mNumberChannels = 1;
        s->abl->mBuffers[c].mDataByteSize = frames * 4;
        s->abl->mBuffers[c].mData = s->scratch[c];
    }
    OSStatus rc = AudioUnitRender(s->in, flags, ts, bus, frames, s->abl);
    if (rc) return rc;
    static float inter[MAXFRAMES * 2];
    float peak = 0;
    for (UInt32 i = 0; i < frames; i++) {
        float l = s->scratch[0][i] * s->preGain, r = s->scratch[1][i] * s->preGain;
        // width: mid/side
        float m = 0.5f * (l + r), sd = 0.5f * (l - r) * s->width;
        l = m + sd; r = m - sd;
        for (int k = 0; k < NBQ; k++) { l = bq_run(&s->bq[k], 0, l); r = bq_run(&s->bq[k], 1, r); }
        // peak limiter: instant attack, ~120 ms release
        float pk = fmaxf(fabsf(l), fabsf(r));
        if (pk > s->env) s->env = pk; else s->env += (pk - s->env) * (1.0f / 5760.0f);
        float g = s->env > s->ceiling ? s->ceiling / s->env : 1.0f;
        l *= g; r *= g;
        // hard guard against the instant a release is still catching up
        if (l > 1.0f) l = 1.0f; else if (l < -1.0f) l = -1.0f;
        if (r > 1.0f) r = 1.0f; else if (r < -1.0f) r = -1.0f;
        inter[2 * i] = l; inter[2 * i + 1] = r;
        if (pk > peak) peak = pk;
    }
    if (ring_push(&s->ring, inter, (size_t)frames * 2) < (size_t)frames * 2) atomic_fetch_add(&s->overruns, 1);
    atomic_store(&s->level, peak);
    atomic_fetch_add(&s->frames, frames);
    return 0;
}

#define SPK_TARGET 1024.0     // frames of cushion between the tap and the speakers

static OSStatus spk_out_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io)
{
    (void)flags; (void)ts; (void)bus;
    Spk *s = ref;
    // non-interleaved stereo float requested: buffers 0 / 1
    float *L = io->mBuffers[0].mData, *R = io->mNumberBuffers > 1 ? io->mBuffers[1].mData : NULL;
    if (frames > MAXFRAMES) frames = MAXFRAMES;
    double fill = (double)(ring_fill(&s->ring) / 2 + s->hn);
    if (s->starving) { if (fill >= SPK_TARGET) s->starving = 0; }
    else if (fill < 2) { s->starving = 1; atomic_fetch_add(&s->underruns, 1); }
    if (s->starving) {
        for (UInt32 i = 0; i < frames; i++) { L[i] = 0; if (R) R[i] = 0; }
        return 0;
    }
    // adaptive step: a slow proportional pull keeps the cushion at SPK_TARGET frames
    double err = (fill - SPK_TARGET) / 65536.0;
    if (err > 0.004) err = 0.004; else if (err < -0.004) err = -0.004;
    double step = 1.0 + err;
    size_t need = (size_t)(s->pos + frames * step) + 2;           // input frames the interpolation can touch
    if (s->hn < need) {
        size_t room = SPK_HIST - s->hn, want = need - s->hn;
        if (want > room) want = room;
        size_t got = ring_pop(&s->ring, s->hist + 2 * s->hn, want * 2) / 2;
        s->hn += got;
        while (s->hn < need && s->hn < SPK_HIST) {                  // short read: repeat the last frame
            float l = s->hn ? s->hist[2 * (s->hn - 1)] : 0, r = s->hn ? s->hist[2 * (s->hn - 1) + 1] : 0;
            s->hist[2 * s->hn] = l; s->hist[2 * s->hn + 1] = r;
            s->hn++;
        }
    }
    double pos = s->pos;
    for (UInt32 i = 0; i < frames; i++) {
        size_t k = (size_t)pos;
        double f = pos - (double)k;
        if (k + 1 >= s->hn) k = s->hn >= 2 ? s->hn - 2 : 0;
        L[i] = (float)(s->hist[2 * k] * (1 - f) + s->hist[2 * (k + 1)] * f);
        if (R) R[i] = (float)(s->hist[2 * k + 1] * (1 - f) + s->hist[2 * (k + 1) + 1] * f);
        pos += step;
    }
    size_t used = (size_t)pos;
    if (used > s->hn) used = s->hn;
    s->pos = pos - (double)(size_t)pos;
    memmove(s->hist, s->hist + 2 * used, (s->hn - used) * 2 * sizeof(float));
    s->hn -= used;
    return 0;
}

static int spk_start(const char *outUid, int profile)
{
    Spk *s = &g_spk;
    s->tapDev = dev_by_uid(UID_TAP);
    s->outDev = pick_builtin(0, outUid);
    if (s->tapDev == kAudioObjectUnknown || s->outDev == kAudioObjectUnknown) { fprintf(stderr, "speakers: device missing (tap %u out %u)\n", (unsigned)s->tapDev, (unsigned)s->outDev); return -1; }
    for (int c = 0; c < 2; c++) if (!s->scratch[c]) s->scratch[c] = calloc(MAXFRAMES, sizeof(float));
    if (!s->abl) s->abl = malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
    if (!s->ring.buf) ring_init(&s->ring, 1 << 16);
    atomic_store(&s->ring.w, 0); atomic_store(&s->ring.r, 0);
    s->pos = 0; s->hn = 0; s->starving = 1; s->env = 0;
    atomic_store(&s->profileIdx, profile);
    spk_apply_profile(s, profile);

    s->in = make_unit(s->tapDev, 1);
    s->out = make_unit(s->outDev, 0);
    if (!s->in || !s->out) return -1;
    AudioStreamBasicDescription fin = fmt(2, 0), fout = fmt(2, 0);
    AURenderCallbackStruct cin = { spk_in_cb, s }, cout = { spk_out_cb, s };
    OSStatus rc = 0;
    rc |= AudioUnitSetProperty(s->in, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fin, sizeof(fin));
    rc |= AudioUnitSetProperty(s->in, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cin, sizeof(cin));
    rc |= AudioUnitSetProperty(s->out, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fout, sizeof(fout));
    rc |= AudioUnitSetProperty(s->out, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cout, sizeof(cout));
    set_buffer_frames(s->tapDev, 256);
    set_buffer_frames(s->outDev, 256);
    rc |= AudioUnitInitialize(s->in);
    rc |= AudioUnitInitialize(s->out);
    if (rc) { fprintf(stderr, "speakers: AudioUnit setup failed (%d)\n", (int)rc); return -1; }
    rc = AudioOutputUnitStart(s->in);
    if (!rc) rc = AudioOutputUnitStart(s->out);
    if (rc) { fprintf(stderr, "speakers: start failed (%d)\n", (int)rc); return -1; }
    char n[96]; dev_string(s->outDev, kAudioObjectPropertyName, n, sizeof(n));
    fprintf(stderr, "speakers: on -> %s, profile %s\n", n, kProfiles[profile].name);
    return 0;
}

// ---- main ---------------------------------------------------------------------------------------------------------------
static int profile_index(const char *name)
{
    for (int i = 0; i < NPROFILES; i++) if (!strcmp(name, kProfiles[i].name)) return i;
    return -1;
}

static int read_profile_file(time_t *mt, int cur)
{
    struct stat st;
    if (stat(PROFILE_FILE, &st) || st.st_mtime == *mt) return cur;
    *mt = st.st_mtime;
    FILE *f = fopen(PROFILE_FILE, "r");
    if (!f) return cur;
    char w[32] = { 0 };
    if (fscanf(f, "%31s", w) != 1) w[0] = 0;
    fclose(f);
    int i = profile_index(w);
    if (i >= 0) { fprintf(stderr, "profile: %s\n", w); return i; }
    return cur;
}

static OSStatus restarted_cb(AudioObjectID o, UInt32 n, const AudioObjectPropertyAddress *a, void *c)
{
    (void)o; (void)n; (void)a; (void)c;
    g_quit = 2;                      // coreaudiod restarted: all AudioObjectIDs are stale; exit, launchd starts us again
    return 0;
}

static void on_sig(int s) { (void)s; g_quit = 1; }

int main(int argc, char **argv)
{
    int profile = 1, doMic = 1, doSpk = 1, list = 0;
    const char *micUid = NULL, *outUid = NULL;
    float strength = 1.0f;
    const char *settingsPath = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-v")) g_verbose = 1;
        else if (!strcmp(argv[i], "--list")) list = 1;
        else if (!strcmp(argv[i], "--no-mic")) doMic = 0;
        else if (!strcmp(argv[i], "--no-speakers")) doSpk = 0;
        else if (!strcmp(argv[i], "--profile") && i + 1 < argc) { profile = profile_index(argv[++i]); if (profile < 0) { fprintf(stderr, "unknown profile\n"); return 2; } }
        else if (!strcmp(argv[i], "--mic-uid") && i + 1 < argc) micUid = argv[++i];
        else if (!strcmp(argv[i], "--out-uid") && i + 1 < argc) outUid = argv[++i];
        else if (!strcmp(argv[i], "--strength") && i + 1 < argc) strength = (float)atof(argv[++i]);
        else if (!strcmp(argv[i], "--settings") && i + 1 < argc) settingsPath = argv[++i];
        else { fprintf(stderr, "usage: rogaudiod [-v] [--list] [--profile off|balanced|movie|music|voice] [--no-mic] [--no-speakers] [--mic-uid UID] [--out-uid UID] [--strength 0..1]\n"); return 2; }
    }
    if (list) {
        DevInfo v[64];
        int n = list_devices(v, 64);
        for (int i = 0; i < n; i++)
            printf("%-4u in %u out %u  transport %.4s  %-28s %s\n", (unsigned)v[i].id, (unsigned)v[i].in, (unsigned)v[i].out,
                   (char[]){ (char)(v[i].transport >> 24), (char)(v[i].transport >> 16), (char)(v[i].transport >> 8), (char)v[i].transport, 0 },
                   v[i].name, v[i].uid);
        return 0;
    }
    signal(SIGINT, on_sig); signal(SIGTERM, on_sig);
    setvbuf(stderr, NULL, _IOLBF, 0);
    g_mic.strength = strength < 0 ? 0 : (strength > 1 ? 1 : strength);

    AudioObjectPropertyAddress ra = addr(kAudioHardwarePropertyServiceRestarted, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &ra, restarted_cb, NULL);

    time_t pmt = 0;
    profile = read_profile_file(&pmt, profile);
    int spkOn = 0;
    int micIdle = 0;
    unsigned long lastStat = 0;
    unsigned long statusTick = 0;
    while (!g_quit) {
        RogAudioSettings settings = { .volume = -20, .strength = strength, .noise = 1, .micEnabled = settingsPath ? 0 : 1 };
        if (rog_settings_read(settingsPath, &settings)) {
            int configured = profile_index(settings.profile);
            if (configured >= 0 && configured != profile) {
                profile = configured;
                atomic_store(&g_spk.profileIdx, profile);
                fprintf(stderr, "profile: %s (RogControl)\n", settings.profile);
            }
            atomic_store(&g_mic.strength, settings.noise ? settings.strength : 0);
        }
        if (doSpk && !spkOn) {
            if (spk_start(outUid, profile) == 0) spkOn = 1;
        }
        if (doMic) {
            AudioObjectID mic = dev_by_uid(UID_MIC);
            // master switch: when off the built-in mic is never opened, even if an app records from ROG Clear Mic
            int want = settings.micEnabled && mic != kAudioObjectUnknown && dev_running_somewhere(mic);
            if (!settings.micEnabled && g_mic_on) { mic_stop(); g_mic_on = 0; micIdle = 0; }
            else if (want && !g_mic_on) { if (mic_start(micUid) == 0) g_mic_on = 1; else mic_stop(); micIdle = 0; }
            else if (!want && g_mic_on) { if (++micIdle >= 6) { mic_stop(); g_mic_on = 0; micIdle = 0; } }
            else if (want) micIdle = 0;
        }
        int np = settingsPath ? profile : read_profile_file(&pmt, profile);
        if (np != profile) { profile = np; atomic_store(&g_spk.profileIdx, profile); }
        if (settingsPath && ++statusTick % 4 == 0) {
            char path[1024], temp[1024];
            const char *slash = strrchr(settingsPath, '/');
            if (slash && slash - settingsPath < 900) {
                snprintf(path, sizeof(path), "%.*s/status.plist", (int)(slash - settingsPath), settingsPath);
                snprintf(temp, sizeof(temp), "%s.tmp", path);
                FILE *f = fopen(temp, "w");
                if (f) {
                    fprintf(f, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
                        "<key>updated</key><real>%.0f</real><key>micActive</key><%s/><key>micEnabled</key><%s/>"
                        "<key>speakerActive</key><%s/><key>profile</key><string>%s</string>"
                        "<key>strength</key><real>%.3f</real></dict></plist>",
                        (double)time(NULL), g_mic_on ? "true" : "false", settings.micEnabled ? "true" : "false", spkOn ? "true" : "false",
                        kProfiles[profile].name, atomic_load(&g_mic.strength));
                    fclose(f); rename(temp, path);
                }
            }
        }
        usleep(250000);
        if (g_verbose && ++lastStat % 20 == 0)
            fprintf(stderr, "stat: mic %s cbs %lu err %d in %.3f out %.3f underruns %lu | spk frames %lu level %.3f underruns %lu overruns %lu\n",
                    g_mic_on ? "on" : "off", atomic_load(&g_mic.cbs), atomic_load(&g_mic.lastErr), atomic_load(&g_mic.inLevel), atomic_load(&g_mic.outLevel), atomic_load(&g_mic.underruns),
                    atomic_load(&g_spk.frames), atomic_load(&g_spk.level), atomic_load(&g_spk.underruns), atomic_load(&g_spk.overruns));
    }
    if (g_mic_on) mic_stop();
    if (spkOn) {
        AudioOutputUnitStop(g_spk.in); AudioOutputUnitStop(g_spk.out);
        AudioUnitUninitialize(g_spk.in); AudioUnitUninitialize(g_spk.out);
    }
    return g_quit == 2 ? 75 : 0;
}
