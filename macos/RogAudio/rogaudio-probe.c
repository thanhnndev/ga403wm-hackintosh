// SPDX-License-Identifier: BSD-3-Clause-Clear
// Reuse the daemon's device and HAL setup; no samples are saved.
#define main rogaudiod_main
#include "rogaudiod.c"
#undef main

static void put32(unsigned char *p, uint32_t v)
{
    for (int i = 0; i < 4; i++) p[i] = (unsigned char)(v >> (8 * i));
}

typedef struct {
    AudioUnit unit;
    UInt32 channels;
    float data[MAXFRAMES * MAXCH];
    _Atomic unsigned long frames;
    _Atomic int error;
    double squares;
    double toneSin, toneCos;
    float peak;
    unsigned long samples;
    int output;
    int music;
    _Atomic float recentRMS;
} Probe;

static float speaker_sample(double t, unsigned channel)
{
    int phase = (int)(t / 4);
    if (phase >= 5) return 0;
    if (phase < 4 && channel != (unsigned)(phase / 2)) return 0;
    double local = fmod(t, 4);
    if (local > 3.6) return 0;
    double beat = fmod(local, 0.4), envelope = (1 - exp(-beat * 120)) * exp(-beat * 8);
    static const double melody[] = {880, 1108.73, 1318.51, 1760, 1318.51, 1108.73, 987.77, 1318.51, 1760};
    static const double bass[] = {164.81, 196, 220, 246.94, 220, 196, 164.81, 196, 220};
    int note = (int)(local / 0.4) % 9;
    double frequency = phase % 2 == 0 ? melody[note] : bass[note];
    if (phase == 4) frequency = channel ? melody[note] : bass[note];
    double pluck = sin(2 * M_PI * frequency * beat) + 0.25 * sin(4 * M_PI * frequency * beat);
    double rhythm = 0.12 * sin(2 * M_PI * (phase % 2 ? 330 : 3300) * beat) * exp(-beat * 35);
    return (float)(0.06 * envelope * (pluck + rhythm));
}

static int render_test(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 1;
    unsigned char header[44] = {0};
    unsigned frames = 20 * 48000, bytes = frames * 4;
    memcpy(header, "RIFF", 4); put32(header + 4, 36 + bytes); memcpy(header + 8, "WAVEfmt ", 8);
    put32(header + 16, 16); header[20] = 1; header[22] = 2;
    put32(header + 24, 48000); put32(header + 28, 192000); header[32] = 4; header[34] = 16;
    memcpy(header + 36, "data", 4); put32(header + 40, bytes);
    if (fwrite(header, 1, sizeof(header), f) != sizeof(header)) { fclose(f); return 1; }
    for (unsigned i = 0; i < frames; i++) {
        int16_t samples[2] = {(int16_t)(speaker_sample(i / RATE, 0) * 32767),
                             (int16_t)(speaker_sample(i / RATE, 1) * 32767)};
        if (fwrite(samples, sizeof(samples), 1, f) != 1) { fclose(f); return 1; }
    }
    return fclose(f) ? 1 : 0;
}

static OSStatus probe_cb(void *ref, AudioUnitRenderActionFlags *flags,
                        const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io)
{
    Probe *p = ref;
    if (frames > MAXFRAMES) return kAudio_ParamError;
    if (p->output) {
        unsigned long start = atomic_load(&p->frames);
        double blockSquares = 0;
        unsigned long blockSamples = 0;
        unsigned channelOffset = 0;
        for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
            float *v = io->mBuffers[b].mData;
            UInt32 ch = io->mBuffers[b].mNumberChannels;
            for (UInt32 i = 0; i < frames; i++) {
                double t = (start + i) / RATE;
                double envelope = fmin(1.0, t / 0.1);
                float s = (float)(0.02 * envelope * sin(2 * M_PI * 1000 * t));
                for (UInt32 c = 0; c < ch; c++) {
                    float sample = p->music ? speaker_sample(t, channelOffset + c) : s;
                    v[i * ch + c] = sample;
                    blockSquares += sample * sample;
                    if (fabsf(sample) > p->peak) p->peak = fabsf(sample);
                    blockSamples++;
                }
            }
            channelOffset += ch;
        }
        p->squares += blockSquares;
        p->samples += blockSamples;
        atomic_store(&p->recentRMS, blockSamples ? (float)sqrt(blockSquares / blockSamples) : 0);
    } else {
        AudioBufferList abl = { .mNumberBuffers = 1,
            .mBuffers = {{p->channels, frames * p->channels * sizeof(float), p->data}} };
        OSStatus rc = AudioUnitRender(p->unit, flags, ts, bus, frames, &abl);
        if (rc) { atomic_store(&p->error, rc); return rc; }
        unsigned long start = atomic_load(&p->frames);
        double blockSquares = 0;
        for (UInt32 i = 0; i < frames; i++) {
            double s = 0;
            for (UInt32 c = 0; c < p->channels; c++) s += p->data[i * p->channels + c];
            s /= p->channels;
            p->squares += s * s;
            blockSquares += s * s;
            p->toneSin += s * sin(2 * M_PI * 1000 * (start + i) / RATE);
            p->toneCos += s * cos(2 * M_PI * 1000 * (start + i) / RATE);
            if (fabs(s) > p->peak) p->peak = (float)fabs(s);
            p->samples++;
        }
        atomic_store(&p->recentRMS, frames ? (float)sqrt(blockSquares / frames) : 0);
    }
    atomic_fetch_add(&p->frames, frames);
    return 0;
}

