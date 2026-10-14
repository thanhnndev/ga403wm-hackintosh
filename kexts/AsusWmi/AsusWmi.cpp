// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AsusWmi: the platform half of asusctl / ROG Control Center for macOS, on the GA403WM (ROG Zephyrus G14 2025).
//
// macOS has no driver for ASUS's ACPI WMI device (ATKD, _UID "ATK", GUID 97845ED0-4E6D-11DE-8A39-0800200C9A66), so the
// firmware stays in whatever performance profile and power limits it booted with, and nothing can change them. This kext
// calls the device's WMNB method the way Linux does (asus-wmi: method id + a 20-byte argument buffer; DSTS reads a device,
// DEVS sets it) and exposes the settings asusctl manages as a user client (asuswmi_abi.h, used by the RogControl menu bar
// app) and as sysctls.
//
// Credits (see NOTICE.md): device ids, the DSTS/DEVS convention, the profile values, the fan curve packing and the GA403WM
// power-limit ranges come from the Linux drivers asus-wmi (Corentin Chary and contributors, GPL-2.0-or-later) and
// asus-armoury (Luke Jones, GPL-2.0), and the feature set from asusctl / rog-control-center (asus-linux.org, Luke Jones and
// contributors, MPL-2.0). No code is copied from them; this file only uses those documented interface values.
//
// What this BIOS does with them (DSDT, docs/ASUSCTL-MACOS.md): PPT writes go to AMD ALIB 0x0C and cannot be read back; the
// profile and the charge limit go through a software SMI; fan curves are EC fields (DEVS 0x00110024/25 sets FMAE, the
// EC's manual fan flag). As asus-armoury does for this board (requires_fan_curve), power limits are only accepted while a
// custom fan curve is active, and only within the range for the current power source (AC or battery).
//
//   sysctl debug.asuswmi.status            (read) profile, charge limit, fans, raw DSTS of the known devices
//   sysctl debug.asuswmi.profile=<0|1|2>   0 balanced, 1 turbo (overboost), 2 silent   (throttle_thermal_policy 0x00120075)
//   sysctl debug.asuswmi.fan_custom=<0|1>  1: the current profile's firmware fan curves as custom curves (fans "manual",
//                                          unchanged duty; enables the power limits), 0: back to the profile's own
//   sysctl debug.asuswmi.ppt_spl=<W>       PL1 sustained   AC 15..80 W, battery 15..35 W   (0x001200A3)
//   sysctl debug.asuswmi.ppt_sppt=<W>      PL2 slow        AC 25..80 W, battery 25..35 W   (0x001200A0)
//   sysctl debug.asuswmi.ppt_fppt=<W>      PL3 fast        AC 35..80 W, battery 35..65 W   (0x001200C1)
//   sysctl debug.asuswmi.charge_limit=<%>  battery charge end 20..100 (0x00120057)
//   sysctl debug.asuswmi.probe=<dev id>    then read debug.asuswmi.probe: raw DSTS of any device id (exploration)
//   sysctl debug.asuswmi.backlight[=<n>]   EC brightness level 0..200 through AWMI.WMAA (the NVIDIA WMI-EC backlight method:
//                                          GUID 603E9613-EF25-4338-A3D0-C46177516DB7, EC fields GBLD / SBLD). The BIOS says the
//                                          source is AUX: the OLED ignores this level; NullMoth sets the panel through NVKMS, and
//                                          BrightnessKeys turns the brightness keys (Notify 0x86 / 0x87 on PEGP.EDP1) into macOS's
//   sysctl debug.asuswmi.kbd[=<0..3>]      keyboard backlight (N-KEY HID 0b05:19b6, feature report 0x5A, as G-Helper / hid-asus)
//   sysctl debug.asuswmi.slash[=<packed>]  Slash lighting, ASUS_SLASH_PACK(mode, brightness 0..3, interval 0..5) (report 0x5D)
//   sysctl debug.asuswmi.key=<code>        emulates a hotkey through WMNB DEVS 0x00100021 (EC0.SKEY): 0x20 brightness up,
//                                          0x10 down, 0xC4 / 0xC5 keyboard light up / down, 0xAE fan key (testing)
// Hotkeys: the EC queues a code with ATKD.IANE and sends Notify (ATKD, 0xFF); _WED (0xFF) returns the queued codes. Handled
// here: 0xC4 / 0xC5 keyboard light up / down (Fn+F3 / F2), 0xAE (Fn+F5) next profile, 0xB3 (Fn+F4) Slash on / off; every
// code is logged in asus-log ("key xx").
//   sysctl debug.asuswmi.battery           ECOK, _BIF and _BST of BAT1 as the firmware returns them
//   sysctl debug.asuswmi.ec_reg=1          runs EC0._REG (3, 1) (EmbeddedControl space available) if ECOK is still 0
//   sysctl debug.asuswmi.dumpacpi=1        publishes the DSDT and SSDTs as registry properties acpi-DSDT, acpi-SSDT-<n>
// sysctl writes need root.
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/acpi/IOACPIPlatformExpert.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <kern/thread_call.h>
#include <sys/sysctl.h>
#include <stdarg.h>
#include <string.h>
#include "asuswmi_abi.h"

#define M_INIT 0x54494E49
#define M_SFUN 0x4E554653
#define M_DSTS 0x53545344
#define M_DEVS 0x53564544
#define WMI_UNSUPPORTED 0xFFFFFFFEu
#define DSTS_PRESENT 0x00010000u

#define DEV_PROFILE   0x00120075
#define DEV_PPT_SPPT  0x001200A0
#define DEV_PPT_SPL   0x001200A3
#define DEV_PPT_FPPT  0x001200C1
#define DEV_NV_BOOST  0x001200C0
#define DEV_NV_TEMP   0x001200C2
#define DEV_NV_TGP    0x00120099
#define DEV_RSOC      0x00120057
#define DEV_GPU_MUX   0x00090016
#define DEV_DGPU      0x00090020
#define DEV_CPU_FAN   0x00110013
#define DEV_GPU_FAN   0x00110014
#define DEV_CPU_CURVE 0x00110024
#define DEV_GPU_CURVE 0x00110025
#define DEV_PANEL_OD  0x00050019
#define DEV_HOTKEY    0x00100021      // DEVS: EC0.SKEY (code), the hotkey dispatcher

