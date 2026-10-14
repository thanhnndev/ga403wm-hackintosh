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

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "render-test")) return render_test(argv[2]);
    if (argc != 4 || (strcmp(argv[1], "input") && strcmp(argv[1], "tone") && strcmp(argv[1], "speakers"))) {
        fprintf(stderr, "usage: rogaudio-probe input|tone|speakers DEVICE_UID SECONDS | render-test PATH\n"); return 2;
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
