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
//  3. (0.1.3) S0i3, as Linux amd_pmc + cpuidle do it:
//     - the PMC mailbox of the SMU (MMIO at SMN 0x13B102E8/EC + 0x10000; msg 0x938, arg 0x9BC, response 0x980):
//       LOG_RESET/LOG_START and OS_HINT(1) after the _DSM entry calls, OS_HINT(0) and LOG_DUMP_DATA before the exit
//       calls; the SMU metrics table then says whether the last sleep reached S0i3, how long, and which IP blocks
//       kept it out (S0ix,Smu*). Boot-arg s0ix_pmc=0 turns it off.
//     - cores in CC6: an S0i3 needs every core in CC6, and HLT / MWAITX are only C1. Non-boot CPUs (offline during
//       sleep, only INIT brings them back) read the IO C-state port CStateBaseAddr+1 (MSR C001_0073, the C2 entry of
//       _CST, Linux "ACPI IOPORT") instead of HLT. Boot-arg s0ix_cc6=0 keeps HLT. The armed boot CPU does the same
//       only when "S0ix,BootCC6" is set (property, or boot-arg s0ix_cc6boot=1): it then relies on the SCI of the wake
//       event to end the C-state with IF=0, and falls back to MWAITX polling if C2 keeps returning at once.
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
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <kern/thread_call.h>
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
static volatile uint16_t gCstPort;               // CStateBaseAddr + depth (_CST C2 = +1, C3 = +2), 0 = none
static uint16_t gCstBase;
static bool gCc6Cpus = true;                     // non-boot CPUs in CC6 while halted
static volatile bool gCc6Boot;                   // armed boot CPU in CC6 between wake checks
static volatile uint32_t gLastCc6Loops;
// 0.1.6: the power button (_QE7 -> Notify PWRB) and the lid (_Q2F -> Notify LID0) are EC queries on the EC's GPE
// (EC0._GPE 0x0A). The DSDT has no _PRW at all, so AppleACPIPlatform disables that GPE before the halt and nothing but
// the RTC could end a sleep (lid close 2026-11-05 13:00: no wake, forced restart). Like Linux s2idle and Windows Modern
// Standby the EC GPE is a wake source: enabled for the halt, the old enable word put back on exit; its status stays set,
// so after the wake ACPI runs the query (lid open or power button wakes fully, other EC events go back to sleep).
static volatile uint8_t gEcGpe = 0x0A;          // EC0._GPE, re-read at start; 0xff = off (boot-arg s0ix_ecwake=0)
static uint32_t gEcEnSaved;
static volatile bool gEcEnSet;
static volatile uint32_t gEcEnAtHalt;            // the enable word as macOS left it, for the log
// 0.1.8: in Modern Standby the EC reports the lid and the power button on AMD GPIO 0 (PWR_BTN_L), not on its GPE:
// SSDT-22 \_SB.GPIO._AEI lists pin 0 (PBTN, ExclusiveAndWake) and _EVT(0) does Notify (PWRB) + Notify (LID0). macOS
// has no _AEI support and VoodooGPIOAMD serves only the touchpad pin, so nothing armed pin 0: the 14:38 observe run
// saw no GPE0 and no PM1 bit for a lid open and a power button press. At halt pin 0 gets interrupt enable, IRQ
// delivery and S0i3 wake (pinctrl-amd bits 11/12/13) with its status cleared; its interrupt / wake status (bits 28/29)
// is a wake event; on exit the old control word goes back with the status cleared, and after the wake StrixS0ix runs
// _EVT(0) so ACPI sends the Notify macOS never got. S0ix,GpioWake: 0 off, 1 wake (default), 2 observe (latch only).
static volatile uint8_t *gGpio;                  // AMDI0030 MMIO (pin n control at n * 4)
static volatile uint32_t gGpioMode = 0;
static volatile bool gGpioCc6;                   // boot CPU CC6 while GPIO wake is armed (until IRQ 7 is proven)
static uint32_t gPin0Saved, gPin0AtHalt, gPin0AtWake, gPin0IntMs, gPin0Toggles;
// 0.1.9: the other _AEI pins too (SSDT-22: 5, 0x10, 0x3A, 0x3B, 0x36, D3C 0x12): at 17:02 a lid open moved no pin 0 bit
// and the wake came 30 s later on the EC GPE, so record which pin (if any) the EC drives for the lid
static constexpr uint8_t kAeiPins[7] = { 0x00, 0x05, 0x10, 0x3A, 0x3B, 0x36, 0x12 };
static uint32_t gAeiHalt[7], gAeiLast[7], gAeiWake[7], gAeiFirstMs[7], gAeiToggles[7];
// 0.1.9: S0ix,DsmSkip, a bit per PEP _DSM fn to leave out (0x18 = fn 3/4 EC 0x97/0x99 + HBHT, 0x180 = fn 7/8 EC 0x98/0x86):
// tests whether the EC Modern Standby commands hold the lid event back (17:02: lid open, SCI 30 s later)
static volatile uint32_t gDsmSkip = 0x180;          // 0.1.10 default: fn 7/8 off (Step120 test B: with them the EC sends no lid SCI)
static volatile uint32_t gEcMode = 1;            // 0.1.7: S0ix,EcWake 0 = off, 1 = EC GPE wakes, 2 = observe only
// 0.1.7: every PM1 / GPE0 status bit that appears while halted, with its first time (ms after halt entry). Observe
// mode (2) keeps the boot CPU on the MWAITX loop (0.25 s polls) and never wakes on the EC, so a lid open or a power
// button press during an RTC-timed sleep shows which status bit it raises, without risking a sleep that never ends.
static uint32_t gSeenGpe, gSeenPm1;
static uint32_t gSeenGpeMs[32], gSeenPm1Ms[16];
static uint64_t gHaltT0;

static inline uint16_t inw(uint16_t p) { uint16_t v; asm volatile("inw %1, %0" : "=a"(v) : "Nd"(p)); return v; }
static inline uint32_t inl(uint16_t p) { uint32_t v; asm volatile("inl %1, %0" : "=a"(v) : "Nd"(p)); return v; }
static inline void outl(uint16_t p, uint32_t v) { asm volatile("outl %0, %1" :: "a"(v), "Nd"(p)); }
static inline void outb(uint16_t p, uint8_t v) { asm volatile("outb %0, %1" :: "a"(v), "Nd"(p)); }
static inline uint8_t inb(uint16_t p) { uint8_t v; asm volatile("inb %1, %0" : "=a"(v) : "Nd"(p) : "memory"); return v; }
static inline uint64_t rdmsr64(uint32_t m) { uint32_t lo, hi; asm volatile("rdmsr" : "=a"(lo), "=d"(hi) : "c"(m)); return (uint64_t(hi) << 32) | lo; }
static inline uint64_t rdtsc64() { uint32_t lo, hi; asm volatile("rdtsc" : "=a"(lo), "=d"(hi)); return (uint64_t(hi) << 32) | lo; }
static inline void cpuid(uint32_t leaf, uint32_t r[4]) { asm volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(leaf), "c"(0)); }

static void sampleStatus()
{
    if (gGpio) {
        uint32_t ms = 1 + uint32_t((rdtsc64() - gHaltT0) / (gTscHz / 1000 ? gTscHz / 1000 : 1));
        for (unsigned i = 0; i < 7; i++) {
            uint32_t v = *reinterpret_cast<volatile uint32_t *>(gGpio + kAeiPins[i] * 4);
            if ((v ^ gAeiLast[i]) & ((1u << 16) | (3u << 28))) { gAeiToggles[i]++; if (!gAeiFirstMs[i]) gAeiFirstMs[i] = ms; }
            gAeiLast[i] = v;
        }
    }
    if (gGpio && gGpioMode) {
        static uint32_t last;
        uint32_t v = *reinterpret_cast<volatile uint32_t *>(gGpio);
        if (gPin0Toggles == 0 && last == 0) last = gPin0AtHalt;
        if ((v ^ last) & (1u << 16)) gPin0Toggles++;
        if ((v & (3u << 28)) && !gPin0IntMs)
            gPin0IntMs = 1 + uint32_t((rdtsc64() - gHaltT0) / (gTscHz / 1000 ? gTscHz / 1000 : 1));
        last = v;
    }
    uint32_t g = inl(gGpe0Sts) & ~gSeenGpe;
    uint32_t p = inw(gPm1Sts) & 0xffffu & ~gSeenPm1;
    if (!(g | p)) return;
    uint32_t ms = uint32_t((rdtsc64() - gHaltT0) / (gTscHz / 1000 ? gTscHz / 1000 : 1));
    for (unsigned i = 0; i < 32; i++) if (g & (1u << i)) gSeenGpeMs[i] = ms;
    for (unsigned i = 0; i < 16; i++) if (p & (1u << i)) gSeenPm1Ms[i] = ms;
    gSeenGpe |= g; gSeenPm1 |= p;
}

// Wake events since the platform callback cleared all ACPI status: PM1 fixed events (bits 0-15) or an enabled GPE
// (bit 16 + GPE number of the lowest one, to keep it readable in one number).
static uint32_t wakeEvent()
{
    uint16_t s = inw(gPm1Sts) & kPm1Wake;
    if (s) return s;
    if (gGpio && gGpioMode == 1 && (*reinterpret_cast<volatile uint32_t *>(gGpio) & (3u << 28))) return 0x20000u;
    uint16_t half = gGpe0Len / 2;
    for (uint16_t i = 0; i + 4 <= half; i += 4) {
        uint32_t g = inl(gGpe0Sts + i) & inl(gGpe0Sts + half + i);
        if (g) return 0x10000u | (uint32_t(i) * 8 + uint32_t(__builtin_ctz(g)));
    }
    return 0;
}

