// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// StrixS0ix: S0 (Modern Standby) system sleep for the ASUS GA403WM (Strix Point) on macOS.
//
// The firmware has no _S3, so AppleACPIPlatform reports "sleep states S4 S5" and refuses system sleep
// (kPMPCIUnsupported). Apple's own S0 path is already in AppleACPIPlatform (docs/890M-TRACE.md Step109):
//   initPlatformPowerManagement: \_SB.LPS0 == Integer 1  ->  deep idle flag, IOPMDeepIdleSupported
//   resolveSystemStateSupport:   no S3 but deep idle     ->  S0 stays in the sleep state mask, "can sleep"
//   sleepPlatform:               S0                       ->  acpi_idle_kernel(): callback clears ACPI status,
//                                                             enables only the wake GPEs, then pmCPUHalt(PM_HALT_SLEEP)
// acpi/SSDT-S0IDLE.dsl provides \_SB.LPS0. This kext supplies the missing pieces:
//  1. pmCPUHalt. On AMD nothing registers pmDispatch, and the stock PM_HALT_SLEEP path is "cli; wbinvd; hlt" with a
//     panic if it ever returns: the boot CPU would never wake. We register a dispatch table with only pmCPUHalt set
//     (every other kernel use checks its field for NULL). Non-boot CPUs and an unarmed boot CPU halt as stock.
//     The armed boot CPU idles with MONITORX/MWAITX (C1, break on masked interrupts, TSC timer) and polls PM1/GPE0
//     status until a wake event (power button, RTC, wake GPE such as the lid), then returns: acpi_idle_kernel rebases
//     time and the platform wakes.
//  2. The Microsoft Modern Standby _DSM on \_SB.PEP (11e00d56..., mask 0x1F9), in Linux s2idle order: display off (3),
//     MS entry (7), sleep entry (5) when the root domain powers this service down for system sleep; sleep exit (6),
//     MS exit (8), display on (4) when it comes back.
// Not yet: the SMU OS_HINT (amd_pmc) for S0i3 residency; without it the SoC stays out of S0i3 but the system sleeps.
//
// Wake event codes (S0ix,LastWakeEvent): PM1 status bits (0x100 power button, 0x400 RTC, 0x4000 PCIe wake),
// 0x10000 + n = GPE n, 0x40000000 = no event within s0ix_maxsec (default 300 s, 0 = unlimited),
// 0x80000000 = a masked non-wake interrupt kept MWAITX from sleeping.
// Safety: if the halt hook cannot be installed (other kernel, unexpected layout, no MONITORX, boot-arg -s0ixoff),
// the kext holds a CPU power assertion so the root domain never enters the S0 path ("sleep prevented by
// kPMCPUAssertion") instead of hanging. Boot-arg -s0ixnodsm skips the _DSM calls.

#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <libkern/OSKextLib.h>
#include <libkern/version.h>
#include <pexpert/pexpert.h>

extern "C" {
void pmKextRegister(uint32_t version, void *cpuFuncs, void *callbacks);   // osfmk/i386/pmCPU.c (Unsupported KPI)
int cpu_number(void);
}

namespace {
constexpr uint32_t kPMDispatchVersion = 0x66;     // PM_DISPATCH_VERSION of this kernel (pmKextRegister: cmpl $0x66)
constexpr size_t kDispHalt = 0x48 / 8;            // pmDispatch_t::pmCPUHalt (pmCPUHalt: call *0x48(pmDispatch))
constexpr size_t kCbInitComplete = 0x10 / 8;      // pmCallBacks_t::initComplete (sets pmInitDone)
constexpr size_t kCbGetMyLCPU = 0x38 / 8;         // pmCallBacks_t::GetMyLCPU (_pmGetMyLogicalCPU)
constexpr size_t kLcpuState = 0x58;               // x86_lcpu_t::state: pmCPUHalt writes 0x15e8(cpu_data), lcpu = +0x1590
constexpr uint32_t kLcpuHalt = 1, kLcpuRun = 5;   // lcpu_state_t: OFF 0, HALT 1, NONSCHED 2, PAUSE 3, IDLE 4, RUN 5
constexpr uint16_t kPm1Wake = (1u << 8) | (1u << 9) | (1u << 10) | (1u << 14);   // PWRBTN, SLPBTN, RTC, PCIEXP_WAKE
}

