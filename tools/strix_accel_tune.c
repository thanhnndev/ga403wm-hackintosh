// Live tunables for StrixAccel >= 0.1.9 (no reboot): writes properties on the StrixAccelerator registry entry.
//   strix_accel_tune                      print current tunables and present counters
//   strix_accel_tune Mode=0|1 Async=0|1 SrcCache=0..4 Block=32..4096 Probe=1 Reset=1
// SrcCache since 0.1.10: 0 default, 1 copyback, 2 write-through; 3/4 are accepted but aliased to default
// (uncached/WC source reads stall the pipe, measured 188 ms vs 0.6 ms on 0.1.9).
// Build: cc -O2 tools/strix_accel_tune.c -framework IOKit -framework CoreFoundation -o strix_accel_tune
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void show(const void *k, const void *v, void *c)
{
    char key[160];
    if (!CFStringGetCString((CFStringRef)k, key, sizeof key, kCFStringEncodingUTF8) || strncmp(key, "StrixAccel,", 11)) return;
    CFTypeRef t = v;
    if (CFGetTypeID(t) == CFNumberGetTypeID()) {
        long long n = 0;
        CFNumberGetValue(t, kCFNumberSInt64Type, &n);
        printf("%-40s %lld\n", key, n);
    } else if (CFGetTypeID(t) == CFStringGetTypeID()) {
        char s[128];
        CFStringGetCString(t, s, sizeof s, kCFStringEncodingUTF8);
        printf("%-40s %s\n", key, s);
    }
}

int main(int argc, char **argv)
{
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("StrixAccelerator"));
    if (!svc) { fprintf(stderr, "StrixAccelerator not found\n"); return 1; }
    if (argc > 1) {
        CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        for (int i = 1; i < argc; i++) {
            char *eq = strchr(argv[i], '=');
            if (!eq) { fprintf(stderr, "bad arg %s\n", argv[i]); return 2; }
            *eq = 0;
            char key[96];
            snprintf(key, sizeof key, "StrixAccel,%s", argv[i]);
            long long v = atoll(eq + 1);
            CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
            CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt64Type, &v);
            CFDictionarySetValue(d, k, n);
        }
        kern_return_t kr = IORegistryEntrySetCFProperties(svc, d);
        if (kr) { fprintf(stderr, "set failed: 0x%x\n", kr); return 3; }
    }
    CFMutableDictionaryRef p = NULL;
    IORegistryEntryCreateCFProperties(svc, &p, NULL, 0);
    if (p) CFDictionaryApplyFunction(p, show, NULL);
    return 0;
}