struct Known { uint32_t id; const char *name; };
static const Known kKnown[] = {
    { DEV_PROFILE, "profile" }, { DEV_RSOC, "charge_limit" }, { DEV_CPU_FAN, "cpu_fan" }, { DEV_GPU_FAN, "gpu_fan" },
    { DEV_NV_BOOST, "nv_dynamic_boost" }, { DEV_NV_TEMP, "nv_temp_target" }, { DEV_NV_TGP, "nv_base_tgp" },
    { DEV_GPU_MUX, "gpu_mux" }, { DEV_DGPU, "dgpu_disable" }, { DEV_PANEL_OD, "panel_overdrive" },
};

// asus-armoury power_limits for DMI board GA403WM: { min, max } per source
struct Range { int lo, hi; };
static const Range kAcPpt[3] = { { 15, 80 }, { 25, 80 }, { 35, 80 } };   // spl, sppt, fppt
static const Range kDcPpt[3] = { { 15, 35 }, { 25, 35 }, { 35, 65 } };
static const uint32_t kPptDev[3] = { DEV_PPT_SPL, DEV_PPT_SPPT, DEV_PPT_FPPT };

class AsusWmi : public IOService {
    OSDeclareDefaultStructors(AsusWmi)
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                           IOUserClient **handler) override;
    IOACPIPlatformDevice *atk = nullptr;
    IOACPIPlatformDevice *acad = nullptr;
    IOLock *lock = nullptr;
    char log[900] = {0};
    size_t loglen = 0;
    bool fanCustom = false;
    uint32_t pptSet[3] = {0, 0, 0};
    void say(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
    bool wmi5(uint32_t method, const uint32_t a[5], uint32_t *ret);
    bool wmi(uint32_t method, uint32_t a0, uint32_t a1, uint32_t *ret)
    {
        uint32_t a[5] = { a0, a1, 0, 0, 0 };
        return wmi5(method, a, ret);
    }
    bool dsts(uint32_t dev, uint32_t *ret) { return wmi(M_DSTS, dev, 0, ret) && *ret != WMI_UNSUPPORTED && *ret != ~0u; }
    bool devs(uint32_t dev, uint32_t val, uint32_t *ret) { return wmi(M_DEVS, dev, val, ret) && *ret != WMI_UNSUPPORTED; }
    bool onAC();
    // the setters below run with `lock` held and return an IOReturn
    IOReturn setValue(int what, int value);
    IOReturn fanRead(int fan, int profile, uint8_t out[16]);
    IOReturn fanWrite(int fan, const uint8_t in[16]);
    IOReturn fanReset();
    IOReturn fanCustomFromFirmware();
    void getState(uint32_t st[ASUS_ST_COUNT]);
    void dumpAcpi();
    // profile and charge limit as last set: DSTS on this BIOS returns 3 for the profile and 0 for the charge limit
    int curProfile = -1, curCharge = -1;
    // EC brightness level through the NVIDIA WMI-EC method (AWMI.WMAA)
    IOACPIPlatformDevice *awmi = nullptr, *bat = nullptr, *ec = nullptr;
    uint32_t blMaxLevel = 0;
    bool wmaa(uint32_t method, uint32_t mode, uint32_t val, uint32_t *ret);
    bool blGet(uint32_t *lvl) { return blMaxLevel && wmaa(1, 0, 0, lvl); }
    IOReturn blSet(int lvl);
    // N-KEY keyboard (HID 0b05:19b6): backlight (feature report 0x5A) and Slash lighting (0x5D), sent as G-Helper does
    int kbdLevel = -1;
    int64_t slashSet = -1;
    bool hidSeen = false;
    IOReturn hidFeature(const uint8_t *cmd, size_t n, size_t total);
    IOReturn kbdSet(int level);
    IOReturn slashApply(uint32_t packed);
    // hotkeys: Notify (ATKD, 0xFF), codes from _WED (0xFF), handled on a thread call
    IONotifier *atkNotifier = nullptr;
    thread_call_t evCall = nullptr;
    uint32_t lastKey = 0, keySequence = 0;
    void events();
    void hotkey(uint32_t code);
    bool battery(uint32_t out[4], char *txt, size_t txtLen);
    IOReturn ecReg();
    void findAcpi();
};
OSDefineMetaClassAndStructors(AsusWmi, IOService)

static AsusWmi *gSelf;
static char gStatus[1024];
static uint32_t gProbeDev, gProbeVal;
static bool gProbeOk;