// pmDispatch->pmCPUHalt: called by pmCPUHalt() with interrupts disabled. Returning means "woken" (boot CPU only).
// ---- 0.1.4: the last step before the SoC can idle, from the halt path (all drivers have suspended by then) ----------
// Linux s2idle order: devices to D3hot (pci_pm_suspend_noirq), then amd_pmc OS_HINT(1); on wake OS_HINT(0), then
// devices back to D0 before their drivers resume. macOS only moves the XHCs to D3, so the 890M and its audio/ACP/PSP/
// NPU functions stay in D0 (SMU "not met": DISPLAY, NBIO). The table below is built in setPowerState(0); the halt path
// touches only ECAM MMIO (no IOPCIBridge lock with interrupts off) and only functions whose PMCSR has No_Soft_Reset,
// so their config space survives D3hot. S0ix,D3Mode: 0 = only record the D-states, 1 = D3hot for the 890M's buses,
// 2 = also every other endpoint IOPCIFamily left in D0 (never the RTX, NVMe or bridges).
struct PciFn {
    volatile uint16_t *pmcsr;                    // ECAM VA of PMCSR
    volatile uint8_t *cfg;                       // ECAM VA of the function's config space
    uint8_t pcie, msi, msix;                     // capability offsets (0 = none)
    uint16_t l1ss;                               // 0.1.13: L1 PM Substates extended capability (0 = none)
    bool saved;
    uint32_t save[64];                           // config space at sleep, for functions without No_Soft_Reset
    uint16_t bdf, vendor, device;
    uint32_t cls;
    bool nsr;
    uint8_t tier;                                // 1: on the 890M's buses, 2: other endpoint, 0: never
    uint8_t pre, set, post;
};
static constexpr unsigned kMaxFn = 48;
static PciFn gFn[kMaxFn];
static unsigned gFnN;

// 0.1.13: NBIO trace. The SMU marks NBIO "not met" for the whole sleep even with every endpoint but the RTX in D3hot
// (Step116 d3 4). Record, per root port and the endpoint behind it, the ASPM / L1 PM Substates / LTR setup at sleep and
// the root port's Link Status at halt entry and at wake, so the trace shows which link never leaves L0 or never gets
// L1.2 enabled. Read only: nothing here changes a link.
struct PciRp {
    volatile uint8_t *cfg;
    uint8_t pcie, sec;
    uint16_t l1ss, bdf;
    uint16_t staHalt, staWake;
};
static constexpr unsigned kMaxRp = 16;
static PciRp gRp[kMaxRp];
static unsigned gRpN;

static uint16_t extCap(volatile uint8_t *cfg, uint16_t id)
{
    uint16_t off = 0x100;
    for (unsigned n = 0; n < 64 && off >= 0x100; n++) {
        uint32_t h = *reinterpret_cast<volatile uint32_t *>(cfg + off);
        if (h == 0 || h == 0xffffffff) return 0;
        if ((h & 0xffff) == id) return off;
        off = uint16_t((h >> 20) & 0xffc);
    }
    return 0;
}

// "aspm S/E l1ss S/E ltr E genG xW dll D": S = supported bits, E = enabled bits (ASPM 1 = L0s, 2 = L1; L1SS bits
// 0..3 = PCI-PM L1.2, PCI-PM L1.1, ASPM L1.2, ASPM L1.1), LTR = Device Control 2 bit 10
static void linkDesc(char *b, size_t n, volatile uint8_t *cfg, uint8_t pcie, uint16_t l1ss)
{
    if (!pcie) { snprintf(b, n, "no PCIe cap"); return; }
    uint32_t lcap = *reinterpret_cast<volatile uint32_t *>(cfg + pcie + 0x0c);
    uint16_t lctl = *reinterpret_cast<volatile uint16_t *>(cfg + pcie + 0x10);
    uint16_t lsta = *reinterpret_cast<volatile uint16_t *>(cfg + pcie + 0x12);
    uint16_t dctl2 = *reinterpret_cast<volatile uint16_t *>(cfg + pcie + 0x28);
    unsigned sc = 0, ec = 0;
    if (l1ss) {
        sc = *reinterpret_cast<volatile uint32_t *>(cfg + l1ss + 4) & 0xf;
        ec = *reinterpret_cast<volatile uint32_t *>(cfg + l1ss + 8) & 0xf;
    }
    snprintf(b, n, "aspm %u/%u l1ss %s%x/%x ltr %u gen%u x%u dll %u", unsigned((lcap >> 10) & 3), unsigned(lctl & 3),
             l1ss ? "" : "none ", sc, ec, unsigned((dctl2 >> 10) & 1), unsigned(lsta & 0xf), unsigned((lsta >> 4) & 0x3f),
             unsigned((lsta >> 13) & 1));
}
static volatile uint32_t gD3Mode;                  // S0ix,D3Mode
static volatile uint8_t *gPmc;                     // PMC mailbox (0.1.3), for OS_HINT from the halt path
static volatile bool gHaltHint;                    // send OS_HINT from the halt path (0.1.4) instead of setPowerState
static volatile uint32_t gHintIn = 0xff, gHintOut = 0xff;

static uint32_t pmcRaw(uint32_t msg, uint32_t arg)  // amd_pmc protocol, spin only (halt path: interrupts off)
{
    auto reg = [](uint32_t o) -> volatile uint32_t & { return *reinterpret_cast<volatile uint32_t *>(gPmc + o); };
    unsigned n = 0;
    while (reg(0x980) == 0 && n++ < 20000) IODelay(50);
    if (reg(0x980) == 0) return 0x100;
    reg(0x980) = 0; reg(0x9BC) = arg; reg(0x938) = msg;
    uint32_t r; n = 0;
    while ((r = reg(0x980)) == 0 && n++ < 20000) IODelay(50);
    return r;
}

static void tscDelay(uint64_t tsc) { uint64_t t = rdtsc64(); while (rdtsc64() - t < tsc) asm volatile("pause"); }

// 0.1.5: pci_save_state / pci_restore_state for functions whose PMCSR No_Soft_Reset is 0 (D3hot -> D0 resets their
// config space): header in reverse (command last), the PCIe control registers, then MSI / MSI-X.
static void cfgSave(PciFn &f)
{
    auto c = reinterpret_cast<volatile uint32_t *>(f.cfg);
    for (unsigned i = 0; i < 64; i++) f.save[i] = c[i];
    f.saved = true;
}

static void cfgRestore(PciFn &f)
{
    if (!f.saved) return;
    auto w16 = [&](unsigned off) { *reinterpret_cast<volatile uint16_t *>(f.cfg + off) =
                                       uint16_t(f.save[off >> 2] >> ((off & 2) * 8)); };
    auto w32 = [&](unsigned off) { *reinterpret_cast<volatile uint32_t *>(f.cfg + off) = f.save[off >> 2]; };
    if (f.pcie) { w16(f.pcie + 0x08); w16(f.pcie + 0x10); w16(f.pcie + 0x18); w16(f.pcie + 0x1c); w16(f.pcie + 0x28); w16(f.pcie + 0x30); }
    auto c = reinterpret_cast<volatile uint32_t *>(f.cfg);
    for (int i = 15; i >= 1; i--) if (c[i] != f.save[i]) c[i] = f.save[i];
    if (f.msi) {
        uint16_t ctl = uint16_t(f.save[(f.msi + 2) >> 2] >> (((f.msi + 2) & 2) * 8));
        w32(f.msi + 4);
        if (ctl & 0x80) { w32(f.msi + 8); w16(f.msi + 0xc); } else w16(f.msi + 8);
        w16(f.msi + 2);
    }
    if (f.msix) w16(f.msix + 2);
    f.saved = false;
}

// which functions a D3 mode moves: 1 = 890M buses (No_Soft_Reset only), 2 = + other endpoints, 3 = + functions
// without No_Soft_Reset (config saved/restored) except the 890M itself, 4 = + the 890M, 5 = + the RTX (NSR only)
static bool d3Wanted(const PciFn &f, uint32_t mode)
{
    // 0.1.6: 5 = + the RTX and its audio (No_Soft_Reset 1), left in D0 by NVRM standby; NBIO stays busy with them in D0
    if (f.vendor == 0x10de) return mode >= 5 && f.nsr;
    if (!f.tier || f.tier > (mode < 2 ? mode : 2)) return false;
    if (f.nsr) return true;
    if (mode < 3) return false;
    bool gpu = f.vendor == 0x1002 && (f.cls >> 16) == 0x03;
    return !gpu || mode >= 4;
}

