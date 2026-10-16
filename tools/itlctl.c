// itlctl - run-time control of the itlmt7925 core (must run as root; the driver checks the administrator privilege).
//
//   cc -o itlctl tools/itlctl.c -framework IOKit -framework CoreFoundation
//   sudo ./itlctl itl_lvl=4            reconnect at fast level 4
//   sudo ./itlctl itl_no160=1          run 160 MHz channels as 80 MHz (with the next reconnect)
//   sudo ./itlctl itl_reo=10           reorder timeout 10 ms
//   sudo ./itlctl itl_pwr=40           send the CLC + SKU power tables now, ceiling 40 = 20 dBm (0.5 dBm units)
// Several key=value pairs in one call are applied together (no160 first, then the level, so the reconnect sees both).
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: itlctl key=value ...\n");
        return 2;
    }
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("itlmt7925"));
    if (!svc) {
        fprintf(stderr, "itlctl: no itlmt7925 service\n");
        return 1;
    }
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);
    for (int i = 1; i < argc; i++) {
        char *eq = strchr(argv[i], '=');
        if (!eq) {
            fprintf(stderr, "itlctl: bad argument %s\n", argv[i]);
            return 2;
        }
        *eq = 0;
        int v = atoi(eq + 1);
        CFStringRef k = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
        CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        CFDictionarySetValue(d, k, n);
        CFRelease(k);
        CFRelease(n);
    }
    kern_return_t kr = IORegistryEntrySetCFProperties(svc, d);
    printf("itlctl: %s (0x%x)\n", kr == KERN_SUCCESS ? "ok" : "refused", kr);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : 1;
}