void AsusWmi::say(const char *fmt, ...)
{
    char line[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    IOLog("AsusWmi: %s\n", line);
    size_t n = strlen(line);
    if (loglen + n + 2 >= sizeof(log)) {                      // keep the newest: drop the oldest entries
        size_t cut = 0;
        while (cut < loglen && (loglen - cut) + n + 2 >= sizeof(log)) {
            while (cut < loglen && log[cut] != ';') cut++;
            if (cut < loglen) cut++;
        }
        memmove(log, log + cut, loglen - cut);
        loglen -= cut;
    }
    memcpy(log + loglen, line, n);
    loglen += n;
    log[loglen++] = ';';
    log[loglen] = 0;
    setProperty("asus-log", log);
}

// ATKD.WMNB(instance 0, method id, buffer { arg0 .. arg4 }) -> integer, as wmi_evaluate_method() with the asus-wmi args.
// The buffer must be 20 bytes: this BIOS's WMNB starts with CreateDWordField (Arg2, 0x10, IIA4), and a shorter buffer
// aborts the method (AE_AML_BUFFER_LIMIT) before it looks at the method id; Linux's struct bios_args is 5 dwords too.
static bool wmiCall(IOACPIPlatformDevice *atk, uint32_t method, const uint32_t a[5], OSObject **result)
{
    OSNumber *inst = OSNumber::withNumber(0ull, 32), *mid = OSNumber::withNumber((unsigned long long)method, 32);
    OSData *buf = OSData::withBytes(a, 5 * sizeof(uint32_t));
    bool ok = false;
    if (inst && mid && buf) {
        OSObject *params[3] = { inst, mid, buf };
        ok = atk->evaluateObject("WMNB", result, params, 3) == kIOReturnSuccess;
    }
    if (inst) inst->release();
    if (mid) mid->release();
    if (buf) buf->release();
    return ok;
}

bool AsusWmi::wmi5(uint32_t method, const uint32_t a[5], uint32_t *ret)
{
    OSObject *o = nullptr;
    bool ok = wmiCall(atk, method, a, &o);
    OSNumber *n = o ? OSDynamicCast(OSNumber, o) : nullptr;
    *ret = n ? n->unsigned32BitValue() : 0;
    ok = ok && n;
    if (o) o->release();
    return ok;
}

// AC adapter state from ACPI (ACPI0003 _PSR); without one, assume battery: the battery ranges are the lower ones.
bool AsusWmi::onAC()
{
    if (!acad) {
        OSDictionary *m = IOService::nameMatching("ACPI0003");
        if (m) {
            IOService *s = IOService::copyMatchingService(m);
            m->release();
            acad = s ? OSDynamicCast(IOACPIPlatformDevice, s) : nullptr;
            if (s && !acad) s->release();
        }
    }
    UInt32 r = 0;
    return acad && acad->evaluateInteger("_PSR", &r) == kIOReturnSuccess && r != 0;
}

// An ACPI namespace node by its 4-character name, searched in the IOACPIPlane (retained). nameMatching() does not work for
// these: their IOName / "name" is the _HID (AWMI and ATKD are both "PNP0C14", EC0 is "PNP0C09").
static IOACPIPlatformDevice *acpiNamed(const char *name)
{
    const IORegistryPlane *plane = IORegistryEntry::getPlane("IOACPIPlane");
    IORegistryEntry *root = plane ? IORegistryEntry::fromPath("/", plane) : nullptr;
    if (!root) return nullptr;
    IOACPIPlatformDevice *r = nullptr;
    IORegistryIterator *it = IORegistryIterator::iterateOver(root, plane, kIORegistryIterateRecursively);
    if (it) {
        while (IORegistryEntry *e = it->getNextObject()) {
            IOACPIPlatformDevice *d = OSDynamicCast(IOACPIPlatformDevice, e);
            if (d && !strcmp(d->getName(plane), name)) { d->retain(); r = d; break; }
        }
        it->release();
    }
    root->release();
    return r;
}

void AsusWmi::findAcpi()
{
    awmi = acpiNamed("AWMI");
    if (awmi && awmi->validateObject("WMAA") != kIOReturnSuccess) { awmi->release(); awmi = nullptr; }
    bat = acpiNamed("BAT1");
    ec = acpiNamed("EC0");
    uint32_t m = 0;
    if (awmi && wmaa(1, 2, 0, &m) && m > 0 && m <= 0xffff) blMaxLevel = m;   // mode 2: the maximum level (0xC8 here)
    say("acpi: AWMI %s (backlight max %u), BAT1 %s, EC0 %s", awmi ? "yes" : "no", blMaxLevel, bat ? "yes" : "no", ec ? "yes" : "no");
}

// AWMI.WMAA (instance 0, method, buffer { mode, value, ... }): method 1 = level (mode 0 get, 1 set, 2 max), method 2 =
// brightness source (Linux nvidia-wmi-ec-backlight; this BIOS says 3, "AUX", but its level method goes to the EC anyway).
bool AsusWmi::wmaa(uint32_t method, uint32_t mode, uint32_t val, uint32_t *ret)
{
    if (!awmi) return false;
    uint32_t b[6] = { mode, val, 0, 0, 0, 0 };
    OSNumber *inst = OSNumber::withNumber(0ull, 32), *mid = OSNumber::withNumber((unsigned long long)method, 32);
    OSData *buf = OSData::withBytes(b, sizeof(b));
    OSObject *o = nullptr;
    bool ok = false;
    if (inst && mid && buf) {
        OSObject *params[3] = { inst, mid, buf };
        ok = awmi->evaluateObject("WMAA", &o, params, 3) == kIOReturnSuccess;
    }
    OSNumber *n = o ? OSDynamicCast(OSNumber, o) : nullptr;
    if (ret) *ret = n ? n->unsigned32BitValue() : 0;
    ok = ok && n;
    if (o) o->release();
    if (inst) inst->release();
    if (mid) mid->release();
    if (buf) buf->release();
    return ok;
}

IOReturn AsusWmi::blSet(int lvl)
{
    if (!blMaxLevel) return kIOReturnUnsupported;
    if (lvl < 0) lvl = 0;
    if (lvl > (int)blMaxLevel) lvl = (int)blMaxLevel;
    uint32_t r = 0;
    return wmaa(1, 1, (uint32_t)lvl, &r) ? kIOReturnSuccess : kIOReturnIOError;
}

// ---------------------------------------------------------------------------------------------------------------------------
// N-KEY keyboard HID: the device is looked up for every command (it is re-created after sleep or a USB reset). The kernel
// can send feature reports to it; user space would need Input Monitoring for that.
// ---------------------------------------------------------------------------------------------------------------------------
static IOHIDDevice *copyKbd()
{
    OSDictionary *m = IOService::serviceMatching("IOHIDDevice");
    if (!m) return nullptr;
    OSIterator *it = IOService::getMatchingServices(m);
    m->release();
    IOHIDDevice *r = nullptr;
    if (it) {
        while (OSObject *o = it->getNextObject()) {
            IOHIDDevice *d = OSDynamicCast(IOHIDDevice, o);
            OSNumber *v = d ? OSDynamicCast(OSNumber, d->getProperty(kIOHIDVendorIDKey)) : nullptr;
            OSNumber *p = d ? OSDynamicCast(OSNumber, d->getProperty(kIOHIDProductIDKey)) : nullptr;
            if (v && p && v->unsigned32BitValue() == 0x0b05 && p->unsigned32BitValue() == 0x19b6) { d->retain(); r = d; break; }
        }
        it->release();
    }
    return r;
}

// One feature report: cmd[0] is the report id, the rest is zero-padded to `total` bytes (report id included).
IOReturn AsusWmi::hidFeature(const uint8_t *cmd, size_t n, size_t total)
{
    uint8_t buf[128];
    if (!n || n > total || total > sizeof(buf)) return kIOReturnBadArgument;
    IOHIDDevice *d = copyKbd();
    if (!d) return kIOReturnNotFound;
    hidSeen = true;
    bzero(buf, total);
    memcpy(buf, cmd, n);
    IOBufferMemoryDescriptor *md = IOBufferMemoryDescriptor::withBytes(buf, total, kIODirectionOut);
    IOReturn r = md ? d->setReport(md, kIOHIDReportTypeFeature, cmd[0]) : kIOReturnNoMemory;
    if (md) md->release();
    d->release();
    return r;
}

static const uint8_t kAsusMagic[14] = { 'A', 'S', 'U', 'S', ' ', 'T', 'e', 'c', 'h', '.', 'I', 'n', 'c', '.' };

// G-Helper Aura.DirectBrightness / hid-asus asus_kbd_backlight_set: 5A BA C5 C4 <level>, after the 5A "ASUS Tech.Inc." init.
IOReturn AsusWmi::kbdSet(int level)
{
    if (level < 0 || level > 3) return kIOReturnBadArgument;
    uint8_t init[15] = { 0x5A };
    memcpy(init + 1, kAsusMagic, sizeof(kAsusMagic));
    const uint8_t set[5] = { 0x5A, 0xBA, 0xC5, 0xC4, (uint8_t)level };
    IOReturn r = hidFeature(init, sizeof(init), 63);
    if (r == kIOReturnSuccess) r = hidFeature(set, sizeof(set), 63);
    if (r == kIOReturnSuccess) kbdLevel = level;
    say("kbd %d -> %08x", level, r);
    return r;
}

// G-Helper SlashDeviceAura (report 0x5D, 128 bytes) for this keyboard: wake up, enable, init, mode, options, save; off = disable.
static const uint8_t kSlashCode[ASUS_SLASH_MODE_COUNT] = { 0x06, 0x10, 0x12, 0x13, 0x1D, 0x1A, 0x19, 0x25,
                                                           0x24, 0x26, 0x32, 0x33, 0x34, 0x42, 0x43, 0x44 };

IOReturn AsusWmi::slashApply(uint32_t v)
{
    uint32_t mode = ASUS_SLASH_MODE(v), br = ASUS_SLASH_BRIGHT(v), iv = ASUS_SLASH_INTERVAL(v);
    if (mode >= ASUS_SLASH_MODE_COUNT || br > 3 || iv > 5 || (v >> 16)) return kIOReturnBadArgument;
    struct Pkt { uint8_t n; uint8_t b[17]; };
    Pkt p[9];
    int np = 0;
    p[np] = { 15, { 0x5D } }; memcpy(p[np].b + 1, kAsusMagic, sizeof(kAsusMagic)); np++;
    p[np++] = { 2, { 0x5D, 0xC2 } };
    p[np++] = { 5, { 0x5D, 0xD1, 0x01, 0x00, 0x01 } };
    p[np++] = { 6, { 0x5D, 0xD8, 0x02, 0x00, 0x01, (uint8_t)(br ? 0x00 : 0x80) } };               // enabled
    if (br) {
        p[np++] = { 6, { 0x5D, 0xD7, 0x00, 0x00, 0x01, 0xAC } };                                   // init
        p[np++] = { 6, { 0x5D, 0xD2, 0x02, 0x01, 0x08, 0xAB } };
        p[np++] = { 17, { 0x5D, 0xD3, 0x04, 0x00, 0x0C, 0x01, kSlashCode[mode], 0x02, 0x42, 0x03, 0x13, 0x04, 0x11, 0x05, 0x12,
                          0x06, 0x13 } };                                                           // mode
        p[np++] = { 13, { 0x5D, 0xD3, 0x03, 0x01, 0x08, 0xAB, 0xFF, 0x01, 0x01, 0x06, (uint8_t)(br * 85), 0xFF, (uint8_t)iv } };
        p[np++] = { 6, { 0x5D, 0xD4, 0x00, 0x00, 0x01, 0xAB } };                                   // save
    }
    IOReturn r = kIOReturnSuccess;
    for (int i = 0; i < np && r == kIOReturnSuccess; i++) r = hidFeature(p[i].b, p[i].n, 128);
    if (r == kIOReturnSuccess) slashSet = v;
    say("slash mode %u bright %u interval %u -> %08x", mode, br, iv, r);
    return r;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Hotkeys
// ---------------------------------------------------------------------------------------------------------------------------
void AsusWmi::hotkey(uint32_t code)
{
    lastKey = code;
    keySequence++;
    say("key %02x", code);
    switch (code) {
    case 0xC4: kbdSet(kbdLevel < 0 ? 1 : (kbdLevel < 3 ? kbdLevel + 1 : 3)); break;     // Fn+F3
    case 0xC5: kbdSet(kbdLevel < 0 ? 0 : (kbdLevel > 0 ? kbdLevel - 1 : 0)); break;     // Fn+F2
    case 0xAE: setValue(ASUS_SET_PROFILE, curProfile < 0 ? 1 : (curProfile + 1) % 3); break;   // Fn+F5: as asus-wmi
    case 0xB3: {                                                                         // Fn+F4: Slash on / off
        uint32_t s = slashSet >= 0 ? (uint32_t)slashSet : ASUS_SLASH_PACK(0, 0, 0);
        slashApply(ASUS_SLASH_PACK(ASUS_SLASH_MODE(s), ASUS_SLASH_BRIGHT(s) ? 0 : 2, ASUS_SLASH_INTERVAL(s)));
        break;
    }
    default: break;
    }
}

void AsusWmi::events()
{
    IOLockLock(lock);
    for (int i = 0; i < 16; i++) {                           // the BIOS queue holds 16 codes
        OSNumber *arg = OSNumber::withNumber(0xFFull, 32);
        OSObject *params[1] = { arg }, *o = nullptr;
        IOReturn r = arg ? atk->evaluateObject("_WED", &o, params, 1) : kIOReturnNoMemory;
        if (arg) arg->release();
        OSNumber *n = o ? OSDynamicCast(OSNumber, o) : nullptr;
        uint64_t code = n ? n->unsigned64BitValue() : ~0ull;
        if (o) o->release();
        if (r != kIOReturnSuccess || code == 0 || code > 0xffff) break;                 // Ones: queue empty
        hotkey((uint32_t)code);
    }
    IOLockUnlock(lock);
}

static void evThread(thread_call_param_t p0, thread_call_param_t) { ((AsusWmi *)p0)->events(); }

static IOReturn atkNotify(void *target, void *, UInt32 type, IOService *, void *arg, vm_size_t)
{
    AsusWmi *self = (AsusWmi *)target;
    if (type == kIOACPIMessageDeviceNotification && arg && *(UInt32 *)arg == 0xFF && self->evCall) thread_call_enter(self->evCall);
    return kIOReturnSuccess;
}

// BAT1 as the firmware reports it. _BIF/_BST only read the EC while ECOK is set (EC0._REG with space 3); otherwise they
// return their initial packages (capacity 5, which is what SMCBatteryManager showed).
bool AsusWmi::battery(uint32_t out[4], char *txt, size_t txtLen)
{
    memset(out, 0, 4 * sizeof(uint32_t));
    UInt32 ecok = 0xff, okec = 0xff;
    if (ec) { ec->evaluateInteger("ECOK", &ecok); ec->evaluateInteger("OKEC", &okec); }
    size_t n = txt ? (size_t)snprintf(txt, txtLen, "ECOK=%u OKEC=%u", ecok, okec) : 0;
    if (!bat) return false;
    bool ok = false;
    const char *const meth[2] = { "_BIF", "_BST" };
    for (int k = 0; k < 2; k++) {
        OSObject *o = nullptr;
        if (bat->evaluateObject(meth[k], &o) != kIOReturnSuccess) continue;
        OSArray *a = o ? OSDynamicCast(OSArray, o) : nullptr;
        uint32_t v[9] = {0};
        if (a) for (unsigned i = 0; i < a->getCount() && i < 9; i++) {
            OSNumber *num = OSDynamicCast(OSNumber, a->getObject(i));
            v[i] = num ? num->unsigned32BitValue() : 0;
        }
        if (a && k == 0) { out[0] = v[1]; out[1] = v[2]; ok = true;
            if (txt) n += (size_t)snprintf(txt + n, txtLen - n, " _BIF unit=%u design=%u full=%u tech=%u volt=%u", v[0], v[1], v[2], v[3], v[4]); }
        if (a && k == 1) { out[2] = v[2]; out[3] = (v[0] & 0xff) | ((v[1] & 0xffffff) << 8);
            if (txt) n += (size_t)snprintf(txt + n, txtLen - n, " _BST state=%u rate=%u remain=%u volt=%u", v[0], v[1], v[2], v[3]); }
        if (o) o->release();
        if (txt && n >= txtLen) n = txtLen - 1;
    }
    return ok;
}

IOReturn AsusWmi::ecReg()
{
    if (!ec) return kIOReturnNotFound;
    UInt32 ecok = 0;
    if (ec->evaluateInteger("ECOK", &ecok) == kIOReturnSuccess && ecok) return kIOReturnSuccess;
    OSNumber *sp = OSNumber::withNumber(3ull, 32), *on = OSNumber::withNumber(1ull, 32);
    IOReturn r = kIOReturnNoMemory;
    if (sp && on) { OSObject *params[2] = { sp, on }; r = ec->evaluateObject("_REG", nullptr, params, 2); }
    if (sp) sp->release();
    if (on) on->release();
    ecok = 0;
    ec->evaluateInteger("ECOK", &ecok);
    say("EC0._REG(3,1) -> %08x, ECOK %u", r, ecok);
    return r;
}

IOReturn AsusWmi::setValue(int what, int v)
{
    uint32_t ret = 0;
    bool ok;
    switch (what) {
    case ASUS_SET_PROFILE:
        if (v < 0 || v > 2) return kIOReturnBadArgument;
        ok = devs(DEV_PROFILE, (uint32_t)v, &ret);
        if (ok) { fanCustom = false; pptSet[0] = pptSet[1] = pptSet[2] = 0; curProfile = v; }   // resets fans and limits
        break;
    case ASUS_SET_SPL: case ASUS_SET_SPPT: case ASUS_SET_FPPT: {
        int i = what - ASUS_SET_SPL;
        const Range &r = (onAC() ? kAcPpt : kDcPpt)[i];
        if (v < r.lo || v > r.hi) return kIOReturnBadArgument;
        if (!fanCustom) return kIOReturnNotPermitted;            // asus-armoury: PPT needs an active custom fan curve here
        ok = devs(kPptDev[i], (uint32_t)v, &ret);
        if (ok) pptSet[i] = (uint32_t)v;
        break;
    }
    case ASUS_SET_CHARGE:
        if (v < 20 || v > 100) return kIOReturnBadArgument;
        ok = devs(DEV_RSOC, (uint32_t)v, &ret);
        if (ok) curCharge = v;
        break;
    case ASUS_SET_BACKLIGHT:
        return blSet(v);
    case ASUS_SET_KBD:
        return kbdSet(v);
    case ASUS_SET_SLASH:
        return v < 0 ? kIOReturnBadArgument : slashApply((uint32_t)v);
    default:
        return kIOReturnUnsupported;
    }
    say("set %d=%d -> %s ret %08x", what, v, ok ? "ok" : "failed", ret);
    return ok ? kIOReturnSuccess : kIOReturnIOError;
}

// Firmware curve: DSTS 0x00110024/25 with arg1 = profile returns a 32-byte buffer, 8 temperatures then 8 duties (%).
IOReturn AsusWmi::fanRead(int fan, int profile, uint8_t out[16])
{
    if (fan < 0 || fan > 1 || profile < 0 || profile > 2) return kIOReturnBadArgument;
    uint32_t a[5] = { (uint32_t)(fan ? DEV_GPU_CURVE : DEV_CPU_CURVE), (uint32_t)profile, 0, 0, 0 };
    OSObject *o = nullptr;
    bool ok = wmiCall(atk, M_DSTS, a, &o);
    OSData *d = o ? OSDynamicCast(OSData, o) : nullptr;
    IOReturn r = kIOReturnIOError;
    if (ok && d && d->getLength() >= 16) { memcpy(out, d->getBytesNoCopy(), 16); r = kIOReturnSuccess; }
    if (o) o->release();
    return r;
}

// Custom curve: DEVS with the 8 temperatures packed into arg1/arg2 and the 8 duties into arg3/arg4, low byte first
// (asus-wmi fan_curve_write). Checked here: temperatures rising, duties not falling, and at least 40 % at the top point.
IOReturn AsusWmi::fanWrite(int fan, const uint8_t c[16])
{
    if (fan < 0 || fan > 1) return kIOReturnBadArgument;
    for (int i = 0; i < 8; i++) {
        if (c[i] < 20 || c[i] > 105 || c[8 + i] > 100) return kIOReturnBadArgument;
        if (i && (c[i] <= c[i - 1] || c[8 + i] < c[8 + i - 1])) return kIOReturnBadArgument;
    }
    if (c[15] < 40) return kIOReturnBadArgument;
    uint32_t a[5] = { (uint32_t)(fan ? DEV_GPU_CURVE : DEV_CPU_CURVE), 0, 0, 0, 0 };
    for (int i = 0; i < 4; i++) {
        a[1] |= (uint32_t)c[i] << (8 * i);
        a[2] |= (uint32_t)c[4 + i] << (8 * i);
        a[3] |= (uint32_t)c[8 + i] << (8 * i);
        a[4] |= (uint32_t)c[12 + i] << (8 * i);
    }
    uint32_t ret = 0;
    bool ok = wmi5(M_DEVS, a, &ret) && ret != WMI_UNSUPPORTED;
    if (ok) fanCustom = true;
    say("fan %d curve %u/%u..%u/%u -> %s ret %08x", fan, c[0], c[8], c[7], c[15], ok ? "ok" : "failed", ret);
    return ok ? kIOReturnSuccess : kIOReturnIOError;
}

// What the fans already do, but as a custom curve: switches the EC to manual fans without changing any duty.
IOReturn AsusWmi::fanCustomFromFirmware()
{
    uint32_t p = curProfile >= 0 ? (uint32_t)curProfile : 0;
    for (int fan = 0; fan < 2; fan++) {
        uint8_t c[16];
        IOReturn r = fanRead(fan, (int)p, c);
        if (r == kIOReturnSuccess) r = fanWrite(fan, c);
        if (r != kIOReturnSuccess) return r;
    }
    return kIOReturnSuccess;
}

// Setting the profile again is how asus-wmi turns a custom curve off: the firmware reloads the profile's curves and limits.
IOReturn AsusWmi::fanReset()
{
    return setValue(ASUS_SET_PROFILE, curProfile >= 0 ? curProfile : 0);
}

void AsusWmi::getState(uint32_t st[ASUS_ST_COUNT])
{
    memset(st, 0, ASUS_ST_COUNT * sizeof(uint32_t));
    uint32_t v = 0;
    bool ac = onAC();
    st[ASUS_ST_ABI] = ASUSWMI_ABI_VERSION;
    st[ASUS_ST_FLAGS] = (ac ? ASUS_FL_AC : 0) | (fanCustom ? ASUS_FL_FAN_CUSTOM : 0);
    st[ASUS_ST_PROFILE] = curProfile >= 0 ? (uint32_t)curProfile : ~0u;
    st[ASUS_ST_CHARGE] = curCharge >= 0 ? (uint32_t)curCharge : ~0u;
    st[ASUS_ST_CPU_FAN_RPM] = dsts(DEV_CPU_FAN, &v) && (v & DSTS_PRESENT) ? (v & 0xffff) * 100 : 0;
    st[ASUS_ST_GPU_FAN_RPM] = dsts(DEV_GPU_FAN, &v) && (v & DSTS_PRESENT) ? (v & 0xffff) * 100 : 0;
    for (int i = 0; i < 3; i++) {
        const Range &r = (ac ? kAcPpt : kDcPpt)[i];
        st[ASUS_ST_SPL + i] = pptSet[i];
        st[ASUS_ST_SPL_MIN + 2 * i] = (uint32_t)r.lo;
        st[ASUS_ST_SPL_MAX + 2 * i] = (uint32_t)r.hi;
    }
    st[ASUS_ST_GPU_MUX] = dsts(DEV_GPU_MUX, &v) ? v : ~0u;
    st[ASUS_ST_DGPU_DISABLE] = dsts(DEV_DGPU, &v) ? v : ~0u;
    st[ASUS_ST_NV_BASE_TGP] = dsts(DEV_NV_TGP, &v) && (v & DSTS_PRESENT) ? (v & 0xffff) : 0;
    st[ASUS_ST_BACKLIGHT] = blGet(&v) ? v : ~0u;
    st[ASUS_ST_BACKLIGHT_MAX] = blMaxLevel;
    battery(&st[ASUS_ST_BAT_DESIGN], nullptr, 0);
    st[ASUS_ST_KBD] = kbdLevel >= 0 ? (uint32_t)kbdLevel : ~0u;
    st[ASUS_ST_SLASH] = slashSet >= 0 ? (uint32_t)slashSet : ~0u;
    st[ASUS_ST_HID] = hidSeen ? 1 : 0;
}

// getACPITableData() is protected; this type is never instantiated, it only makes the (virtual) call reachable.
class AcpiTables : public IOACPIPlatformExpert {
public:
    const OSData *table(const char *sig, UInt32 n) { return getACPITableData(sig, n); }
};

void AsusWmi::dumpAcpi()
{
    AcpiTables *pe = (AcpiTables *)OSDynamicCast(IOACPIPlatformExpert, getPlatform());
    if (!pe) { say("no ACPI platform expert"); return; }
    const OSData *d = pe->table("DSDT", 0);
    if (d) setProperty("acpi-DSDT", (OSObject *)d);
    int n = 0;
    for (uint32_t i = 0; i < 64; i++) {
        const OSData *s = pe->table("SSDT", i);
        if (!s) break;
        char key[24];
        snprintf(key, sizeof(key), "acpi-SSDT-%u", i);
        setProperty(key, (OSObject *)s);
        n++;
    }
    say("acpi dump: DSDT %u bytes, %d SSDTs", d ? d->getLength() : 0, n);
}

// ---------------------------------------------------------------------------------------------------------------------------
// User client
// ---------------------------------------------------------------------------------------------------------------------------
class AsusWmiUC : public IOUserClient {
    OSDeclareDefaultStructors(AsusWmiUC)
public:
    bool initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args, IOExternalMethodDispatch *dispatch,
                            OSObject *target, void *reference) override;
private:
    AsusWmi *drv = nullptr;
    bool allowed = false;
};
OSDefineMetaClassAndStructors(AsusWmiUC, IOUserClient)

bool AsusWmiUC::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties)
{
    if (!IOUserClient::initWithTask(owningTask, securityToken, type, properties)) return false;
    // root, an administrator, or the user at the console; a remote (ssh) session of another user is refused
    allowed = clientHasPrivilege(owningTask, kIOClientPrivilegeAdministrator) == kIOReturnSuccess ||
              clientHasPrivilege(owningTask, kIOClientPrivilegeLocalUser) == kIOReturnSuccess;
    return true;
}