// ---- monitor: input device -> output device, live (hear your own voice) ---------------------------------------------------
#define RING 16384
typedef struct {
    AudioUnit in, out;
    UInt32 inCh, outCh;
    float ring[RING];
    _Atomic unsigned long wr, rd;
    float scratch[MAXFRAMES * MAXCH];
    float gain;
    _Atomic float recentRMS;
    _Atomic int error;
    _Atomic unsigned long frames, underruns;
} Monitor;

static OSStatus monitor_in_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                              UInt32 bus, UInt32 frames, AudioBufferList *io)
{
    Monitor *m = ref;
    if (frames > MAXFRAMES) return kAudio_ParamError;
    AudioBufferList abl = { .mNumberBuffers = 1, .mBuffers = {{m->inCh, frames * m->inCh * sizeof(float), m->scratch}} };
    OSStatus rc = AudioUnitRender(m->in, flags, ts, bus, frames, &abl);
    if (rc) { atomic_store(&m->error, rc); return rc; }
    unsigned long w = atomic_load(&m->wr), r = atomic_load(&m->rd);
    if (w - r > RING - frames) { atomic_store(&m->rd, w - 2048); }      // overrun: drop old audio
    double sq = 0;
    for (UInt32 i = 0; i < frames; i++) {
        float s = 0;
        for (UInt32 c = 0; c < m->inCh; c++) s += m->scratch[i * m->inCh + c];
        s = s / m->inCh * m->gain;
        sq += s * s;
        m->ring[(w + i) % RING] = s;
    }
    atomic_store(&m->wr, w + frames);
    atomic_store(&m->recentRMS, frames ? (float)sqrt(sq / frames) : 0);
    atomic_fetch_add(&m->frames, frames);
    return 0;
}

static OSStatus monitor_out_cb(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                               UInt32 bus, UInt32 frames, AudioBufferList *io)
{
    Monitor *m = ref;
    unsigned long r = atomic_load(&m->rd), w = atomic_load(&m->wr);
    // start only once ~40 ms is queued, then follow; keeps latency small and bounded
    int ready = (w - r) >= frames + 1024 || atomic_load(&m->frames) > 0 && (w - r) >= frames;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        float *v = io->mBuffers[b].mData;
        UInt32 ch = io->mBuffers[b].mNumberChannels;
        for (UInt32 i = 0; i < frames; i++) {
            float s = ready ? m->ring[(r + i) % RING] : 0;
            for (UInt32 c = 0; c < ch; c++) v[i * ch + c] = s;
        }
    }
    if (ready) atomic_store(&m->rd, r + frames); else atomic_fetch_add(&m->underruns, 1);
    return 0;
}

static int run_monitor(const char *inUid, const char *outUid, double seconds, float gain)
{
    static Monitor m;
    m.gain = gain;
    setvbuf(stdout, NULL, _IOLBF, 0);
    AudioObjectID inDev = dev_by_uid(inUid), outDev = dev_by_uid(outUid);
    if (inDev == kAudioObjectUnknown || outDev == kAudioObjectUnknown) return 1;
    m.inCh = dev_channels(inDev, kAudioObjectPropertyScopeInput);
    m.outCh = dev_channels(outDev, kAudioObjectPropertyScopeOutput);
    if (!m.inCh || m.inCh > MAXCH || !m.outCh || m.outCh > MAXCH) return 1;
    m.in = make_unit(inDev, 1); m.out = make_unit(outDev, 0);
    if (!m.in || !m.out) return 1;
    AudioStreamBasicDescription fi = fmt(m.inCh, 1), fo = fmt(m.outCh, 1);
    AURenderCallbackStruct icb = { monitor_in_cb, &m }, ocb = { monitor_out_cb, &m };
    OSStatus rc = AudioUnitSetProperty(m.in, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fi, sizeof(fi));
    if (!rc) rc = AudioUnitSetProperty(m.in, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &icb, sizeof(icb));
    if (!rc) rc = AudioUnitSetProperty(m.out, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fo, sizeof(fo));
    if (!rc) rc = AudioUnitSetProperty(m.out, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &ocb, sizeof(ocb));
    if (!rc) rc = AudioUnitInitialize(m.in);
    if (!rc) rc = AudioUnitInitialize(m.out);
    if (!rc) rc = AudioOutputUnitStart(m.in);
    if (!rc) rc = AudioOutputUnitStart(m.out);
    if (!rc) for (double e = 0; e < seconds; e += 0.1) {
        usleep(100000);
        float rms = atomic_load(&m.recentRMS);
        printf("progress elapsed=%.1f rms=%.9f dBFS=%.2f frames=%lu underruns=%lu\n", e + 0.1, rms,
               rms > 0 ? 20 * log10(rms) : -120, atomic_load(&m.frames), atomic_load(&m.underruns));
        if (atomic_load(&m.error)) break;
    }
    AudioOutputUnitStop(m.in); AudioOutputUnitStop(m.out);
    AudioUnitUninitialize(m.in); AudioUnitUninitialize(m.out);
    AudioComponentInstanceDispose(m.in); AudioComponentInstanceDispose(m.out);
    printf("monitor in=%s out=%s setup=%d render=%d frames=%lu underruns=%lu\n", inUid, outUid, (int)rc,
           atomic_load(&m.error), atomic_load(&m.frames), atomic_load(&m.underruns));
    return rc || atomic_load(&m.error) || !atomic_load(&m.frames) ? 1 : 0;
}

