// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// Sends APPLE80211_IOC_VIRTUAL_IF_CREATE (0x5e, role 6 = AWDL) through the private IO80211 framework - the same request
// wifip2pd makes when it wants an AWDL interface. Used to exercise the driver's setVIRTUAL_IF_CREATE handler directly,
// without wifip2pd's own capability gate in the way (docs/ROADMAP-AWDL.md, phase 2).
//
// Build: cc -o /tmp/vif_create_test tools/awdl/vif_create_test.m -framework CoreFoundation -framework Foundation -framework IOKit
// Run:   ./vif_create_test [bsdname]        (default en5)
//        ./vif_create_test en5 1            (also sends APPLE80211_IOC_VIRTUAL_IF_DELETE, 0x5f, first)
//
// 25G241 findings baked in (all verified on the machine):
//  * Apple80211BindToInterfaceWithService takes (ref, service, ifname); the other order makes the framework call
//    CFStringGetCString on the Mach port and throw. The name-only Apple80211BindToInterface binds but leaves the handle
//    without a userclient, and the next RawSet crashes.
//  * Apple80211RawSet takes (ref, apple80211req*) - not the classic (ref, cmd, data, len): its disassembly reads rsi+0x18
//    (req_len) and passes rsi+0x20 (req_data) on, so the classic form crashes (the cmd value 0x5e read as a pointer).
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
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

// IOKit/80211/apple80211_ioctl.h: the request the Family's ioctl path reads (cmd at +0x10, len at +0x18, ptr at +0x20 -
// matches apple80211RouteExternal and setVirtualInterfaceCreate).
struct apple80211req {
    char req_if_name[16];      // IFNAMSIZ
    int32_t req_type;          // the ioctl command
    int32_t req_val;
    uint32_t req_len;
    void *req_data;
};

typedef int (*fn_open)(void **handle);
typedef int (*fn_bind)(void *handle, CFStringRef ifname);
typedef int (*fn_bind_svc_a)(void *handle, CFStringRef ifname, io_service_t service);
typedef int (*fn_bind_svc_b)(void *handle, io_service_t service, CFStringRef ifname);
typedef int (*fn_raw_set)(void *handle, struct apple80211req *req);
typedef int (*fn_close)(void *handle);

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    const char *ifname = argc > 1 ? argv[1] : "en5";
    int do_delete = argc > 2 && atoi(argv[2]) != 0;

    void *fw = dlopen("/System/Library/PrivateFrameworks/IO80211.framework/IO80211", RTLD_NOW);
    if (!fw) {
        fprintf(stderr, "dlopen(IO80211): %s\n", dlerror());
        return 1;
    }
    fn_open pOpen = (fn_open)dlsym(fw, "Apple80211Open");
    fn_bind pBind = (fn_bind)dlsym(fw, "Apple80211BindToInterface");
    fn_bind_svc_a pBindSvcA = (fn_bind_svc_a)dlsym(fw, "Apple80211BindToInterfaceWithService");
    fn_bind_svc_b pBindSvcB = (fn_bind_svc_b)dlsym(fw, "Apple80211BindToInterfaceWithService");
    fn_raw_set pRawSet = (fn_raw_set)dlsym(fw, "Apple80211RawSet");
    fn_close pClose = (fn_close)dlsym(fw, "Apple80211Close");
    if (!pOpen || !pRawSet || !pClose) {
        fprintf(stderr, "missing symbols: open=%p rawSet=%p close=%p\n", (void *)pOpen, (void *)pRawSet, (void *)pClose);
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
    int bound = 0;
    // The service-bound call is the one that leaves the handle usable for RawSet on 25G241; both argument orders are tried
    // (the wrong one throws inside the framework).
    if (pBindSvcB && svc) {
        @try {
            rc = pBindSvcB(handle, svc, name);
            printf("BindToInterfaceWithService(service=%#x, %s) rc=%d (0x%x)\n", svc, ifname, rc, rc);
            bound = rc == 0;
        } @catch (NSException *e) {
            printf("BindToInterfaceWithService(service, name) threw: %s\n", e.reason.UTF8String);
        }
    }
    if (!bound && pBindSvcA && svc) {
        @try {
            rc = pBindSvcA(handle, name, svc);
            printf("BindToInterfaceWithService(%s, service=%#x) rc=%d (0x%x)\n", ifname, svc, rc, rc);
            bound = rc == 0;
        } @catch (NSException *e) {
            printf("BindToInterfaceWithService(name, service) threw: %s\n", e.reason.UTF8String);
        }
    }
    if (!bound && pBind) {
        rc = pBind(handle, name);
        printf("BindToInterface(%s) rc=%d (0x%x)\n", ifname, rc, rc);
        bound = rc == 0;
    }
    if (!bound) {
        fprintf(stderr, "no working bind path (service=%#x)\n", svc);
        return 1;
    }

    if (do_delete) {
        struct virt_if_delete_data dd;
        struct apple80211req req;
        memset(&dd, 0, sizeof(dd));
        dd.version = 1;
        memset(&req, 0, sizeof(req));
        strncpy(req.req_if_name, ifname, sizeof(req.req_if_name) - 1);
        req.req_type = 0x5f;
        req.req_len = 0x14;
        req.req_data = &dd;
        rc = pRawSet(handle, &req);
        printf("RawSet(0x5f VIRTUAL_IF_DELETE) rc=%d (0x%x)\n", rc, rc);
    }

    struct virt_if_create_data d;
    struct apple80211req req;
    memset(&d, 0, sizeof(d));
    d.version = 1;
    d.role = 6;                          // AWDL (proximity); 7 = APSTA, 8-10 = NAN
    memset(&req, 0, sizeof(req));
    strncpy(req.req_if_name, ifname, sizeof(req.req_if_name) - 1);
    req.req_type = 0x5e;
    req.req_len = 0x20;
    req.req_data = &d;
    rc = pRawSet(handle, &req);
    printf("RawSet(0x5e VIRTUAL_IF_CREATE, role=%u) rc=%d (0x%x) bsd_name='%.15s'\n", d.role, rc, rc, d.bsd_name);

    pClose(handle);
    if (svc) IOObjectRelease(svc);
    CFRelease(name);
    return rc == 0 ? 0 : 1;
}