bool AsusWmiUC::start(IOService *provider)
{
    drv = OSDynamicCast(AsusWmi, provider);
    return drv && IOUserClient::start(provider);
}

IOReturn AsusWmiUC::clientClose()
{
    terminate();
    return kIOReturnSuccess;
}

IOReturn AsusWmiUC::externalMethod(uint32_t selector, IOExternalMethodArguments *a, IOExternalMethodDispatch *, OSObject *, void *)
{
    if (!drv || !a || !drv->lock) return kIOReturnNotAttached;
    if (!allowed) return kIOReturnNotPrivileged;
    IOReturn r;
    switch (selector) {
    case kAsusUcGetState: {
        if (!a->structureOutput || a->structureOutputSize < ASUS_ST_COUNT * sizeof(uint32_t)) return kIOReturnBadArgument;
        uint32_t st[ASUS_ST_COUNT];
        IOLockLock(drv->lock);
        drv->getState(st);
        IOLockUnlock(drv->lock);
        memcpy(a->structureOutput, st, sizeof(st));
        a->structureOutputSize = sizeof(st);
        return kIOReturnSuccess;
    }
    case kAsusUcSet:
        if (a->scalarInputCount != 2) return kIOReturnBadArgument;
        IOLockLock(drv->lock);
        r = drv->setValue((int)a->scalarInput[0], (int)a->scalarInput[1]);
        IOLockUnlock(drv->lock);
        return r;
    case kAsusUcFanRead: {
        if (a->scalarInputCount != 2 || !a->structureOutput || a->structureOutputSize < 16) return kIOReturnBadArgument;
        uint8_t c[16];
        IOLockLock(drv->lock);
        r = drv->fanRead((int)a->scalarInput[0], (int)a->scalarInput[1], c);
        IOLockUnlock(drv->lock);
        if (r == kIOReturnSuccess) { memcpy(a->structureOutput, c, 16); a->structureOutputSize = 16; }
        return r;
    }
    case kAsusUcFanWrite: {
        if (a->scalarInputCount != 1 || !a->structureInput || a->structureInputSize != 16) return kIOReturnBadArgument;
        uint8_t c[16];
        memcpy(c, a->structureInput, 16);
        IOLockLock(drv->lock);
        r = drv->fanWrite((int)a->scalarInput[0], c);
        IOLockUnlock(drv->lock);
        return r;
    }
    case kAsusUcFanReset:
        IOLockLock(drv->lock);
        r = drv->fanReset();
        IOLockUnlock(drv->lock);
        return r;
    default:
        return kIOReturnUnsupported;
    }
}