static void haltEnter()
{
    for (unsigned i = 0; i < gFnN; i++) {
        PciFn &f = gFn[i];
        uint16_t v = *f.pmcsr;
        f.pre = v & 3; f.set = f.pre; f.post = 0xff;
        if (f.pre == 0 && d3Wanted(f, gD3Mode)) {
            if (!f.nsr) cfgSave(f);
            *f.pmcsr = uint16_t((v & ~0x8003u) | 3);   // keep PME_En, do not clear PME_Status (W1C)
            f.set = 3;
        }
    }
    for (unsigned i = 0; i < gFnN; i++) if (gFn[i].set == 3 && gFn[i].pre == 0) { tscDelay(gTscHz / 100); break; }   // 10 ms
    for (unsigned i = 0; i < gRpN; i++) gRp[i].staHalt = *reinterpret_cast<volatile uint16_t *>(gRp[i].cfg + gRp[i].pcie + 0x12);
    gEcEnSet = false;
    gSeenGpe = gSeenPm1 = 0;
    gPin0IntMs = gPin0Toggles = 0;
    if (gGpio) for (unsigned i = 0; i < 7; i++) {
        gAeiHalt[i] = gAeiLast[i] = *reinterpret_cast<volatile uint32_t *>(gGpio + kAeiPins[i] * 4);
        gAeiFirstMs[i] = gAeiToggles[i] = 0;
    }
    if (gGpio && gGpioMode) {
        auto pin0 = reinterpret_cast<volatile uint32_t *>(gGpio);
        gPin0Saved = gPin0AtHalt = *pin0;
        uint32_t v = (gPin0Saved | (1u << 11) | (1u << 13)) & ~(3u << 28);
        if (gGpioMode == 1) v |= 1u << 12;        // deliver to IRQ 7, so a C-state ends on it
        *pin0 = v | (3u << 28);                   // W1C: drop the lid-close pulse latched before the halt
    }
    if (gEcMode == 1 && gEcGpe != 0xff && gEcGpe < gGpe0Len / 2 * 8) {
        uint16_t en = uint16_t(gGpe0Sts + gGpe0Len / 2 + (gEcGpe / 32) * 4);
        gEcEnSaved = gEcEnAtHalt = inl(en);
        uint32_t bit = 1u << (gEcGpe % 32);
        if (!(gEcEnSaved & bit)) { outl(en, gEcEnSaved | bit); gEcEnSet = true; }
    }
    if (gHaltHint && gPmc) gHintIn = pmcRaw(0x03, 1);
}

static void haltExit()
{
    if (gHaltHint && gPmc) gHintOut = pmcRaw(0x03, 0);
    for (unsigned i = 0; i < gRpN; i++) gRp[i].staWake = *reinterpret_cast<volatile uint16_t *>(gRp[i].cfg + gRp[i].pcie + 0x12);
    if (gGpio) for (unsigned i = 0; i < 7; i++) gAeiWake[i] = *reinterpret_cast<volatile uint32_t *>(gGpio + kAeiPins[i] * 4);
    if (gGpio && gGpioMode) {
        auto pin0 = reinterpret_cast<volatile uint32_t *>(gGpio);
        gPin0AtWake = *pin0;
        *pin0 = (gPin0Saved & ~(3u << 28)) | (3u << 28);   // old control word, status cleared before IRQs come back
    }
    if (gEcEnSet) { outl(uint16_t(gGpe0Sts + gGpe0Len / 2 + (gEcGpe / 32) * 4), gEcEnSaved); gEcEnSet = false; }
    bool any = false;
    for (unsigned i = 0; i < gFnN; i++) {
        PciFn &f = gFn[i];
        if (f.set == 3 && f.pre == 0) { *f.pmcsr = uint16_t(*f.pmcsr & ~0x8003u); any = true; }
    }
    if (any) tscDelay(gTscHz / 100);              // D3hot -> D0: 10 ms before the first config access
    for (unsigned i = 0; i < gFnN; i++) if (gFn[i].set == 3 && gFn[i].pre == 0 && !gFn[i].nsr) cfgRestore(gFn[i]);
    for (unsigned i = 0; i < gFnN; i++) gFn[i].post = *gFn[i].pmcsr & 3;
}

// 0.1.11: an EC GPE wake leaves macOS in dark wake even for the power button (Step121 19:22:33: no PWRB notify reached
// us, so the _QE7 Notify does not happen or does not count). Take the EC query ourselves at wake (status 0x66 SCI_EVT,
// command 0x84, data 0x62), then run that _Qxx from a thread and ask for a full wake on 0xE7 (power button).
// AppleACPIEC then finds no SCI_EVT and does nothing. gEcQuery: -1 not tried, -2 no SCI_EVT, -3 EC timeout, else xx.
static volatile int gEcQuery = -1;
// 0.1.12: EC queries that mean "the user wants the machine": a byte each, 0 = unused. Step122 (22:18:53): the power
// button during the halt is query 0xCE, whose _QCE only writes DBG8 (Modern Standby wake ping); 0xE7 is the button
// while awake. S0ix,UserQueries / boot-arg s0ix_userq change the list.
static volatile uint32_t gUserQ = 0x0000E7CE;
static volatile bool gEcQ = true;              // S0ix,EcQuery / boot-arg s0ix_ecquery=0 turns the interception off
static volatile uint8_t gEcSt;
static bool ecWait(uint8_t mask, uint8_t want)
{
    uint64_t end = rdtsc64() + gTscHz / 200;       // 5 ms
    while (((gEcSt = inb(0x66)) & mask) != want) if (rdtsc64() > end) return false;
    return true;
}
static void ecQuery()
{
    gEcSt = inb(0x66);
    if (!(gEcSt & 0x20)) { gEcQuery = -2; return; }
    if (!ecWait(0x02, 0)) { gEcQuery = -3; return; }
    outb(0x66, 0x84);
    if (!ecWait(0x01, 0x01)) { gEcQuery = -3; return; }
    gEcQuery = inb(0x62);
}

static void s0ixHalt(void)
{
    if (cpu_number() != 0 || !gArmed) {
        auto st = reinterpret_cast<volatile uint32_t *>(static_cast<uint8_t *>(gGetMyLCPU()) + kLcpuState);
        *st = kLcpuHalt;                          // cpu_exit_wait() waits for LCPU_HALT
        if (gCstPort && gCc6Cpus) {               // CC6 (caches flushed by the core); INIT/SIPI still restarts it
            asm volatile("wbinvd" ::: "memory");
            for (;;) (void)inb(gCstPort);
        }
        for (;;) asm volatile("wbinvd; hlt" ::: "memory");   // stock: only INIT/SIPI brings it back
    }
    gIdleEntries++;
    gHaltT0 = rdtsc64();
    haltEnter();
    uint64_t t0 = rdtsc64();
    uint32_t why, loops = 0, fast = 0, cc6 = 0, cc6fast = 0;
    // CC6 between checks: the wake event's SCI ends the C-state (interrupts stay masked); a pending non-wake
    // interrupt makes C2 return at once, and after a run of those the loop drops back to MWAITX with its timer
    while (gCc6Boot && gEcMode != 2 && !(gGpio && gGpioMode && !gGpioCc6) && gCstPort && !(why = wakeEvent())) {
        uint64_t a = rdtsc64();
        (void)inb(gCstPort);
        cc6++;
        sampleStatus();
        if (rdtsc64() - a < gTimeoutTsc / 1024) { if (++cc6fast > 2000) break; } else cc6fast = 0;
    }
    gLastCc6Loops = cc6;
    while (!(why = wakeEvent())) {
        uint64_t a = rdtsc64();
        asm volatile(".byte 0x0f, 0x01, 0xfa" :: "a"(gMonitorLine), "c"(0), "d"(0));                 // MONITORX
        asm volatile(".byte 0x0f, 0x01, 0xfb" :: "a"(0), "b"(gTimeoutTsc), "c"(3) : "memory");      // MWAITX C1, IRQ break, timer
        loops++;
        sampleStatus();
        // a masked interrupt that is not a wake event stays pending and breaks MWAITX at once: after a long run of
        // immediate returns give up and wake (macOS goes back to sleep from the dark wake) instead of spinning
        uint64_t b = rdtsc64();
        if (b - a < gTimeoutTsc / 1024) { if (++fast > 20000) { why = 0x80000000u; break; } }
        else fast = 0;
        if (gMaxIdleTsc && b - t0 > gMaxIdleTsc) { why = 0x40000000u; break; }   // safety net: no wake event seen
    }
    gLastIdleTsc = rdtsc64() - t0;
    haltExit();
    gEcQuery = -1;
    if (gEcGpe != 0xff && why == (0x10000u | gEcGpe) && gEcQ) ecQuery();
    gLastWhy = why;
    gLastLoops = loops;
    gLastFast = fast;
}

// ---- 0.1.14: runtime CPU idle (pmDispatch MachineIdle) -------------------------------------------------------------
// machine_idle() (25G332, checked in the kernel binary) calls pmDispatch->MachineIdle (offset 0x10) with interrupts off
// when it is set, and otherwise runs "sti; hlt; cli". HLT is C1: on AMD nothing else registers MachineIdle, so a core
// that is awake never power-gates (CC6) and the package never idles deeply, which keeps an idle macOS hot. Linux
// acpi_idle uses the firmware _CST: C1 MWAIT, C2 IO port 0x414 (18 us), C3 IO port 0x415 (350 us). An IO C-state read
// with IF=0 ends on any interrupt (the sleep path above relies on the same), and the local APIC timer keeps running in
// CC6 (CPUID 6 ARAT, machdep.cpu.thermal.invariant_APIC_timer = 1). The pending interrupt is taken by "sti; nop; cli".
// The state comes from a per-CPU average of the last idle lengths (a small "menu" governor): below S0ix,IdleC2us HLT,
// then C2, and in mode 2 C3 above S0ix,IdleC3us when PM1 BM_STS shows no bus master activity (Linux acpi_idle_bm_check).
// S0ix,IdleMode (boot-arg s0ix_idle, runtime s0ix-set idle): 0 = stock HLT (default), 1 = HLT/C2, 2 = HLT/C2/C3.
// Boot-arg -s0ixidleoff leaves MachineIdle unregistered (the kernel's own sti; hlt).
namespace { constexpr size_t kDispMachineIdle = 0x10 / 8; }
static inline void outw16(uint16_t port, uint16_t v) { asm volatile("outw %0, %1" :: "a"(v), "Nd"(port)); }
static volatile uint32_t gIdleMode, gIdleC2us = 40, gIdleC3us = 2000;
static volatile uint64_t gIdleC2Tsc, gIdleC3Tsc;
struct alignas(64) IdleStat { uint64_t pred, n[3], tsc[3], bmDemote; };
static IdleStat gIdle[64];

