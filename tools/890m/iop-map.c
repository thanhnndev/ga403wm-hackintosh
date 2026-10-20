// SPDX-License-Identifier: BSD-3-Clause-Clear
// Fresh, read-only IOPresentment association map. Sign this helper with the
// adjacent entitlements on the already configured development machine.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
int main(void) {
    void *image = dlopen("/System/Library/PrivateFrameworks/IOPresentment.framework/IOPresentment", RTLD_NOW);
    if (!image) { puts(dlerror()); return 1; }
    CFTypeRef (*getMap)(void) = dlsym(image, "IOPresentmentGetMap");
    if (!getMap) { puts(dlerror()); return 2; }
    CFTypeRef map = getMap();
    if (!map) { puts("IOPresentment map unavailable"); return 3; }
    if (CFGetTypeID(map) == CFArrayGetTypeID())
        printf("IOPresentment map entries: %ld\n", (long)CFArrayGetCount((CFArrayRef)map));
    CFShow(map);
    return 0;
}