IOReturn AsusWmi::newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties, IOUserClient **handler)
{
    if (!handler) return kIOReturnBadArgument;
    AsusWmiUC *uc = OSTypeAlloc(AsusWmiUC);
    if (!uc) return kIOReturnNoMemory;
    if (!uc->initWithTask(owningTask, securityID, type, properties)) { uc->release(); return kIOReturnError; }
    if (!uc->attach(this)) { uc->release(); return kIOReturnError; }
    if (!uc->start(this)) { uc->detach(this); uc->release(); return kIOReturnError; }
    *handler = uc;
    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------------------------------------------------------
// sysctls (root)
// ---------------------------------------------------------------------------------------------------------------------------
static void buildStatus()
{
    size_t n = 0;
    gStatus[0] = 0;
    n += (size_t)snprintf(gStatus, sizeof(gStatus), "%s fan_custom=%d set_profile=%d set_charge=%d", gSelf->onAC() ? "ac" : "battery",
                          gSelf->fanCustom, gSelf->curProfile, gSelf->curCharge);
    uint32_t bl = 0;
    if (gSelf->blGet(&bl)) n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " backlight=%u/%u", bl, gSelf->blMaxLevel);
    n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " kbd=%d slash=%lld last_key=%02x", gSelf->kbdLevel,
                          (long long)gSelf->slashSet, gSelf->lastKey);
    for (int i = 0; i < 3; i++) {
        static const char *const nm[3] = { "spl", "sppt", "fppt" };
        n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " ppt_%s=%u", nm[i], gSelf->pptSet[i]);
    }
    for (const Known &k : kKnown) {
        uint32_t v = 0;
        if (!gSelf->dsts(k.id, &v)) { n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " %s=-", k.name); continue; }
        if (!(v & DSTS_PRESENT)) { n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " %s=absent", k.name); continue; }
        n += (size_t)snprintf(gStatus + n, sizeof(gStatus) - n, " %s=%u(%08x)", k.name, v & 0xffff, v);
        if (n >= sizeof(gStatus) - 48) break;
    }
}