static void idleThresholds()
{
    gIdleC2Tsc = gTscHz / 1000000 * gIdleC2us;
    gIdleC3Tsc = gTscHz / 1000000 * gIdleC3us;
}

static uint64_t s0ixMachineIdle(uint64_t)
{
    int c = cpu_number();
    uint32_t mode = gIdleMode;
    uint16_t base = gCstBase;
    if (!mode || !base || c < 0 || c >= 64) {
        asm volatile("sti; hlt; cli" ::: "memory");
        return 0;
    }
    IdleStat &s = gIdle[c];
    unsigned k = s.pred < gIdleC2Tsc ? 0 : 1;
    if (k == 1 && mode >= 2 && s.pred >= gIdleC3Tsc) {
        if (inw(gPm1Sts) & 0x10) { outw16(gPm1Sts, 0x10); s.bmDemote++; }   // BM_STS: write 1 to clear, C2 this time
        else k = 2;
    }
    uint64_t t0 = rdtsc64(), dt;
    if (k == 0) {
        asm volatile("sti; hlt; cli" ::: "memory");
        dt = rdtsc64() - t0;
    } else {
        (void)inb(uint16_t(base + k));
        dt = rdtsc64() - t0;
        asm volatile("sti; nop; cli" ::: "memory");
    }
    s.pred = s.pred - (s.pred >> 3) + (dt >> 3);
    s.n[k]++;
    s.tsc[k] += dt;
    return 0;
}

class StrixS0ix : public IOService {
    OSDeclareDefaultStructors(StrixS0ix)
    void publishIdle(bool reset);
    IOACPIPlatformDevice *pep = nullptr;
    IOPCIDevice *rc = nullptr;                  // 00:00.0, for SMN index/data
    IOMemoryMap *pmcMap = nullptr, *smuMap = nullptr;
    volatile uint8_t *pmc = nullptr;
    const volatile uint8_t *smu = nullptr;        // struct smu_metrics
    bool pmcOn = false;
    uint32_t smuVer = 0;
    bool setupPmc();
    uint32_t smnRead(uint32_t addr);
    IOReturn pmcSend(uint32_t msg, uint32_t arg, uint32_t *out = nullptr);
    void pmcSleep();
    void pmcWake();
    void setupCc6();
    void setupEcWake();
    void setupGpio();
    static void gpioEvt(thread_call_param_t self, thread_call_param_t);
    IOACPIPlatformDevice *gpioDev = nullptr;
    IOMemoryMap *gpioMap = nullptr;
    thread_call_t evtCall = nullptr;
    // 0.1.10: the power button's EC SCI wakes the halt, but macOS stays in dark wake (Step120: 18:59:18, 19:03:21);
    // on Notify(PWRB, 0x80) soon after our wake, ask the root domain for a full wake like a HID event would
    IONotifier *pwrbNote = nullptr;
    IOACPIPlatformDevice *ecDev = nullptr;
    thread_call_t qCall = nullptr;
    static void ecEvt(thread_call_param_t self, thread_call_param_t);
    static IOReturn fullWake(const char *why);
    static IOReturn pwrbMsg(void *target, void *ref, UInt32 type, IOService *provider, void *arg, vm_size_t size);
    bool pciBuilt = false;
    uint64_t ecam = 0;
    void buildPci();
    void publishPci();
    bool pm = false, halt = false, useDsm = true, slept = false, shutdown = false;
    IOPMDriverAssertionID block = 0;
    UInt32 sleeps = 0;
    bool installHalt();
    void readFadt();
    void publishFacp(const OSData *facp);
    IOReturn dsm(UInt32 fn, OSObject **result = nullptr);
public:
    bool start(IOService *provider) override;
    IOReturn setPowerState(unsigned long state, IOService *device) override;
    IOReturn setProperties(OSObject *properties) override;
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
    publishFacp(facp);
}

// 0.1.2: NMXGPU's xkpi reads ACPI tables from the first registry entry with an "ACPI Tables" dictionary
// (nmx_platform.cpp copy_acpi_tables). On Tahoe that is StrixVFCT's node, which holds only VFCT, so xkpi zeroed its
// FADT copy ("no FADT; ACPI power flags read as zero"), amdgpu saw LOW_POWER_S0 clear ("BIOS has not been configured
// for suspend-to-idle") and skipped suspend and resume: the 890M stayed fully powered in S0 sleep (Step109d/110).
// Add the live FACP to that dictionary (or publish one here when StrixVFCT is absent). This runs before NMXGPU's
// SYSINIT (Step110 boot: 64 ms earlier); if NMXGPU ever wins the race it sees today's state. -s0ixnofacp skips it.
void StrixS0ix::publishFacp(const OSData *facp)
{
    if (PE_parse_boot_argn("-s0ixnofacp", nullptr, 0)) { IOLog("StrixS0ix: -s0ixnofacp, FACP not published\n"); return; }
    uint32_t flags;
    memcpy(&flags, static_cast<const uint8_t *>(facp->getBytesNoCopy()) + 112, 4);
    setProperty("S0ix,FadtFlags", flags, 32);
    const OSSymbol *key = OSSymbol::withCString("ACPI Tables");
    IORegistryEntry *host = nullptr;
    if (IORegistryEntry *root = IORegistryEntry::getRegistryRoot()) {
        if (IORegistryIterator *it = IORegistryIterator::iterateOver(root, gIOServicePlane, kIORegistryIterateRecursively)) {
            while (IORegistryEntry *e = it->getNextObject())
                if (OSDynamicCast(OSDictionary, e->getProperty(key))) { host = e; host->retain(); break; }
            it->release();
        }
    }
    OSDictionary *old = host ? OSDynamicCast(OSDictionary, host->getProperty(key)) : nullptr;
    OSDictionary *tables = old ? OSDictionary::withDictionary(old, old->getCount() + 1) : OSDictionary::withCapacity(1);
    const char *where = "none";
    if (tables) {
        if (old && old->getObject("FACP")) where = "already there";
        else {
            tables->setObject("FACP", facp);
            IORegistryEntry *dst = host ? host : this;
            dst->setProperty(key, tables);
            where = host ? host->getName() : "StrixS0ix (no other ACPI Tables entry)";
        }
        tables->release();
    }
    OSSafeReleaseNULL(host);
    key->release();
    IOLog("StrixS0ix: FACP (%u bytes, flags %#x, LOW_POWER_S0 %s) published for xkpi: %s\n", facp->getLength(), flags,
          (flags & (1u << 21)) ? "set" : "CLEAR", where);
}

// ---- S0i3 (0.1.3) ----------------------------------------------------------------------------------------------
namespace {
constexpr uint32_t kPmcBaseLo = 0x13B102E8, kPmcBaseHi = 0x13B102EC, kPmcOffset = 0x10000;   // amd_pmc pmc.h
constexpr uint32_t kPmcMsg = 0x938, kPmcArg = 0x9BC, kPmcRsp = 0x980, kPmcScratch = 0xF14;    // family 1Ah model 20h
constexpr uint32_t kMsgVersion = 0x02, kMsgOsHint = 0x03, kMsgLogAddrHi = 0x04, kMsgLogAddrLo = 0x05,
                   kMsgLogStart = 0x06, kMsgLogReset = 0x07, kMsgLogDump = 0x08;
constexpr uint32_t kSmuMetricsSize = 0x250;
}

uint32_t StrixS0ix::smnRead(uint32_t addr)
{
    rc->configWrite32(0x60, addr);              // amd_nb SMN index/data on the root complex
    return rc->configRead32(0x64);
}

IOReturn StrixS0ix::pmcSend(uint32_t msg, uint32_t arg, uint32_t *out)
{
    auto reg = [this](uint32_t o) -> volatile uint32_t & { return *reinterpret_cast<volatile uint32_t *>(pmc + o); };
    unsigned n = 0;
    while (reg(kPmcRsp) == 0 && n++ < 20000) IODelay(50);   // previous command done (1 s)
    if (reg(kPmcRsp) == 0) return kIOReturnBusy;
    reg(kPmcRsp) = 0;
    reg(kPmcArg) = arg;
    reg(kPmcMsg) = msg;
    n = 0;
    uint32_t r;
    while ((r = reg(kPmcRsp)) == 0 && n++ < 20000) IODelay(50);
    if (r == 1) { if (out) *out = reg(kPmcArg); return kIOReturnSuccess; }
    return r == 0 ? kIOReturnTimeout : r == 0xFC ? kIOReturnBusy : r == 0xFE ? kIOReturnUnsupported : kIOReturnError;
}

