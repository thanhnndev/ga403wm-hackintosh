// SPDX-License-Identifier: BSD-3-Clause-Clear
#ifndef ROG_AUDIO_SETTINGS_H
#define ROG_AUDIO_SETTINGS_H
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef struct { char profile[32]; double volume, strength; int muted, noise, micEnabled; } RogAudioSettings;

static int rog_settings_read(const char *path, RogAudioSettings *s)
{
    if (!path) return 0;
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char bytes[16384];
    size_t n = fread(bytes, 1, sizeof(bytes), f);
    int extra = fgetc(f);
    fclose(f);
    if (!n || extra != EOF) return 0;
    CFDataRef data = CFDataCreate(NULL, bytes, n);
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);
    if (!plist) return 0;
    if (CFGetTypeID(plist) != CFDictionaryGetTypeID()) { CFRelease(plist); return 0; }
    CFDictionaryRef d = (CFDictionaryRef)plist;
    CFTypeRef v = CFDictionaryGetValue(d, CFSTR("profile"));
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        char profile[32] = {0};
        if (CFStringGetCString(v, profile, sizeof(profile), kCFStringEncodingUTF8))
            memcpy(s->profile, profile, sizeof(profile));
    }
    v = CFDictionaryGetValue(d, CFSTR("volume"));
    double number;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID() && CFNumberGetValue(v, kCFNumberDoubleType, &number) && isfinite(number))
        s->volume = fmax(-60, fmin(0, number));
    v = CFDictionaryGetValue(d, CFSTR("strength"));
    if (v && CFGetTypeID(v) == CFNumberGetTypeID() && CFNumberGetValue(v, kCFNumberDoubleType, &number) && isfinite(number))
        s->strength = fmax(0, fmin(1, number));
    v = CFDictionaryGetValue(d, CFSTR("muted"));
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) s->muted = CFBooleanGetValue(v);
    v = CFDictionaryGetValue(d, CFSTR("noiseCancellation"));
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) s->noise = CFBooleanGetValue(v);
    v = CFDictionaryGetValue(d, CFSTR("micEnabled"));
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) s->micEnabled = CFBooleanGetValue(v);
    CFRelease(plist);
    return 1;
}
#endif