static int status_sysctl SYSCTL_HANDLER_ARGS
{
    if (!gSelf) return ENODEV;
    IOLockLock(gSelf->lock);
    buildStatus();
    int e = SYSCTL_OUT(req, gStatus, strlen(gStatus) + 1);
    IOLockUnlock(gSelf->lock);
    return e;
}

static int hotkey_sysctl SYSCTL_HANDLER_ARGS
{
    if (!gSelf) return ENODEV;
    char value[48];
    IOLockLock(gSelf->lock);
    snprintf(value, sizeof(value), "%u %u", gSelf->keySequence, gSelf->lastKey);
    IOLockUnlock(gSelf->lock);
    return SYSCTL_OUT(req, value, strlen(value) + 1);
}

enum { W_DUMP = 100, W_FAN_CUSTOM = 101, W_EC_REG = 102, W_KEY = 103 };

static int write_sysctl SYSCTL_HANDLER_ARGS
{
    if (!gSelf) return ENODEV;
    int what = (int)arg2, v = -1;
    uint32_t cur = 0;
    IOLockLock(gSelf->lock);
    if (what == ASUS_SET_PROFILE) v = gSelf->curProfile;
    else if (what == ASUS_SET_CHARGE) v = gSelf->curCharge;
    else if (what == ASUS_SET_BACKLIGHT) v = gSelf->blGet(&cur) ? (int)cur : -1;
    else if (what == W_EC_REG) { UInt32 e = 0; v = gSelf->ec && gSelf->ec->evaluateInteger("ECOK", &e) == kIOReturnSuccess ? (int)e : -1; }
    else if (what >= ASUS_SET_SPL && what <= ASUS_SET_FPPT) v = (int)gSelf->pptSet[what - ASUS_SET_SPL];
    else if (what == W_FAN_CUSTOM) v = gSelf->fanCustom;
    else if (what == ASUS_SET_KBD) v = gSelf->kbdLevel;
    else if (what == ASUS_SET_SLASH) v = (int)gSelf->slashSet;
    else if (what == W_KEY) v = (int)gSelf->lastKey;
    IOLockUnlock(gSelf->lock);
    int e = sysctl_handle_int(oidp, &v, 0, req);
    if (e || !req->newptr) return e;
    IOLockLock(gSelf->lock);
    IOReturn r;
    if (what == W_DUMP) { gSelf->dumpAcpi(); r = kIOReturnSuccess; }
    else if (what == W_FAN_CUSTOM) r = v ? gSelf->fanCustomFromFirmware() : gSelf->fanReset();
    else if (what == W_EC_REG) r = v ? gSelf->ecReg() : kIOReturnSuccess;
    else if (what == W_KEY) { uint32_t ret = 0; r = v > 0 && v < 0x100 && gSelf->devs(DEV_HOTKEY, (uint32_t)v, &ret) ? kIOReturnSuccess : kIOReturnBadArgument;
                              gSelf->say("hotkey %02x emulated -> %08x", v, ret); }
    else r = gSelf->setValue(what, v);
    IOLockUnlock(gSelf->lock);
    switch (r) {
    case kIOReturnSuccess: return 0;
    case kIOReturnBadArgument: return EINVAL;
    case kIOReturnNotPermitted: return EBUSY;            // power limits before a custom fan curve
    default: return EIO;
    }
}

