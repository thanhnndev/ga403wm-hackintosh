// SPDX-License-Identifier: BSD-3-Clause-Clear
// Diagnostic refresh only: no device open, GPU register or EFI writes.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>

static int registryIDEquals(io_service_t service, CFStringRef key, unsigned value) {
    CFTypeRef data = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    int equal = 0;
    if (data && CFGetTypeID(data) == CFDataGetTypeID() && CFDataGetLength(data) == 4) {
        const UInt8 *b = CFDataGetBytePtr(data);
        unsigned id = (unsigned)b[0] | ((unsigned)b[1] << 8) |
                      ((unsigned)b[2] << 16) | ((unsigned)b[3] << 24);
        equal = id == value;
    }
    if (data) CFRelease(data);
    return equal;
}

static void inspectPCIMatching(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOPCIDevice"), &iterator);
    if (kr != KERN_SUCCESS) { printf("PCI matching failed: 0x%x\n", kr); return; }
    unsigned matches = 0;
    io_service_t pci;
    while ((pci = IOIteratorNext(iterator))) {
        if (registryIDEquals(pci, CFSTR("vendor-id"), 0x1002) &&
            registryIDEquals(pci, CFSTR("device-id"), 0x150e)) ++matches;
        IOObjectRelease(pci);
    }
    IOObjectRelease(iterator);
    printf("Current matched PCI registry targets: %u (properties only)\n", matches);
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "--inspect") && strcmp(argv[1], "--refresh"))) {
        fprintf(stderr, "Usage: %s --inspect|--refresh\n", argv[0]); return 2;
    }
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("StrixProbe"), &iterator);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "Matching failed: 0x%x\n", kr); return 1; }
    io_service_t service = IOIteratorNext(iterator);
    io_service_t extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!service || extra) {
        if (service) IOObjectRelease(service);
        if (extra) IOObjectRelease(extra);
        fprintf(stderr, "Expected exactly one StrixProbe service\n"); return 1;
    }
    CFTypeRef support = IORegistryEntryCreateCFProperty(service,
        CFSTR("Refresh,Supported"), kCFAllocatorDefault, 0);
    int supported = support && CFEqual(support, kCFBooleanTrue);
    if (support) CFRelease(support);
    printf("Refresh supported: %s\n", supported ? "yes" : "no");
    if (!strcmp(argv[1], "--inspect")) inspectPCIMatching();
    if (!strcmp(argv[1], "--refresh")) {
        if (!supported) {
            fprintf(stderr, "Loaded probe has no refresh endpoint; no request sent\n");
            IOObjectRelease(service); return 2;
        }
        const void *keys[] = { CFSTR("Refresh") };
        const void *values[] = { kCFBooleanTrue };
        CFDictionaryRef request = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!request) { IOObjectRelease(service); return 1; }
        kr = IORegistryEntrySetCFProperties(service, request);
        CFRelease(request);
        printf("Refresh result: 0x%x\n", kr);
    }
    IOObjectRelease(service);
    return kr == KERN_SUCCESS ? 0 : 1;
}
