// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Local 24H32 service helper. No credentials or hardware identifiers printed.
// Build: clang tools/native_wifi_service.c -framework SystemConfiguration
//        -framework CoreFoundation -o build/native_wifi_service
// Read-only: build/native_wifi_service probe
// Create: sudo build/native_wifi_service create /absolute/private/backup.plist
#include <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int backupPreferences(SCPreferencesRef prefs, const char *path)
{
    CFArrayRef keys = SCPreferencesCopyKeyList(prefs);
    if (!keys) return 0;
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (CFIndex n = 0; n < CFArrayGetCount(keys); n++) {
        CFStringRef key = (CFStringRef)CFArrayGetValueAtIndex(keys, n);
        CFPropertyListRef value = SCPreferencesGetValue(prefs, key);
        if (value) CFDictionarySetValue(dict, key, value);
    }
    CFDataRef data = CFPropertyListCreateData(NULL, dict, kCFPropertyListXMLFormat_v1_0, 0, NULL);
    CFRelease(dict); CFRelease(keys);
    if (!data) return 0;
    FILE *file = fopen(path, "wx"); // never overwrite an earlier backup
    int ok = 0;
    if (file) {
        ok = fwrite(CFDataGetBytePtr(data), 1, CFDataGetLength(data), file) == (size_t)CFDataGetLength(data);
        if (fclose(file)) ok = 0;
    }
    CFRelease(data);
    return ok;
}

int main(int argc, char **argv)
{
    int create = argc > 1 && !strcmp(argv[1], "create");
    if (argc > 1 && strcmp(argv[1], "probe") && !create) return 2;
    if (create && (geteuid() != 0 || argc != 3 || argv[2][0] != '/')) {
        fprintf(stderr, "create requires root and an absolute private backup path\n"); return 2;
    }
    typedef SCNetworkInterfaceRef (*CreateBSD)(CFAllocatorRef, CFStringRef, UInt32);
    CreateBSD find = (CreateBSD)dlsym(RTLD_DEFAULT, "_SCNetworkInterfaceCreateWithBSDName");
    SCNetworkInterfaceRef interface = find ? find(NULL, CFSTR("en9"), 0) : NULL;
    if (!interface) { fprintf(stderr, "en9 lookup failed: %d\n", SCError()); return 1; }
    CFStringRef type = SCNetworkInterfaceGetInterfaceType(interface);
    if (!type || !CFEqual(type, kSCNetworkInterfaceTypeIEEE80211)) {
        fprintf(stderr, "en9 is not classified as IEEE80211; no changes\n"); CFRelease(interface); return 1;
    }
    printf("en9 classified as IEEE80211\n");
    SCPreferencesRef prefs = SCPreferencesCreate(NULL, CFSTR("itlmt-native-test"), NULL);
    if (!prefs) { CFRelease(interface); return 1; }
    CFArrayRef services = SCNetworkServiceCopyAll(prefs);
    int exists = 0;
    if (services) {
        for (CFIndex n = 0; n < CFArrayGetCount(services); n++) {
            SCNetworkServiceRef service = (SCNetworkServiceRef)CFArrayGetValueAtIndex(services, n);
            SCNetworkInterfaceRef x = SCNetworkServiceGetInterface(service);
            CFStringRef bsd = x ? SCNetworkInterfaceGetBSDName(x) : NULL;
            if (bsd && CFEqual(bsd, CFSTR("en9"))) exists = 1;
        }
        CFRelease(services);
    }
    printf("service for en9: %s\n", exists ? "present" : "absent");
    if (!create || exists) { CFRelease(prefs); CFRelease(interface); return 0; }
    if (!SCPreferencesLock(prefs, FALSE)) {
        fprintf(stderr, "preferences busy: %d\n", SCError()); CFRelease(prefs); CFRelease(interface); return 1;
    }
    if (!backupPreferences(prefs, argv[2])) {
        fprintf(stderr, "preferences backup failed; no changes\n");
        SCPreferencesUnlock(prefs); CFRelease(prefs); CFRelease(interface); return 1;
    }
    SCNetworkSetRef set = SCNetworkSetCopyCurrent(prefs);
    SCNetworkServiceRef service = set ? SCNetworkServiceCreate(prefs, interface) : NULL;
    int ok = service && SCNetworkServiceSetName(service, CFSTR("Wi-Fi Native"))
        && SCNetworkServiceEstablishDefaultConfiguration(service)
        && SCNetworkServiceSetEnabled(service, TRUE)
        && SCNetworkSetAddService(set, service);
    int committed = ok && SCPreferencesCommitChanges(prefs);
    int applied = committed && SCPreferencesApplyChanges(prefs);
    if (!committed && service) SCNetworkServiceRemove(service);
    printf("service creation: committed=%d applied=%d error=%d\n", committed, applied, applied ? 0 : SCError());
    if (service) CFRelease(service);
    if (set) CFRelease(set);
    SCPreferencesUnlock(prefs); CFRelease(prefs); CFRelease(interface);
    return applied ? 0 : 1;
}