static void *gDispatch[64];
static void *gCallbacks[64];
static void *(*gGetMyLCPU)(void);
static uint16_t gPm1Sts = 0x800, gGpe0Sts = 0x820, gGpe0Len = 8;    // FADT values of this machine; re-read at start
static uint32_t gTimeoutTsc = 0x10000000;
static uint64_t gMaxIdleTsc;                     // 0 = no limit (boot-arg s0ix_maxsec, default 300 s in 0.1.x)
static volatile bool gArmed;
alignas(64) static volatile uint64_t gMonitorLine[8];
static volatile uint64_t gIdleEntries, gLastIdleTsc, gTscHz;
static volatile uint32_t gLastWhy, gLastLoops, gLastFast;

static inline uint16_t inw(uint16_t p) { uint16_t v; asm volatile("inw %1, %0" : "=a"(v) : "Nd"(p)); return v; }
static inline uint32_t inl(uint16_t p) { uint32_t v; asm volatile("inl %1, %0" : "=a"(v) : "Nd"(p)); return v; }
static inline uint64_t rdtsc64() { uint32_t lo, hi; asm volatile("rdtsc" : "=a"(lo), "=d"(hi)); return (uint64_t(hi) << 32) | lo; }
static inline void cpuid(uint32_t leaf, uint32_t r[4]) { asm volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(leaf), "c"(0)); }

// Wake events since the platform callback cleared all ACPI status: PM1 fixed events (bits 0-15) or an enabled GPE
// (bit 16 + GPE number of the lowest one, to keep it readable in one number).
static uint32_t wakeEvent()
{
    uint16_t s = inw(gPm1Sts) & kPm1Wake;
    if (s) return s;
    uint16_t half = gGpe0Len / 2;
    for (uint16_t i = 0; i + 4 <= half; i += 4) {
        uint32_t g = inl(gGpe0Sts + i) & inl(gGpe0Sts + half + i);
        if (g) return 0x10000u | (uint32_t(i) * 8 + uint32_t(__builtin_ctz(g)));
    }
    return 0;
}

// pmDispatch->pmCPUHalt: called by pmCPUHalt() with interrupts disabled. Returning means "woken" (boot CPU only).
static void s0ixHalt(void)
{
    if (cpu_number() != 0 || !gArmed) {
        auto st = reinterpret_cast<volatile uint32_t *>(static_cast<uint8_t *>(gGetMyLCPU()) + kLcpuState);
        *st = kLcpuHalt;                          // cpu_exit_wait() waits for LCPU_HALT
        for (;;) asm volatile("wbinvd; hlt" ::: "memory");   // stock: only INIT/SIPI brings it back
    }
    gIdleEntries++;
    uint64_t t0 = rdtsc64();
    uint32_t why, loops = 0, fast = 0;
    while (!(why = wakeEvent())) {
        uint64_t a = rdtsc64();
        asm volatile(".byte 0x0f, 0x01, 0xfa" :: "a"(gMonitorLine), "c"(0), "d"(0));                 // MONITORX
        asm volatile(".byte 0x0f, 0x01, 0xfb" :: "a"(0), "b"(gTimeoutTsc), "c"(3) : "memory");      // MWAITX C1, IRQ break, timer
        loops++;
        // a masked interrupt that is not a wake event stays pending and breaks MWAITX at once: after a long run of
        // immediate returns give up and wake (macOS goes back to sleep from the dark wake) instead of spinning
        uint64_t b = rdtsc64();
        if (b - a < gTimeoutTsc / 1024) { if (++fast > 20000) { why = 0x80000000u; break; } }
        else fast = 0;
        if (gMaxIdleTsc && b - t0 > gMaxIdleTsc) { why = 0x40000000u; break; }   // safety net: no wake event seen
    }
    gLastIdleTsc = rdtsc64() - t0;
    gLastWhy = why;
    gLastLoops = loops;
    gLastFast = fast;
}

class StrixS0ix : public IOService {
    OSDeclareDefaultStructors(StrixS0ix)
    IOACPIPlatformDevice *pep = nullptr;
    bool pm = false, halt = false, useDsm = true, slept = false, shutdown = false;
    IOPMDriverAssertionID block = 0;
    UInt32 sleeps = 0;
    bool installHalt();
    void readFadt();
    IOReturn dsm(UInt32 fn, OSObject **result = nullptr);
public:
    bool start(IOService *provider) override;
    IOReturn setPowerState(unsigned long state, IOService *device) override;
    void systemWillShutdown(IOOptionBits specifier) override;
};

OSDefineMetaClassAndStructors(StrixS0ix, IOService)

