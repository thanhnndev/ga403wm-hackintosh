// Read-only Wi-Fi discovery diagnostic; prints no MAC, SSID or serial number.
// clang tools/native_wifi_discovery.c -framework IOKit -framework SystemConfiguration
//     -framework CoreFoundation -o build/native_wifi_discovery
#include <IOKit/IOKitLib.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>

int main(void)
{
    CFArrayRef interfaces = SCNetworkInterfaceCopyAll();
    if (!interfaces) return 1;
    for (CFIndex i = 0; i < CFArrayGetCount(interfaces); i++) {
        SCNetworkInterfaceRef x = (SCNetworkInterfaceRef)CFArrayGetValueAtIndex(interfaces, i);
        char bsd[128] = "nil", type[128] = "nil";
        CFStringRef s = SCNetworkInterfaceGetBSDName(x);
        if (s) CFStringGetCString(s, bsd, sizeof(bsd), kCFStringEncodingUTF8);
        s = SCNetworkInterfaceGetInterfaceType(x);
        if (s) CFStringGetCString(s, type, sizeof(type), kCFStringEncodingUTF8);
        printf("SC: bsd=%s type=%s\n", bsd, type);
    }
    CFRelease(interfaces);
    // Read-only BSD-name lookup, as declared in Apple's public configd source.
    // Do not create or modify any network service/preferences.
    typedef SCNetworkInterfaceRef (*CreateBSD)(CFAllocatorRef, CFStringRef, uint32_t);
    CreateBSD createBSD = (CreateBSD)dlsym(RTLD_DEFAULT, "_SCNetworkInterfaceCreateWithBSDName");
    if (createBSD) {
        SCNetworkInterfaceRef x = createBSD(NULL, CFSTR("en9"), 0);
        if (x) {
            char type[128] = "nil";
            CFStringRef s = SCNetworkInterfaceGetInterfaceType(x);
            if (s) CFStringGetCString(s, type, sizeof(type), kCFStringEncodingUTF8);
            printf("SC explicit BSD lookup: en9 type=%s\n", type);
            CFRelease(x);
        } else printf("SC explicit BSD lookup: en9 unavailable error=%d\n", SCError());
    } else printf("SC explicit BSD lookup symbol unavailable\n");
    const char *classes[] = {"itlmt7925WifiInterface", "IOSkywalkNetworkBSDClient", "IONetworkInterface"};
    for (unsigned j = 0; j < sizeof(classes) / sizeof(classes[0]); j++) {
        io_iterator_t it = IO_OBJECT_NULL;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(classes[j]), &it) != KERN_SUCCESS)
            continue;
        io_service_t x;
        while ((x = IOIteratorNext(it))) {
            // Restrict output to class and ancestry, never registry names/properties.
            printf("IOKit: match=%s IONetworkInterface=%d IOSkywalkNetworkInterface=%d\n",
                   classes[j], IOObjectConformsTo(x, "IONetworkInterface"),
                   IOObjectConformsTo(x, "IOSkywalkNetworkInterface"));
            IOObjectRelease(x);
        }
        IOObjectRelease(it);
    }
    return 0;
}