bool StrixS0ix::setupPmc()
{
    UInt32 want = 1;
    PE_parse_boot_argn("s0ix_pmc", &want, sizeof want);
    if (!want) { IOLog("StrixS0ix: s0ix_pmc=0, no SMU OS hint\n"); return false; }
    if (OSDictionary *m = IOService::serviceMatching("IOPCIDevice")) {
        if (OSIterator *it = IOService::getMatchingServices(m)) {
            while (auto d = OSDynamicCast(IOPCIDevice, it->getNextObject()))
                if (d->getBusNumber() == 0 && d->getDeviceNumber() == 0 && d->getFunctionNumber() == 0) {
                    rc = d; rc->retain(); break;
                }
            it->release();
        }
        m->release();
    }
    if (!rc) { IOLog("StrixS0ix: no 00:00.0 root complex, no SMU OS hint\n"); return false; }
    uint32_t id = rc->configRead32(0);
    if ((id & 0xffff) != 0x1022 || (id >> 16) != 0x1507) {
        IOLog("StrixS0ix: root complex %08x is not Strix (1022:1507), no SMU OS hint\n", id);
        return false;
    }
    uint32_t lo = smnRead(kPmcBaseLo) & 0xFFF00000u, hi = smnRead(kPmcBaseHi) & 0xFFFFu;
    uint64_t base = (uint64_t(hi) << 32 | lo) + kPmcOffset;
    if (!lo && !hi) { IOLog("StrixS0ix: PMC base reads 0, no SMU OS hint\n"); return false; }
    if (IODeviceMemory *mem = IODeviceMemory::withRange(base, 0x1000)) {
        pmcMap = mem->map(kIOMapInhibitCache);
        mem->release();
    }
    if (!pmcMap) { IOLog("StrixS0ix: PMC %#llx not mappable\n", base); return false; }
    pmc = reinterpret_cast<volatile uint8_t *>(pmcMap->getVirtualAddress());
    IOReturn r = pmcSend(kMsgVersion, 0, &smuVer);
    if (r != kIOReturnSuccess) { IOLog("StrixS0ix: PMC at %#llx: SMU version -> %#x, no SMU OS hint\n", base, r); return false; }
    uint32_t tlo = 0, thi = 0;
    if (pmcSend(kMsgLogAddrLo, 0, &tlo) == kIOReturnSuccess && pmcSend(kMsgLogAddrHi, 0, &thi) == kIOReturnSuccess &&
        (tlo || thi)) {
        uint64_t t = uint64_t(thi) << 32 | tlo, page = t & ~0xfffULL;
        if (IOMemoryDescriptor *md = IOMemoryDescriptor::withPhysicalAddress(page, (t - page) + kSmuMetricsSize + 0xfff & ~0xfffULL,
                                                                               kIODirectionIn)) {
            smuMap = md->map(kIOMapInhibitCache);
            md->release();
        }
        if (smuMap) smu = reinterpret_cast<const volatile uint8_t *>(smuMap->getVirtualAddress() + (t - page));
    }
    setProperty("S0ix,SmuVersion", smuVer, 32);
    IOLog("StrixS0ix: PMC mailbox at %#llx, SMU %u.%u.%u, metrics table %s, idlemask %#x\n", base, (smuVer >> 16) & 0xff,
          (smuVer >> 8) & 0xff, smuVer & 0xff, smu ? "mapped" : "NOT available",
          *reinterpret_cast<volatile uint32_t *>(pmc + kPmcScratch));
    return true;
}

void StrixS0ix::pmcSleep()
{
    if (!pmcOn) return;
    IOReturn a = kIOReturnSuccess, b = kIOReturnSuccess;
    if (smu) { a = pmcSend(kMsgLogReset, 0); b = pmcSend(kMsgLogStart, 0); }
    gPmc = pmc;
    bool fromHalt = gHaltHint && halt;
    IOReturn h = fromHalt ? kIOReturnSuccess : pmcSend(kMsgOsHint, 1);
    gHintIn = gHintOut = 0xff;
    IOLog("StrixS0ix: SMU log reset/start %#x/%#x, OS_HINT(1) %s %#x, idlemask %#x\n", a, b, fromHalt ? "deferred to halt" : "sent", h,
          *reinterpret_cast<volatile uint32_t *>(pmc + kPmcScratch));
}

void StrixS0ix::pmcWake()
{
    if (!pmcOn) return;
    uint32_t mask = *reinterpret_cast<volatile uint32_t *>(pmc + kPmcScratch);
    IOReturn h = (gHaltHint && halt) ? (gHintOut == 1 ? kIOReturnSuccess : kIOReturnError) : pmcSend(kMsgOsHint, 0);
    IOReturn d = smu ? pmcSend(kMsgLogDump, 0) : kIOReturnUnsupported;
    setProperty("S0ix,SmuIdleMask", mask, 32);
    if (!smu || d != kIOReturnSuccess) {
        IOLog("StrixS0ix: OS_HINT(0) %#x, idlemask %#x, metrics dump %#x\n", h, mask, d);
        return;
    }
    uint8_t t[kSmuMetricsSize];
    for (size_t i = 0; i < sizeof t; i++) t[i] = smu[i];
    uint32_t hints, status;
    uint64_t entering, resume, s0i3;
    memcpy(&hints, t + 0x04, 4);
    memcpy(&status, t + 0x08, 4);
    memcpy(&entering, t + 0x10, 8);
    memcpy(&resume, t + 0x20, 8);
    memcpy(&s0i3, t + 0x30, 8);
    setProperty("S0ix,SmuS0i3Entered", status, 32);
    setProperty("S0ix,SmuS0i3Us", s0i3, 64);
    setProperty("S0ix,SmuHintCount", hints, 32);
    // timecondition_notmet_lastcapture[32] at 0x50: per IP block (amd_pmc soc15_ip_blk order), time it was not idle
    if (OSData *nm = OSData::withBytes(t + 0x50, 32 * 8)) { setProperty("S0ix,SmuNotMetUs", nm); nm->release(); }
    // SMU 93.11 fills 16 per-block slots (0..15) followed by 16 running totals (16..31, slot i + 16). Slot 15 holds
    // no block time (values in the 1e18 us range), so the log names slots 0..14 only; the raw 32 stay in SmuNotMetUs.
    static const char *const kBlk[15] = { "DISPLAY", "CPU", "GFX", "VDD", "VDD_CCX", "ACP", "VCN0", "VCN1", "ISP",
                                          "NBIO", "DF", "USB3_0", "USB3_1", "LAPIC", "USB3_2" };
    char list[200] = "";
    size_t at = 0;
    for (unsigned i = 0; i < 15 && at + 24 < sizeof list; i++) {
        uint64_t v;
        memcpy(&v, t + 0x50 + i * 8, 8);
        if (v) at += (size_t)snprintf(list + at, sizeof list - at, " %s %llums", kBlk[i], v / 1000);
    }
    IOLog("StrixS0ix: OS_HINT(0) %#x, S0i3 %s, %llu ms in S0i3 (entry %llu us, resume %llu us), hints %u, idlemask %#x, "
          "not met:%s\n", h, status ? "REACHED" : "not reached", s0i3 / 1000, entering, resume, hints, mask,
          at ? list : " none");
}

void StrixS0ix::setupGpio()
{
    UInt32 mode = 0;                                // 0.1.10: off by default; pin 0 never moved in Step120 (lid, button), and
    PE_parse_boot_argn("s0ix_gpiowake", &mode, sizeof mode);   // an armed pin keeps the boot CPU out of CC6
    gGpioMode = mode > 2 ? 2 : mode;
    if (IOService *g = IOService::copyMatchingService(IOService::nameMatching("AMDI0030"))) {
        gpioDev = OSDynamicCast(IOACPIPlatformDevice, g);
        if (gpioDev) {
            gpioDev->retain();
            if (IODeviceMemory *m = gpioDev->getDeviceMemoryWithIndex(0))
                if ((gpioMap = m->map(kIOMapInhibitCache)))
                    gGpio = reinterpret_cast<volatile uint8_t *>(gpioMap->getVirtualAddress());
        }
        g->release();
    }
    evtCall = thread_call_allocate(&StrixS0ix::gpioEvt, this);
    uint32_t pin0 = gGpio ? *reinterpret_cast<volatile uint32_t *>(gGpio) : 0;
    setProperty("S0ix,GpioWake", gGpioMode, 32);
    setProperty("S0ix,GpioPin0", pin0, 32);
    IOLog("StrixS0ix: AMD GPIO %s, pin 0 (lid + power button, _AEI) control %#x, wake mode %u\n",
          gGpio ? "mapped" : "NOT found", pin0, unsigned(gGpioMode));
}

// after a pin 0 wake: what Windows / Linux do with the _AEI event (Notify PWRB and LID0); EC needs to be up first
void StrixS0ix::gpioEvt(thread_call_param_t self, thread_call_param_t)
{
    auto me = static_cast<StrixS0ix *>(self);
    if (!me->gpioDev) return;
    OSNumber *n = OSNumber::withNumber(0ULL, 32);
    OSObject *arg[1] = { n };
    IOReturn r = me->gpioDev->evaluateObject("_EVT", nullptr, arg, 1);
    if (n) n->release();
    IOLog("StrixS0ix: GPIO._EVT(0) after the pin 0 wake -> %#x\n", r);
}

static uint64_t gWakeAbs;
// requestUserActive is not exported to kexts; a display wrangler activity tickle is the exported path that the root
// domain turns into a full wake from dark wake (kStimulusDarkWakeActivityTickle), the same as a HID event
IOReturn StrixS0ix::fullWake(const char *why)
{
    IOReturn r = kIOReturnNotFound;
    if (IOService *w = IOService::copyMatchingService(IOService::serviceMatching("IODisplayWrangler"))) {
        r = w->activityTickle(kIOPMSuperclassPolicy1, 4) ? kIOReturnSuccess : kIOReturnNotReady;
        w->release();
    }
    IOLog("StrixS0ix: %s: display wrangler tickle -> %#x\n", why, r);
    return r;
}