static int probe_sysctl SYSCTL_HANDLER_ARGS
{
    if (!gSelf) return ENODEV;
    if (req->newptr) {                                       // write: a device id
        int dev = 0;
        int e = SYSCTL_IN(req, &dev, sizeof(dev));
        if (e) return e;
        IOLockLock(gSelf->lock);
        gProbeDev = (uint32_t)dev;
        gProbeOk = gSelf->wmi(M_DSTS, gProbeDev, 0, &gProbeVal);
        IOLockUnlock(gSelf->lock);
        return 0;
    }
    char s[64];
    snprintf(s, sizeof(s), "dev %08x: %s %08x", gProbeDev, gProbeOk ? "dsts" : "call failed", gProbeVal);
    return SYSCTL_OUT(req, s, strlen(s) + 1);
}

static int battery_sysctl SYSCTL_HANDLER_ARGS
{
    if (!gSelf) return ENODEV;
    char s[256];
    uint32_t b[4];
    IOLockLock(gSelf->lock);
    gSelf->battery(b, s, sizeof(s));
    IOLockUnlock(gSelf->lock);
    return SYSCTL_OUT(req, s, strlen(s) + 1);
}

SYSCTL_NODE(_debug, OID_AUTO, asuswmi, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "AsusWmi");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, status, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, status_sysctl, "A", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, hotkey, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, hotkey_sysctl, "A", "sequence and last ATKD event");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, profile, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_PROFILE, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, fan_custom, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_FAN_CUSTOM, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, ppt_spl, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_SPL, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, ppt_sppt, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_SPPT, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, ppt_fppt, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_FPPT, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, charge_limit, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_CHARGE, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, dumpacpi, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_DUMP, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, probe, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, 0, probe_sysctl, "A", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, backlight, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_BACKLIGHT, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, battery, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, battery_sysctl, "A", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, ec_reg, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_EC_REG, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, kbd, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_KBD, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, slash, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, ASUS_SET_SLASH, write_sysctl, "I", "");
SYSCTL_PROC(_debug_asuswmi, OID_AUTO, key, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_KEY, write_sysctl, "I", "");

