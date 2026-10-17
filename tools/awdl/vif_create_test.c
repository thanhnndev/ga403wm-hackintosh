// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// Sends APPLE80211_IOC_VIRTUAL_IF_CREATE (0x5e, role 6 = AWDL) through the private IO80211 framework - the same request
// wifip2pd makes when it wants an AWDL interface. Used to exercise the driver's setVIRTUAL_IF_CREATE handler directly,
// without wifip2pd's own capability gate in the way (docs/ROADMAP-AWDL.md, phase 2).
//
// Build: cc -o /private/var/folders/sy/2g2gmh497x77tcxnfkkdtf600000gn/T/opencode/vif_create_test tools/awdl/vif_create_test.c \
//            -framework CoreFoundation -framework IOKit
// Run:   ./vif_create_test [bsdname]        (default en5)
//        ./vif_create_test en5 1            (also deletes the interface first via APPLE80211_IOC_VIRTUAL_IF_DELETE, 0x5f)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// IOKit/80211/apple80211_ioctl.h: u32 version; u8 mac[6]; u16 unk1; u32 role; u8 bsd_name[15] (packed, 0x1f bytes; the
// Family's setVirtualInterfaceCreate clamps the request length to 0x20).
struct virt_if_create_data {
    uint32_t version;
    uint8_t mac[6];
    uint16_t unk1;
    uint32_t role;
    uint8_t bsd_name[15];
    uint8_t pad;
} __attribute__((packed));

// IOKit/80211/apple80211_ioctl.h: u32 version; u8 bsd_name[15] (packed)
struct virt_if_delete_data {
    uint32_t version;
    uint8_t bsd_name[15];
    uint8_t pad;
} __attribute__((packed));

typedef int (*fn_open)(void **handle);
typedef int (*fn_bind)(void *handle, CFStringRef ifname);
typedef int (*fn_bind_svc)(void *handle, CFStringRef ifname, io_service_t service);
typedef int (*fn_raw_set)(void *handle, uint32_t cmd, void *data, size_t len);
typedef int (*fn_close)(void *handle);

static const char *ioctl_name(uint32_t cmd)
{
    switch (cmd) {
    case 0x5e: return "VIRTUAL_IF_CREATE";
    case 0x5f: return "VIRTUAL_IF_DELETE";
    default: return "?";
    }
}

int main(int argc, char **argv)
{
    const char *ifname = argc > 1 ? argv[1] : "en5";
    int do_delete = argc > 2 && atoi(argv[2]) != 0;

    void *fw = dlopen("/System/Library/PrivateFrameworks/IO80211.framework/IO80211", RTLD_NOW);
    if (!fw) {
        fprintf(stderr, "dlopen(IO80211): %s\n", dlerror());
        return 1;
    }
    fn_open pOpen = (fn_open)dlsym(fw, "Apple80211Open");
    fn_bind pBind = (fn_bind)dlsym(fw, "Apple80211BindToInterface");
    fn_bind_svc pBindSvc = (fn_bind_svc)dlsym(fw, "Apple80211BindToInterfaceWithService");
    fn_raw_set pRawSet = (fn_raw_set)dlsym(fw, "Apple80211RawSet");
    fn_close pClose = (fn_close)dlsym(fw, "Apple80211Close");
    if (!pOpen || !pRawSet || !pClose || (!pBind && !pBindSvc)) {
        fprintf(stderr, "missing symbols: open=%p bind=%p bindSvc=%p rawSet=%p close=%p\n",
                (void *)pOpen, (void *)pBind, (void *)pBindSvc, (void *)pRawSet, (void *)pClose);
        return 1;
    }

    void *handle = NULL;
    int rc = pOpen(&handle);
    if (rc != 0 || !handle) {
        fprintf(stderr, "Apple80211Open rc=%d (0x%x)\n", rc, rc);
        return 1;
    }

    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("itlmt7925WifiInterface"));
    CFStringRef name = CFStringCreateWithCString(NULL, ifname, kCFStringEncodingUTF8);
    if (pBindSvc && svc) {
        rc = pBindSvc(handle, name, svc);
        printf("BindToInterfaceWithService(%s, service=%#x) rc=%d (0x%x)\n", ifname, svc, rc, rc);
    } else if (pBind) {
        rc = pBind(handle, name);
        printf("BindToInterface(%s) rc=%d (0x%x)\n", ifname, rc, rc);
    } else {
        fprintf(stderr, "no bind path (svc=%#x)\n", svc);
        return 1;
    }
    if (rc != 0) return 1;

    if (do_delete) {
        struct virt_if_delete_data dd;
        memset(&dd, 0, sizeof(dd));
        dd.version = 1;
        rc = pRawSet(handle, 0x5f, &dd, 0x14);
        printf("RawSet(0x5f %s) rc=%d (0x%x)\n", ioctl_name(0x5f), rc, rc);
    }

    struct virt_if_create_data d;
    memset(&d, 0, sizeof(d));
    d.version = 1;
    d.role = 6;                          // AWDL (proximity); 7 = APSTA, 8-10 = NAN
    rc = pRawSet(handle, 0x5e, &d, 0x20);
    printf("RawSet(0x5e %s, role=%u) rc=%d (0x%x) bsd_name='%.15s'\n",
           ioctl_name(0x5e), d.role, rc, rc, d.bsd_name);

    pClose(handle);
    if (svc) IOObjectRelease(svc);
    CFRelease(name);
    return rc == 0 ? 0 : 1;
}