int main(int argc, char **argv)
{
    if ((argc == 5 || argc == 6) && !strcmp(argv[1], "monitor")) {
        double seconds = atof(argv[4]);
        float gain = argc == 6 ? (float)atof(argv[5]) : 1.0f;
        if (!isfinite(seconds) || seconds <= 0 || seconds > 600 || !isfinite(gain) || gain < 0 || gain > 8) return 2;
        return run_monitor(argv[2], argv[3], seconds, gain);
    }
    if (argc == 3 && !strcmp(argv[1], "render-test")) return render_test(argv[2]);
    if (argc != 4 || (strcmp(argv[1], "input") && strcmp(argv[1], "tone") && strcmp(argv[1], "speakers"))) {
        fprintf(stderr, "usage: rogaudio-probe input|tone|speakers DEVICE_UID SECONDS | monitor IN_UID OUT_UID SECONDS [GAIN] | render-test PATH\n"); return 2;
    }
    double seconds = atof(argv[3]);
    if (!isfinite(seconds) || seconds <= 0 || seconds > 30) return 2;
    Probe p = {0};
    p.output = strcmp(argv[1], "input") != 0;
    p.music = !strcmp(argv[1], "speakers");
    setvbuf(stdout, NULL, _IOLBF, 0);
    AudioObjectID dev = dev_by_uid(argv[2]);
    if (dev == kAudioObjectUnknown) return 1;
    p.channels = dev_channels(dev, p.output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput);
    if (!p.channels || p.channels > MAXCH) return 1;
    p.unit = make_unit(dev, !p.output);
    if (!p.unit) return 1;
    AudioStreamBasicDescription format = fmt(p.channels, 1);
    AURenderCallbackStruct cb = {probe_cb, &p};
    OSStatus rc = AudioUnitSetProperty(p.unit, kAudioUnitProperty_StreamFormat,
        p.output ? kAudioUnitScope_Input : kAudioUnitScope_Output, p.output ? 0 : 1, &format, sizeof(format));
    if (!rc) rc = AudioUnitSetProperty(p.unit,
        p.output ? kAudioUnitProperty_SetRenderCallback : kAudioOutputUnitProperty_SetInputCallback,
        p.output ? kAudioUnitScope_Input : kAudioUnitScope_Global, 0, &cb, sizeof(cb));
    if (!rc) rc = AudioUnitInitialize(p.unit);
    if (!rc) rc = AudioOutputUnitStart(p.unit);
    if (!rc) for (double elapsed = 0; elapsed < seconds; elapsed += 0.25) {
        usleep((useconds_t)(fmin(0.25, seconds - elapsed) * 1000000));
        float rms = atomic_load(&p.recentRMS);
        printf("progress elapsed=%.2f phase=%d rms=%.9f dBFS=%.2f frames=%lu\n",
            elapsed + 0.25, (int)((elapsed + 0.25) / 4), rms, rms > 0 ? 20 * log10(rms) : -120,
            atomic_load(&p.frames));
    }
    AudioOutputUnitStop(p.unit);
    AudioUnitUninitialize(p.unit);
    AudioComponentInstanceDispose(p.unit);
    double rms = p.samples ? sqrt(p.squares / p.samples) : 0;
    double tone = p.samples ? 2 * hypot(p.toneSin, p.toneCos) / p.samples : 0;
    printf("%s uid=%s channels=%u frames=%lu setup=%d render=%d",
        argv[1], argv[2], p.channels, atomic_load(&p.frames), (int)rc, atomic_load(&p.error));
    if (!p.output) printf(" rms=%.9f dBFS=%.2f peak=%.6f tone1k=%.9f",
        rms, rms ? 20 * log10(rms) : -INFINITY, p.peak, tone);
    else printf(p.music ? " source=ROG-Speaker-Test phases=5" : " frequency=1000 amplitude=0.02");
    putchar('\n');
    return rc || atomic_load(&p.error) || !atomic_load(&p.frames) ? 1 : 0;
}