static struct sysctl_oid *const kOids[] = {
    &sysctl__debug_asuswmi, &sysctl__debug_asuswmi_status, &sysctl__debug_asuswmi_hotkey, &sysctl__debug_asuswmi_profile, &sysctl__debug_asuswmi_fan_custom,
    &sysctl__debug_asuswmi_ppt_spl, &sysctl__debug_asuswmi_ppt_sppt, &sysctl__debug_asuswmi_ppt_fppt,
    &sysctl__debug_asuswmi_charge_limit, &sysctl__debug_asuswmi_dumpacpi, &sysctl__debug_asuswmi_probe,
    &sysctl__debug_asuswmi_backlight, &sysctl__debug_asuswmi_battery, &sysctl__debug_asuswmi_ec_reg,
    &sysctl__debug_asuswmi_kbd, &sysctl__debug_asuswmi_slash, &sysctl__debug_asuswmi_key,
};

bool AsusWmi::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    atk = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!atk || gSelf) return false;
    if (atk->validateObject("WMNB") != kIOReturnSuccess) { IOLog("AsusWmi: no WMNB on %s\n", atk->getName()); return false; }
    lock = IOLockAlloc();
    if (!lock) return false;
    gSelf = this;
    uint32_t r = 0;
    if (wmi(M_INIT, 0, 0, &r)) say("INIT %08x", r); else say("INIT failed");
    if (wmi(M_SFUN, 0, 0, &r)) say("SFUN %08x", r); else say("SFUN failed");
    findAcpi();
    evCall = thread_call_allocate(evThread, this);
    if (evCall) atkNotifier = atk->registerInterest(gIOGeneralInterest, atkNotify, this);
    say("hotkeys %s", atkNotifier ? "hooked" : "not hooked");
    char bt[256];
    uint32_t b4[4];
    battery(b4, bt, sizeof(bt));
    say("%s", bt);
    buildStatus();
    say("%s", gStatus);
    for (sysctl_oid *o : kOids) sysctl_register_oid(o);
    registerService();
    return true;
}

void AsusWmi::stop(IOService *provider)
{
    for (int i = (int)(sizeof(kOids) / sizeof(kOids[0])) - 1; i >= 0; i--) sysctl_unregister_oid(kOids[i]);
    if (atkNotifier) { atkNotifier->remove(); atkNotifier = nullptr; }
    if (evCall) { thread_call_cancel_wait(evCall); thread_call_free(evCall); evCall = nullptr; }
    gSelf = nullptr;
    if (acad) { acad->release(); acad = nullptr; }
    if (awmi) { awmi->release(); awmi = nullptr; }
    if (bat) { bat->release(); bat = nullptr; }
    if (ec) { ec->release(); ec = nullptr; }
    if (lock) { IOLockFree(lock); lock = nullptr; }
    IOService::stop(provider);
}