void StrixS0ix::readFadt()
{
    // Tahoe publishes no "ACPI Tables" property; ask the platform through the ACPI device
    const OSData *facp = pep->getACPITableData("FACP", 0);
    if (!facp || facp->getLength() < 96) { IOLog("StrixS0ix: FACP not readable, using 0x800/0x820\n"); return; }
    auto b = static_cast<const uint8_t *>(facp->getBytesNoCopy());
    uint32_t pm1a, gpe0;
    memcpy(&pm1a, b + 56, 4);
    memcpy(&gpe0, b + 80, 4);
    if (pm1a && pm1a < 0x10000) gPm1Sts = uint16_t(pm1a);
    if (gpe0 && gpe0 < 0x10000) { gGpe0Sts = uint16_t(gpe0); gGpe0Len = b[92]; }
    IOLog("StrixS0ix: FADT PM1a_EVT %#x GPE0 %#x len %u\n", gPm1Sts, gGpe0Sts, gGpe0Len);
}

bool StrixS0ix::installHalt()
{
    if (version_major != 25) { IOLog("StrixS0ix: Darwin %d, built for 25: no halt hook\n", version_major); return false; }
    uint32_t r[4];
    cpuid(0x80000001, r);
    if (!(r[2] & (1u << 29))) { IOLog("StrixS0ix: no MONITORX/MWAITX: no halt hook\n"); return false; }
    cpuid(5, r);
    // IBE: an interrupt ends MWAITX even with IF=0; without it the 0.25 s timer still ends every wait
    setProperty("S0ix,MwaitIBE", bool(r[2] & 2));
    // TSC rate for the MWAITX timer (~0.25 s per wait)
    uint64_t t0 = rdtsc64(), n0 = 0, n1 = 0;
    absolutetime_to_nanoseconds(mach_absolute_time(), &n0);
    IODelay(20000);
    absolutetime_to_nanoseconds(mach_absolute_time(), &n1);
    uint64_t hz = (rdtsc64() - t0) * 1000000000ULL / (n1 - n0 ? n1 - n0 : 1);
    gTscHz = hz;
    uint64_t to = hz / 4;
    gTimeoutTsc = uint32_t(to > 0xffffffffULL ? 0xffffffffULL : (to < 1000000 ? 1000000 : to));
    UInt32 maxsec = 300;
    PE_parse_boot_argn("s0ix_maxsec", &maxsec, sizeof maxsec);
    gMaxIdleTsc = uint64_t(maxsec) * hz;
    // first call with no dispatch table: the kernel fills the callbacks only, so the lcpu layout can be checked
    // before anything is registered (a wrong version panics in pmKextRegister, hence the Darwin 25 gate above)
    pmKextRegister(kPMDispatchVersion, nullptr, gCallbacks);
    gGetMyLCPU = reinterpret_cast<void *(*)(void)>(gCallbacks[kCbGetMyLCPU]);
    if (!gGetMyLCPU || !gCallbacks[kCbInitComplete]) { IOLog("StrixS0ix: callbacks not filled: no halt hook\n"); return false; }
    boolean_t ie = ml_set_interrupts_enabled(FALSE);
    uint32_t st = *reinterpret_cast<volatile uint32_t *>(static_cast<uint8_t *>(gGetMyLCPU()) + kLcpuState);
    ml_set_interrupts_enabled(ie);
    if (st != kLcpuRun) { IOLog("StrixS0ix: lcpu state at +%#zx is %u, not RUN: no halt hook\n", kLcpuState, st); return false; }
    gDispatch[kDispHalt] = reinterpret_cast<void *>(&s0ixHalt);
    pmKextRegister(kPMDispatchVersion, gDispatch, gCallbacks);
    reinterpret_cast<void (*)(void)>(gCallbacks[kCbInitComplete])();
    IOLog("StrixS0ix: pmCPUHalt registered (TSC %llu MHz, MWAITX timeout %u)\n", hz / 1000000, gTimeoutTsc);
    return true;
}

IOReturn StrixS0ix::dsm(UInt32 fn, OSObject **result)
{
    static const uint8_t ms[16] = { 0x56, 0x0d, 0xe0, 0x11, 0x64, 0xce, 0xce, 0x47,
                                    0x83, 0x7b, 0x1f, 0x89, 0x8f, 0x9a, 0xa4, 0x61 };   // 11e00d56-ce64-47ce-837b-1f898f9aa461
    OSObject *p[4] = { OSData::withBytes(ms, sizeof ms), OSNumber::withNumber(0ULL, 32),
                       OSNumber::withNumber(uint64_t(fn), 32), OSArray::withCapacity(1) };
    IOReturn r = kIOReturnNoMemory;
    OSObject *res = nullptr;
    if (p[0] && p[1] && p[2] && p[3]) r = pep->evaluateObject("_DSM", &res, p, 4);
    for (auto o : p) if (o) o->release();
    if (result) *result = res; else if (res) res->release();
    return r;
}

