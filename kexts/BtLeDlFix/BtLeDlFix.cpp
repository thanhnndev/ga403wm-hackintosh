// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// BtLeDlFix: Lilu plugin that lets BLE devices finish connecting through the MediaTek MT7925 controller.
//
// bluetoothd (macOS 15) walks every new LE connection through
//   VERSION -> FEATURES -> LENGTH -> PHY -> ready
// and in the LENGTH step waits for an HCI "LE Data Length Change" event after it has seen that both sides support
// Extended Data Length. The MT7925 firmware (like any spec-compliant controller whose lengths already match) never
// emits that event, so the link sits in WAIT_FOR_LENGTH until the peer times out and a BLE mouse never connects.
// Apple has a quirk for one chipset id (cmp eax, 8) that skips the step; this plugin makes the quirk unconditional by
// turning "cmp eax, 8" into "cmp eax, eax". Same hook as BlueToolFixup: cs_validate_page, patching the page in memory.
//
// Pattern (bluetoothd x86_64, macOS 15.8.1 / 24H32, __text+0x1e4f69):
//   83 f8 08            cmp   eax, 8          -> 39 c0 90   cmp eax, eax ; nop
//   45 0f b6 f6         movzx r14d, r14b
//   b8 00 00 00 00      mov   eax, 0
//   44 0f 44 f0         cmove r14d, eax

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <Headers/kern_version.hpp>

#include <sys/vnode.h>

#define MODULE_SHORT "btledl"

static const uint8_t kLenOriginal[] = {
    0x83, 0xF8, 0x08, 0x45, 0x0F, 0xB6, 0xF6, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x44, 0x0F, 0x44, 0xF0,
};
static const uint8_t kLenPatched[] = {
    0x39, 0xC0, 0x90, 0x45, 0x0F, 0xB6, 0xF6, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x44, 0x0F, 0x44, 0xF0,
};

static mach_vm_address_t orig_cs_validate {};

static void patched_cs_validate_page(vnode_t vp, memory_object_t pager, memory_object_offset_t page_offset, const void *data,
                                     int *validated_p, int *tainted_p, int *nx_p) {
    char path[PATH_MAX];
    int pathlen = PATH_MAX;
    FunctionCast(patched_cs_validate_page, orig_cs_validate)(vp, pager, page_offset, data, validated_p, tainted_p, nx_p);
    static constexpr size_t dirLength = sizeof("/usr/sbin/") - 1;
    if (vn_getpath(vp, path, &pathlen) == 0 && UNLIKELY(strncmp(path, "/usr/sbin/", dirLength) == 0) &&
        strcmp(path + dirLength, "bluetoothd") == 0) {
        if (KernelPatcher::findAndReplace(const_cast<void *>(data), PAGE_SIZE, kLenOriginal, kLenPatched))
            SYSLOG(MODULE_SHORT, "patched LE data length wait in %s", path);
    }
}

static void pluginStart() {
    SYSLOG(MODULE_SHORT, "start");
    lilu.onPatcherLoadForce([](void *, KernelPatcher &patcher) {
        KernelPatcher::RouteRequest csRoute("_cs_validate_page", patched_cs_validate_page, orig_cs_validate);
        if (!patcher.routeMultipleLong(KernelPatcher::KernelID, &csRoute, 1))
            SYSLOG(MODULE_SHORT, "failed to route cs validation pages");
    });
}

static const char *bootargOff[] {"-btledlfxoff"};
static const char *bootargDebug[] {"-btledlfxdbg"};
static const char *bootargBeta[] {"-btledlfxbeta"};

PluginConfiguration ADDPR(config) {
    xStringify(PRODUCT_NAME),
    parseModuleVersion(xStringify(MODULE_VERSION)),
    LiluAPI::AllowNormal | LiluAPI::AllowInstallerRecovery | LiluAPI::AllowSafeMode,
    bootargOff,
    arrsize(bootargOff),
    bootargDebug,
    arrsize(bootargDebug),
    bootargBeta,
    arrsize(bootargBeta),
    KernelVersion::Monterey,
    KernelVersion::Tahoe,
    pluginStart
};