void StrixS0ix::ecEvt(thread_call_param_t self, thread_call_param_t)
{
    auto me = static_cast<StrixS0ix *>(self);
    int q = gEcQuery;
    if (q < 0 || !me->ecDev) return;
    char name[5] = { '_', 'Q', "0123456789ABCDEF"[(q >> 4) & 15], "0123456789ABCDEF"[q & 15], 0 };
    IOReturn r = me->ecDev->evaluateObject(name);
    IOLog("StrixS0ix: EC query %#x at the wake, %s -> %#x\n", q, name, r);
    for (unsigned i = 0; i < 4; i++)
        if (uint32_t((gUserQ >> (8 * i)) & 0xff) == uint32_t(q) && q) { fullWake(q == 0xCE ? "power button (_QCE)" : name); break; }
}          // mach_absolute_time of our last setPowerState(1) after a sleep
IOReturn StrixS0ix::pwrbMsg(void *target, void *, UInt32 type, IOService *, void *arg, vm_size_t)
{
    auto me = static_cast<StrixS0ix *>(target);
    uintptr_t v = reinterpret_cast<uintptr_t>(arg);
    uint64_t ns = 0;
    if (gWakeAbs) absolutetime_to_nanoseconds(mach_absolute_time() - gWakeAbs, &ns);
    bool near = gWakeAbs && ns < 60ull * NSEC_PER_SEC;
    bool press = type == kIOACPIMessageDeviceNotification && v == 0x80;
    IOLog("StrixS0ix: PWRB message %#x arg %#lx, %llu ms after the wake%s\n", type, (unsigned long)v, ns / 1000000,
          press && near ? ": power button, asking for a full wake" : "");
    // requestUserActive is not exported to kexts; a display wrangler activity tickle is the exported path that the root
    // domain turns into a full wake from dark wake (kStimulusDarkWakeActivityTickle), the same as a HID event
    if (press && near) fullWake("PWRB notify 0x80");
    (void)me;
    return kIOReturnSuccess;
}

void StrixS0ix::setupEcWake()
{
    UInt32 on = 1;
    PE_parse_boot_argn("s0ix_ecwake", &on, sizeof on);
    UInt32 gpe = 0x0A;
    if (IOService *ec = IOService::copyMatchingService(IOService::nameMatching("PNP0C09"))) {
        if (auto dev = OSDynamicCast(IOACPIPlatformDevice, ec)) { dev->evaluateInteger("_GPE", &gpe); ecDev = dev; dev->retain(); }
        ec->release();
    }
    gEcGpe = gpe < 0xff ? uint8_t(gpe) : 0xff;
    UInt32 q = 1, uq = gUserQ;
    PE_parse_boot_argn("s0ix_userq", &uq, sizeof uq);
    gUserQ = uq;
    setProperty("S0ix,UserQueries", gUserQ, 32);
    PE_parse_boot_argn("s0ix_ecquery", &q, sizeof q);
    gEcQ = q != 0;
    qCall = thread_call_allocate(&StrixS0ix::ecEvt, this);
    gEcMode = on > 2 ? 2 : on;
    setProperty("S0ix,EcWakeGpe", gEcGpe, 8);
    setProperty("S0ix,EcWake", gEcMode, 32);
    IOLog("StrixS0ix: EC GPE %#x mode %u as a wake source (lid, power button)\n", gpe, unsigned(gEcMode));
    if (IOService *pb = IOService::copyMatchingService(IOService::nameMatching("PNP0C0C"))) {
        pwrbNote = pb->registerInterest(gIOGeneralInterest, &StrixS0ix::pwrbMsg, this);
        pb->release();
    }
    IOLog("StrixS0ix: PWRB notify %s\n", pwrbNote ? "watched (full wake on 0x80 after a sleep)" : "NOT found");
}

void StrixS0ix::setupCc6()
{
    UInt32 v = 1;
    PE_parse_boot_argn("s0ix_cc6", &v, sizeof v);
    gCc6Cpus = v != 0;
    v = 1;                                          // 0.1.4: on by default (Step112 run 2: CC6 for 60 s, RTC wake on time)
    PE_parse_boot_argn("s0ix_cc6boot", &v, sizeof v);
    gCc6Boot = v != 0;
    uint64_t base = rdmsr64(0xC0010073) & 0xffff;   // CStateBaseAddr
    UInt32 depth = 2;                               // 0.1.5: _CST C3 (port base+2, 350 us) is the deepest; C2 = base+1
    PE_parse_boot_argn("s0ix_cst", &depth, sizeof depth);
    if (depth < 1 || depth > 2) depth = 2;
    if (base >= 0x100 && base < 0xfff0) { gCstBase = uint16_t(base); gCstPort = uint16_t(base + depth); }
    setProperty("S0ix,CstDepth", depth, 32);
    setProperty("S0ix,CstPort", gCstPort, 16);
    setProperty("S0ix,CC6Cpus", gCc6Cpus && gCstPort);
    setProperty("S0ix,BootCC6", gCc6Boot && gCstPort);
    IOLog("StrixS0ix: CStateBaseAddr %#llx, CC6 port %#x, non-boot CPUs %s, boot CPU %s\n", base, gCstPort,
          gCc6Cpus && gCstPort ? "CC6" : "HLT", gCc6Boot && gCstPort ? "CC6" : "MWAITX");
}

void StrixS0ix::buildPci()
{
    if (pciBuilt) return;
    pciBuilt = true;
    if (const OSData *mcfg = pep->getACPITableData("MCFG", 0)) {
        // not retained for us (as FACP in readFadt): releasing it panicked the first 0.1.4 sleep ("A kext releasing a(n)
        // OSData ... has corrupted the registry", Kernel-2026-11-05-105201.panic)
        if (mcfg->getLength() >= 56) memcpy(&ecam, static_cast<const uint8_t *>(mcfg->getBytesNoCopy()) + 44, 8);
    }
    if (!ecam) { IOLog("StrixS0ix: no MCFG, no PCI D-state work\n"); return; }
    OSDictionary *m = IOService::serviceMatching("IOPCIDevice");
    OSIterator *it = m ? IOService::getMatchingServices(m) : nullptr;
    unsigned igpuBus[2] = { 0x100, 0x100 };
    IOPCIDevice *list[kMaxFn]; unsigned n = 0;
    while (it && n < kMaxFn) {
        auto d = OSDynamicCast(IOPCIDevice, it->getNextObject());
        if (!d) break;
        if ((d->configRead8(0x0E) & 0x7f) != 0) {                   // bridges stay as they are
            UInt8 pc = 0;
            if (d->getBusNumber() == 0 && (d->configRead8(0x0E) & 0x7f) == 1 && gRpN < kMaxRp &&
                d->findPCICapability(kIOPCIPCIExpressCapability, &pc) && pc && ((d->configRead16(pc + 2) >> 4) & 0xf) == 4) {
                uint64_t pa = ecam + (uint64_t(d->getDeviceNumber()) << 15 | uint64_t(d->getFunctionNumber()) << 12);
                IODeviceMemory *mem = IODeviceMemory::withRange(pa, 0x1000);
                IOMemoryMap *map = mem ? mem->map(kIOMapInhibitCache) : nullptr;
                OSSafeReleaseNULL(mem);
                if (map) {                                           // kept for the life of the kext
                    PciRp &r = gRp[gRpN++];
                    r.cfg = reinterpret_cast<volatile uint8_t *>(map->getVirtualAddress());
                    r.pcie = pc; r.sec = d->configRead8(0x19);
                    r.bdf = uint16_t(d->getDeviceNumber() << 3 | d->getFunctionNumber());
                    r.l1ss = extCap(r.cfg, 0x1e);
                    r.staHalt = r.staWake = 0;
                }
            }
            continue;
        }
        uint32_t id = d->configRead32(0), cls = d->configRead32(8) >> 8;
        if ((id & 0xffff) == 0x1002 && (cls >> 16) == 0x03) igpuBus[0] = d->getBusNumber();
        if (id == 0x150d1022) igpuBus[1] = d->getBusNumber();       // NPU bus (IPU sits next to it)
        list[n++] = d;
    }
    OSSafeReleaseNULL(it); OSSafeReleaseNULL(m);
    for (unsigned i = 0; i < n && gFnN < kMaxFn; i++) {
        IOPCIDevice *d = list[i];
        UInt8 pmOff = 0;
        if (!d->findPCICapability(kIOPCIPowerManagementCapability, &pmOff) || !pmOff) continue;
        uint32_t id = d->configRead32(0), cls = d->configRead32(8) >> 8;
        unsigned bus = d->getBusNumber(), dev = d->getDeviceNumber(), fn = d->getFunctionNumber();
        uint64_t pa = ecam + (uint64_t(bus) << 20 | uint64_t(dev) << 15 | uint64_t(fn) << 12);
        IODeviceMemory *mem = IODeviceMemory::withRange(pa, 0x1000);
        IOMemoryMap *map = mem ? mem->map(kIOMapInhibitCache) : nullptr;
        OSSafeReleaseNULL(mem);
        if (!map) continue;                                          // kept for the life of the kext
        auto base = reinterpret_cast<volatile uint8_t *>(map->getVirtualAddress());
        if (*reinterpret_cast<volatile uint32_t *>(base) != id) { map->release(); continue; }   // ECAM must agree
        PciFn &f = gFn[gFnN++];
        f.cfg = base;
        f.pmcsr = reinterpret_cast<volatile uint16_t *>(base + pmOff + 4);
        UInt8 cap = 0;
        f.pcie = d->findPCICapability(kIOPCIPCIExpressCapability, &cap) ? cap : 0;
        cap = 0; f.msi = d->findPCICapability(kIOPCIMSICapability, &cap) ? cap : 0;
        cap = 0; f.msix = d->findPCICapability(kIOPCIMSIXCapability, &cap) ? cap : 0;
        f.l1ss = extCap(base, 0x1e);
        f.saved = false;
        f.bdf = uint16_t(bus << 8 | dev << 3 | fn);
        f.vendor = uint16_t(id); f.device = uint16_t(id >> 16); f.cls = cls;
        f.nsr = (*f.pmcsr & 0x8) != 0;
        bool usb = cls == 0x0C0330, nvme = (cls >> 8) == 0x0108, nv = f.vendor == 0x10de;
        f.tier = (usb || nvme || nv || bus == 0) ? 0 : (bus == igpuBus[0] || bus == igpuBus[1]) ? 1 : 2;
        f.pre = f.set = f.post = 0xff;
    }
    IOLog("StrixS0ix: PCI D-state table: %u functions (ECAM %#llx, 890M bus %#x, NPU bus %#x), D3 mode %u\n", gFnN, ecam,
          igpuBus[0], igpuBus[1], unsigned(gD3Mode));
}