bool StrixS0ix::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    pep = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!pep) return false;
    // the pmDispatch table and the halt function must outlive any unload attempt
    OSKextRetainKextWithLoadTag(OSKextGetCurrentLoadTag());
    useDsm = !PE_parse_boot_argn("-s0ixnodsm", nullptr, 0);
    readFadt();

    OSObject *q = nullptr;
    unsigned mask = 0;
    if (dsm(0, &q) == kIOReturnSuccess)
        if (auto d = OSDynamicCast(OSData, q)) {
            auto m = static_cast<const uint8_t *>(d->getBytesNoCopy());
            if (d->getLength() > 0) mask = m[0];
            if (d->getLength() > 1) mask |= unsigned(m[1]) << 8;
        }
    if (q) q->release();
    if ((mask & 0x1f8) != 0x1f8) { IOLog("StrixS0ix: PEP _DSM mask %#x lacks fn 3-8, _DSM calls off\n", mask); useDsm = false; }
    setProperty("S0ix,DsmMask", mask, 32);
    setProperty("S0ix,Dsm", useDsm);

    halt = !PE_parse_boot_argn("-s0ixoff", nullptr, 0) && installHalt();
    setProperty("S0ix,HaltHook", halt);
    if (!halt) {
        block = getPMRootDomain()->createPMAssertion(kIOPMDriverAssertionCPUBit, kIOPMDriverAssertionLevelOn, this,
                                                     "com.ga403wm.strixs0ix.no-halt-hook");
        IOLog("StrixS0ix: no halt hook, system sleep blocked (assertion %llu)\n", block);
    }

    static IOPMPowerState states[2] = {
        { kIOPMPowerStateVersion1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { kIOPMPowerStateVersion1, kIOPMPowerOn, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    PMinit();
    getPMRootDomain()->addPowerChild(this);       // top level: powered down after the device tree, only on real sleep
    if (registerPowerDriver(this, states, 2) == kIOReturnSuccess) { pm = true; changePowerStateTo(1); }
    IOLog("StrixS0ix: 0.1.1 up, PEP _DSM mask %#x (%s), halt hook %s, power child %s\n", mask, useDsm ? "used" : "off",
          halt ? "on" : "OFF", pm ? "on" : "FAILED");
    registerService();
    return true;
}

// restart and power-off also take the root domain's children down: never arm the idle path or run the Modern
// Standby entry then (the boot CPU must halt as stock after the S5 write)
void StrixS0ix::systemWillShutdown(IOOptionBits specifier)
{
    shutdown = true;
    gArmed = false;
    IOService::systemWillShutdown(specifier);
}

IOReturn StrixS0ix::setPowerState(unsigned long state, IOService *)
{
    if (state == 0 && shutdown) return kIOPMAckImplied;
    if (state == 0) {
        sleeps++;
        IOReturn a = kIOReturnSuccess, b = kIOReturnSuccess, c = kIOReturnSuccess;
        if (useDsm) { a = dsm(3); b = dsm(7); c = dsm(5); }
        gArmed = halt;
        slept = true;
        IOLog("StrixS0ix: sleep #%u, _DSM 3/7/5 %x/%x/%x, idle %s\n", unsigned(sleeps), a, b, c, halt ? "armed" : "NOT armed");
        return kIOPMAckImplied;
    }
    if (!slept) return kIOPMAckImplied;           // the first state 1 at registration
    slept = false;
    gArmed = false;
    IOReturn a = kIOReturnSuccess, b = kIOReturnSuccess, c = kIOReturnSuccess;
    if (useDsm) { a = dsm(6); b = dsm(8); c = dsm(4); }
    uint64_t ms = gTscHz ? gLastIdleTsc * 1000 / gTscHz : 0;
    setProperty("S0ix,Sleeps", sleeps, 32);
    setProperty("S0ix,IdleEntries", gIdleEntries, 64);
    setProperty("S0ix,LastWakeEvent", gLastWhy, 32);
    setProperty("S0ix,LastIdleMs", ms, 64);
    setProperty("S0ix,LastLoops", gLastLoops, 32);
    IOLog("StrixS0ix: wake #%u, idle entries %llu, last idle %llu ms, wake event %#x, loops %u fast %u, _DSM 6/8/4 %x/%x/%x\n",
          unsigned(sleeps), gIdleEntries, ms, gLastWhy, gLastLoops, gLastFast, a, b, c);
    return kIOPMAckImplied;
}