static void logLinks(IOService *svc)
{
    OSArray *a = OSArray::withCapacity(gRpN);
    for (unsigned i = 0; i < gRpN; i++) {
        const PciRp &r = gRp[i];
        char rp[96], ep[96] = "no endpoint", line[240];
        linkDesc(rp, sizeof rp, r.cfg, r.pcie, r.l1ss);
        unsigned epBdf = 0xffff;
        for (unsigned j = 0; j < gFnN; j++) if ((gFn[j].bdf >> 8) == r.sec) {
            linkDesc(ep, sizeof ep, gFn[j].cfg, gFn[j].pcie, gFn[j].l1ss); epBdf = gFn[j].bdf; break;
        }
        snprintf(line, sizeof line, "00:%02x.%x -> %02x: rp %s; ep %02x:00.%x %s", r.bdf >> 3, r.bdf & 7, r.sec, rp,
                 epBdf >> 8, epBdf & 7, ep);
        IOLog("StrixS0ix: link %s\n", line);
        if (a) if (OSString *str = OSString::withCString(line)) { a->setObject(str); str->release(); }
    }
    if (a) { svc->setProperty("S0ix,Links", a); a->release(); }
}

void StrixS0ix::publishPci()
{
    if (gRpN) {
        char l[300]; size_t at = 0; l[0] = 0;
        for (unsigned i = 0; i < gRpN && at + 40 < sizeof l; i++)   // DLL active and width at halt / at wake
            at += (size_t)snprintf(l + at, sizeof l - at, " %02x:%u/%u", gRp[i].sec, unsigned((gRp[i].staHalt >> 13) & 1),
                                   unsigned((gRp[i].staWake >> 13) & 1));
        IOLog("StrixS0ix: root port DLL active at halt/wake (secondary bus: halt/wake):%s\n", l);
    }
    if (!gFnN) return;
    OSArray *a = OSArray::withCapacity(gFnN);
    char d3[200], d0[200]; size_t a3 = 0, a0 = 0;      // moved to D3 by the halt path / left in D0 for the whole sleep
    d3[0] = d0[0] = 0;
    for (unsigned i = 0; i < gFnN && a; i++) {
        const PciFn &f = gFn[i];
        char e[64];
        snprintf(e, sizeof e, "%02x:%02x.%x %04x:%04x cls %06x nsr %u tier %u D%u->D%u->D%u", f.bdf >> 8, (f.bdf >> 3) & 0x1f,
                 f.bdf & 7, f.vendor, f.device, f.cls, f.nsr, f.tier, f.pre, f.set, f.post);
        if (OSString *str = OSString::withCString(e)) { a->setObject(str); str->release(); }
        if (f.pre != 0) continue;
        char *b = f.set == 3 ? d3 : d0;
        size_t &n = f.set == 3 ? a3 : a0;
        if (n + 12 < sizeof d3) n += (size_t)snprintf(b + n, sizeof d3 - n, " %02x:%02x.%x", f.bdf >> 8, (f.bdf >> 3) & 0x1f, f.bdf & 7);
    }
    if (a) { setProperty("S0ix,PciStates", a); a->release(); }
    IOLog("StrixS0ix: halt path put in D3:%s; left in D0:%s; OS_HINT from halt in/out %#x/%#x\n", a3 ? d3 : " none",
          a0 ? d0 : " none", gHintIn, gHintOut);
}

// "S0ix,BootCC6" = true/false from user space (scripts/macos-syssleep-test.sh): no reboot needed to try it
// "S0ix,IdleStats": per idle state the entry count and the time spent in it, summed over all CPUs since the last reset
void StrixS0ix::publishIdle(bool reset)
{
    uint64_t n[3] = {}, t[3] = {}, bm = 0;
    for (auto &s : gIdle) {
        for (int k = 0; k < 3; k++) { n[k] += s.n[k]; t[k] += s.tsc[k]; }
        bm += s.bmDemote;
    }
    uint64_t khz = gTscHz / 1000 ? gTscHz / 1000 : 1;
    char buf[200];
    snprintf(buf, sizeof buf, "mode %u: HLT %llu x %llu ms, C2 %llu x %llu ms, C3 %llu x %llu ms, bm demote %llu",
             unsigned(gIdleMode), n[0], t[0] / khz, n[1], t[1] / khz, n[2], t[2] / khz, bm);
    setProperty("S0ix,IdleStats", buf);
    if (reset)
        for (auto &s : gIdle) { for (int k = 0; k < 3; k++) { s.n[k] = 0; s.tsc[k] = 0; } s.bmDemote = 0; }
}

IOReturn StrixS0ix::setProperties(OSObject *properties)
{
    auto d = OSDynamicCast(OSDictionary, properties);
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,IdleMode")) : nullptr) {
        if (!gDispatch[kDispMachineIdle] || !gCstBase) return kIOReturnUnsupported;
        gIdleMode = n->unsigned32BitValue() > 2 ? 2 : n->unsigned32BitValue();
        setProperty("S0ix,IdleMode", gIdleMode, 32);
        publishIdle(true);
        IOLog("StrixS0ix: runtime idle mode now %u (0 HLT, 1 HLT/C2, 2 HLT/C2/C3)\n", unsigned(gIdleMode));
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,IdleC2us")) : nullptr) {
        gIdleC2us = n->unsigned32BitValue();
        idleThresholds();
        setProperty("S0ix,IdleC2us", gIdleC2us, 32);
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,IdleC3us")) : nullptr) {
        gIdleC3us = n->unsigned32BitValue();
        idleThresholds();
        setProperty("S0ix,IdleC3us", gIdleC3us, 32);
        return kIOReturnSuccess;
    }
    if (auto b0 = d ? OSDynamicCast(OSBoolean, d->getObject("S0ix,IdleStats")) : nullptr) {
        publishIdle(b0->isTrue());              // true = publish and reset the counters, false = publish only
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,D3Mode")) : nullptr) {
        gD3Mode = n->unsigned32BitValue() > 5 ? 5 : n->unsigned32BitValue();
        setProperty("S0ix,D3Mode", gD3Mode, 32);
        IOLog("StrixS0ix: D3 mode now %u\n", unsigned(gD3Mode));
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,CstDepth")) : nullptr) {
        uint32_t depth = n->unsigned32BitValue();
        if (!gCstBase || depth < 1 || depth > 2) return kIOReturnBadArgument;
        gCstPort = uint16_t(gCstBase + depth);
        setProperty("S0ix,CstDepth", depth, 32);
        setProperty("S0ix,CstPort", gCstPort, 16);
        IOLog("StrixS0ix: C-state port now %#x (_CST C%u)\n", unsigned(gCstPort), depth + 1);
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,UserQueries")) : nullptr) {
        gUserQ = n->unsigned32BitValue();
        setProperty("S0ix,UserQueries", gUserQ, 32);
        IOLog("StrixS0ix: EC queries that ask for a full wake now %#x\n", unsigned(gUserQ));
        return kIOReturnSuccess;
    }
    if (auto q = d ? OSDynamicCast(OSBoolean, d->getObject("S0ix,EcQuery")) : nullptr) {
        gEcQ = q->isTrue();
        setProperty("S0ix,EcQuery", bool(gEcQ));
        IOLog("StrixS0ix: EC query at the wake %s\n", gEcQ ? "taken by us" : "left to AppleACPIEC");
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,DsmSkip")) : nullptr) {
        gDsmSkip = n->unsigned32BitValue() & 0x1f8;
        setProperty("S0ix,DsmSkip", gDsmSkip, 32);
        IOLog("StrixS0ix: PEP _DSM skip mask now %#x\n", unsigned(gDsmSkip));
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,GpioWake")) : nullptr) {
        gGpioMode = n->unsigned32BitValue() > 2 ? 2 : n->unsigned32BitValue();
        setProperty("S0ix,GpioWake", gGpioMode, 32);
        IOLog("StrixS0ix: GPIO pin 0 wake mode now %u\n", unsigned(gGpioMode));
        return kIOReturnSuccess;
    }
    if (auto b2 = d ? OSDynamicCast(OSBoolean, d->getObject("S0ix,GpioCc6")) : nullptr) {
        gGpioCc6 = b2->isTrue();
        setProperty("S0ix,GpioCc6", bool(gGpioCc6));
        IOLog("StrixS0ix: boot CPU %s while GPIO wake is armed\n", gGpioCc6 ? "in CC6" : "on MWAITX");
        return kIOReturnSuccess;
    }
    if (auto n = d ? OSDynamicCast(OSNumber, d->getObject("S0ix,EcWake")) : nullptr) {
        gEcMode = n->unsigned32BitValue() > 2 ? 2 : n->unsigned32BitValue();
        setProperty("S0ix,EcWake", gEcMode, 32);
        IOLog("StrixS0ix: EC GPE %#x now %s\n", unsigned(gEcGpe),
              gEcMode == 1 ? "a wake source" : gEcMode == 2 ? "observed only (no EC wake, MWAITX loop)" : "off");
        return kIOReturnSuccess;
    }
    if (auto h = d ? OSDynamicCast(OSBoolean, d->getObject("S0ix,HaltHint")) : nullptr) {
        gHaltHint = h->isTrue();
        setProperty("S0ix,HaltHint", bool(gHaltHint));
        IOLog("StrixS0ix: OS_HINT now from the %s\n", gHaltHint ? "halt path" : "power state change");
        return kIOReturnSuccess;
    }
    auto b = d ? OSDynamicCast(OSBoolean, d->getObject("S0ix,BootCC6")) : nullptr;
    if (!b) return kIOReturnUnsupported;
    gCc6Boot = b->isTrue() && gCstPort;
    setProperty("S0ix,BootCC6", bool(gCc6Boot));
    IOLog("StrixS0ix: boot CPU now %s while asleep\n", gCc6Boot ? "CC6" : "MWAITX");
    return kIOReturnSuccess;
}

/*
 * The PM_DISPATCH_VERSION the running kernel accepts, read from pmKextRegister's own check: it starts with
 * cmp edi, imm8 (83 ff ib) or cmp edi, imm32 (81 ff id) within its first bytes (after the frame setup).
 * 0 when no such compare is found: the caller then leaves pmKextRegister alone.
 */
static uint32_t kernelPMDispatchVersion()
{
    const uint8_t *p = reinterpret_cast<const uint8_t *>(&pmKextRegister);
    for (int i = 0; i < 48; i++) {
        if (p[i] == 0x83 && p[i + 1] == 0xff)
            return p[i + 2];
        if (p[i] == 0x81 && p[i + 1] == 0xff)
            return uint32_t(p[i + 2]) | uint32_t(p[i + 3]) << 8 | uint32_t(p[i + 4]) << 16 | uint32_t(p[i + 5]) << 24;
        if (p[i] == 0xc3 || p[i] == 0xe8)      // ret or a call before any compare: not the layout we know
            return 0;
    }
    return 0;
}

bool StrixS0ix::installHalt()
{
    if (version_major != 25) { IOLog("StrixS0ix: Darwin %d, built for 25: no halt hook\n", version_major); return false; }
    // pmKextRegister panics on a version mismatch, and a 26.x point release may bump PM_DISPATCH_VERSION: read the
    // version this kernel checks (its first "cmp edi, imm") and register only if it is the layout we were built for
    {
        uint32_t want = kernelPMDispatchVersion();
        setProperty("S0ix,PMDispatchVersion", want, 32);
        if (want != kPMDispatchVersion) {
            IOLog("StrixS0ix: kernel PM dispatch version %#x, built for %#x: no halt hook\n", want, kPMDispatchVersion);
            return false;
        }
    }
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
    if (!PE_parse_boot_argn("-s0ixidleoff", nullptr, 0)) {
        UInt32 v = 0;
        PE_parse_boot_argn("s0ix_idle", &v, sizeof v);
        gIdleMode = v > 2 ? 2 : v;
        idleThresholds();
        gDispatch[kDispMachineIdle] = reinterpret_cast<void *>(&s0ixMachineIdle);
    }
    setProperty("S0ix,IdleHook", gDispatch[kDispMachineIdle] != nullptr);
    setProperty("S0ix,IdleMode", gIdleMode, 32);
    setProperty("S0ix,IdleC2us", gIdleC2us, 32);
    setProperty("S0ix,IdleC3us", gIdleC3us, 32);
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
    if (gDsmSkip & (1u << fn)) { IOLog("StrixS0ix: PEP _DSM fn %u skipped (S0ix,DsmSkip)\n", unsigned(fn)); return kIOReturnSuccess; }
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
    setupEcWake();
    setupGpio();
    setupCc6();
    {
        UInt32 v = 1;
        PE_parse_boot_argn("s0ix_halthint", &v, sizeof v);
        gHaltHint = v != 0;
        v = 0;
        PE_parse_boot_argn("s0ix_d3", &v, sizeof v);
        gD3Mode = v > 5 ? 5 : v;
        setProperty("S0ix,HaltHint", bool(gHaltHint));
        setProperty("S0ix,D3Mode", gD3Mode, 32);
    }
    pmcOn = setupPmc();
    setProperty("S0ix,Pmc", pmcOn);

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
    IOLog("StrixS0ix: 0.1.13 up, PEP _DSM mask %#x (%s), halt hook %s, power child %s\n", mask, useDsm ? "used" : "off",
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
        buildPci();
        logLinks(this);
        pmcSleep();
        gArmed = halt;
        slept = true;
        IOLog("StrixS0ix: sleep #%u, _DSM 3/7/5 %x/%x/%x, idle %s\n", unsigned(sleeps), a, b, c, halt ? "armed" : "NOT armed");
        return kIOPMAckImplied;
    }
    if (!slept) return kIOPMAckImplied;           // the first state 1 at registration
    slept = false;
    gArmed = false;
    gWakeAbs = mach_absolute_time();
    pmcWake();
    publishPci();
    IOReturn a = kIOReturnSuccess, b = kIOReturnSuccess, c = kIOReturnSuccess;
    if (useDsm) { a = dsm(6); b = dsm(8); c = dsm(4); }
    uint64_t ms = gTscHz ? gLastIdleTsc * 1000 / gTscHz : 0;
    setProperty("S0ix,Sleeps", sleeps, 32);
    setProperty("S0ix,IdleEntries", gIdleEntries, 64);
    setProperty("S0ix,LastWakeEvent", gLastWhy, 32);
    setProperty("S0ix,LastIdleMs", ms, 64);
    setProperty("S0ix,LastLoops", gLastLoops, 32);
    setProperty("S0ix,LastCC6Loops", gLastCc6Loops, 32);
    setProperty("S0ix,EcEnAtHalt", gEcEnAtHalt, 32);
    {
        char seen[240] = ""; size_t at = 0;
        for (unsigned i = 0; i < 16 && at + 24 < sizeof seen; i++)
            if (gSeenPm1 & (1u << i)) at += (size_t)snprintf(seen + at, sizeof seen - at, " PM1.%u@%ums", i, gSeenPm1Ms[i]);
        for (unsigned i = 0; i < 32 && at + 24 < sizeof seen; i++)
            if (gSeenGpe & (1u << i)) at += (size_t)snprintf(seen + at, sizeof seen - at, " GPE%#x@%ums", i, gSeenGpeMs[i]);
        setProperty("S0ix,SeenGpe0Sts", gSeenGpe, 32);
        setProperty("S0ix,SeenPm1Sts", gSeenPm1, 32);
        IOLog("StrixS0ix: status bits raised while halted:%s\n", at ? seen : " none");
    }
    if (gGpio && gGpioMode) {
        setProperty("S0ix,GpioPin0AtHalt", gPin0AtHalt, 32);
        setProperty("S0ix,GpioPin0AtWake", gPin0AtWake, 32);
        IOLog("StrixS0ix: GPIO pin 0 at halt %#x, at wake %#x, status first seen at %u ms (0 = never), level toggles %u\n",
              gPin0AtHalt, gPin0AtWake, gPin0IntMs ? gPin0IntMs - 1 : 0, gPin0Toggles);
        for (unsigned i = 0; i < 7; i++)
            IOLog("StrixS0ix: _AEI pin %#x halt %#x wake %#x, changes %u, first at %u ms\n", kAeiPins[i], gAeiHalt[i],
                  gAeiWake[i], gAeiToggles[i], gAeiFirstMs[i] ? gAeiFirstMs[i] - 1 : 0);
        if (gLastWhy == 0x20000u && evtCall) {
            uint64_t dl;
            clock_interval_to_deadline(300, kMillisecondScale, &dl);
            thread_call_enter_delayed(evtCall, dl);
        }
    }
    if (gEcQuery != -1) IOLog("StrixS0ix: EC status %#x at the wake, query %d%s\n", unsigned(gEcSt), gEcQuery,
                              gEcQuery == -2 ? " (no SCI_EVT)" : gEcQuery == -3 ? " (EC timeout)" : "");
    setProperty("S0ix,LastEcQuery", uint32_t(gEcQuery & 0xffff), 32);
    if (gEcQuery >= 0 && qCall) {
        uint64_t dl;
        clock_interval_to_deadline(500, kMillisecondScale, &dl);
        thread_call_enter_delayed(qCall, dl);
    }
    IOLog("StrixS0ix: wake #%u, idle entries %llu, last idle %llu ms, wake event %#x (%s), loops %u fast %u cc6 %u, "
          "GPE0_EN at halt %#x, _DSM 6/8/4 %x/%x/%x\n", unsigned(sleeps), gIdleEntries, ms, gLastWhy,
          gLastWhy == 0x400 ? "RTC" : gLastWhy == 0x100 ? "power button" : gLastWhy == 0x20000u ? "GPIO 0: lid/power button" : gLastWhy == (0x10000u | gEcGpe) ? "EC: lid/button/other" :
          gLastWhy & 0x10000 ? "GPE" : gLastWhy == 0x40000000 ? "time limit" : gLastWhy == 0x80000000 ? "IRQ storm" : "PM1",
          gLastLoops, gLastFast, gLastCc6Loops, gEcEnAtHalt, a, b, c);
    return kIOPMAckImplied;
}
