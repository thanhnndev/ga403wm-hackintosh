// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AmdCppc: CPU performance control for AMD Zen on macOS, which has no driver for it (no P-state requests, no CPPC).
// Measured on the GA403WM (Ryzen AI 9 HX 370, boost 5.1 GHz), one busy thread, on AC: 1.4-3.3 GHz (tools/cpuclock.c).
//
// At start it only READS, on every CPU: HWCR (boost disable bit), the legacy P-state control/status, the CPPC enable, caps and
// request registers, and APERF/MPERF. The result is the registry property "report" and sysctl debug.amdcppc.report.
// Changes are made only when root writes a sysctl, so they can be tried without a reboot and are gone after one:
//   sysctl debug.amdcppc.pstate=0      request P-state 0 (the boostable one) on every CPU through PStateCtl (legacy path)
//   sysctl debug.amdcppc.boost=1       clear HWCR.CpbDis on every CPU (0 sets it: no boost)
//   sysctl debug.amdcppc.cppc=1        enable CPPC on every CPU (cannot be turned off until reset; what Linux amd-pstate does)
//   sysctl debug.amdcppc.freq           (read) effective clock of every CPU over 200 ms from APERF/MPERF (MPERF counts at the P0
//                                      reference clock while the core is in C0), plus the hardware P-state status register:
//                                      tells a slow core apart from a thread that is not getting the CPU
//   sysctl debug.amdcppc.temp           (read) Tctl from SMN 0x59800 through the host bridge's index/data pair (0x60 / 0x64),
//                                      as Linux k10temp does, and the P-state current limit MSR: is the clock held by heat?
//   sysctl debug.amdcppc.sensors        (read, cheap, for the RogControl app) "tctl=<m°C> pkg_mw=<mW>": Tctl as above and the
//                                      package power from the RAPL energy counter (MSR 0xC001029B, unit from 0xC0010299) averaged
//                                      since the previous read of this sysctl (0 on the first read)
//   sysctl debug.amdcppc.epp=<0..255>  CPPC request on every CPU: max = highest perf, min = lowest non-linear, desired = 0
//                                      (autonomous), EPP = value (0 performance .. 128 balanced .. 255 power save). Only when
//                                      CPPC is enabled.
// Reads are #GP-safe. Writes use wrmsr64 after preflight; a successful read does NOT guarantee a fault-safe write.
// Writes are restricted to Strix Point with CPPC capability and validated fields.
// AmdCppcPolicy provides autonomous EPP policy and sleep/wake restoration outside the kernel.
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <sys/sysctl.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <i386/proc_reg.h>
#include <string.h>

extern "C" {
int rdmsr_carefully(uint32_t msr, uint32_t *lo, uint32_t *hi);
void mp_rendezvous_no_intrs(void (*action)(void *), void *arg);
int cpu_number(void);
}

#define MSR_APERF          0xE8
#define MSR_MPERF          0xE7
#define MSR_HWCR           0xC0010015
#define MSR_PSTATE_CTL     0xC0010062
#define MSR_PSTATE_STAT    0xC0010063
#define MSR_PSTATE_DEF0    0xC0010064
#define MSR_CPPC_CAP1      0xC00102B0
#define MSR_CPPC_ENABLE    0xC00102B1
#define MSR_CPPC_REQ       0xC00102B3
#define MSR_HW_PSTATE_STAT 0xC0010293
#define MSR_PSTATE_CUR_LIM 0xC0010061
#define SMN_THM_TCON_CUR   0x00059800
#define MSR_RAPL_UNIT      0xC0010299
#define MSR_PKG_ENERGY     0xC001029B
#define HWCR_CPB_DIS       (1ull << 25)

static const int kMaxCpu = 64;
struct CpuRegs { bool supported; bool present; bool ok[8]; uint64_t hwcr, pctl, pstat, pdef0, cap1, en, req, aperf, mperf; };
static CpuRegs gRegs[kMaxCpu];
static int gNcpu;
static char gReport[32768];

static bool rd(uint32_t m, uint64_t *v)
{
    uint32_t lo = 0, hi = 0;
    if (rdmsr_carefully(m, &lo, &hi)) return false;
    *v = ((uint64_t)hi << 32) | lo;
    return true;
}

static bool supportedCpu()
{
    uint32_t a = 0, b = 0, c = 0, d = 0;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "=c"(c), "=d"(d));
    if (b != 0x68747541 || d != 0x69746e65 || c != 0x444d4163) return false;
    a = 1;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "=c"(c), "=d"(d));
    unsigned family = ((a >> 8) & 15) + ((a >> 20) & 255);
    unsigned model = ((a >> 4) & 15) | ((a >> 12) & 240);
    if (family != 0x1a || model != 0x24) return false; // Strix Point only
    a = 0x80000008;
    __asm__ volatile("cpuid" : "+a"(a), "=b"(b), "=c"(c), "=d"(d));
    return (b & (1u << 27)) != 0; // AMD CPPC full-MSR support
}

static void readAll(void *)
{
    int c = cpu_number();
    if (c < 0 || c >= kMaxCpu) return;
    CpuRegs &r = gRegs[c];
    r.present = true;
    r.supported = supportedCpu();
    r.ok[0] = rd(MSR_HWCR, &r.hwcr);
    r.ok[1] = rd(MSR_PSTATE_CTL, &r.pctl);
    r.ok[2] = rd(MSR_PSTATE_STAT, &r.pstat);
    r.ok[3] = rd(MSR_PSTATE_DEF0, &r.pdef0);
    r.ok[4] = rd(MSR_CPPC_CAP1, &r.cap1);
    r.ok[5] = rd(MSR_CPPC_ENABLE, &r.en);
    r.ok[6] = rd(MSR_CPPC_REQ, &r.req);
    r.ok[7] = rd(MSR_APERF, &r.aperf) && rd(MSR_MPERF, &r.mperf);
}

// Writes: each action only touches a register this CPU could read (so it exists), and only the documented fields.
struct WriteReq { int what; uint64_t val; };
enum { W_PSTATE = 1, W_BOOST, W_CPPC_EN, W_EPP };
static void writeAll(void *arg)
{
    const WriteReq *w = (const WriteReq *)arg;
    int c = cpu_number();
    if (c < 0 || c >= kMaxCpu) return;
    const CpuRegs &r = gRegs[c];
    switch (w->what) {
    case W_PSTATE:
        if (r.ok[1]) wrmsr64(MSR_PSTATE_CTL, (r.pctl & ~7ull) | (w->val & 7));
        break;
    case W_BOOST:
        if (r.ok[0]) wrmsr64(MSR_HWCR, w->val ? (r.hwcr & ~HWCR_CPB_DIS) : (r.hwcr | HWCR_CPB_DIS));
        break;
    case W_CPPC_EN:
        if (r.ok[5] && !(r.en & 1)) wrmsr64(MSR_CPPC_ENABLE, 1);
        break;
    case W_EPP:
        if (r.ok[4] && r.ok[5] && r.ok[6] && (r.en & 1)) {
            uint64_t highest = (r.cap1 >> 24) & 0xff, lownl = (r.cap1 >> 8) & 0xff;
            uint64_t req = (r.req & ~0xffffffffull) | highest | (lownl << 8) | (0ull << 16) | ((w->val & 0xff) << 24);
            wrmsr64(MSR_CPPC_REQ, req);
        }
        break;
    }
}

static void buildReport()
{
    // one line per distinct register set, so 24 identical CPUs give one line
    size_t n = 0;
    gReport[0] = 0;
    bool done[kMaxCpu] = {};
    for (int c = 0; c < gNcpu && n + 200 < sizeof(gReport); c++) {
        if (done[c] || !gRegs[c].present) continue;
        const CpuRegs &r = gRegs[c];
        int same = 0;
        for (int k = c; k < gNcpu; k++) {
            const CpuRegs &o = gRegs[k];
            if (o.present && o.supported == r.supported && !memcmp(o.ok, r.ok, sizeof(r.ok)) && o.hwcr == r.hwcr && o.pctl == r.pctl && o.pstat == r.pstat && o.pdef0 == r.pdef0 && o.cap1 == r.cap1 && o.en == r.en && o.req == r.req) {
                done[k] = true; same++;
            }
        }
        unsigned mhz0 = r.ok[3] ? (unsigned)(r.pdef0 & 0xfff) * 5 : 0;      // Zen 4/5 PStateDef: CpuFid[11:0] x 5 MHz
        n += (size_t)snprintf(gReport + n, sizeof(gReport) - n,
            "%scpu%d(x%d): CpbDis=%d PStateCtl=%llu PStateStat=%llu P0=%uMHz(def %s) CPPC_EN=%s CAP1=high %llu nom %llu lownl %llu low %llu "
            "REQ=max %llu min %llu des %llu epp %llu",
            n ? " | " : "", c, same, r.ok[0] ? (int)((r.hwcr >> 25) & 1) : -1, r.ok[1] ? r.pctl & 7 : 99ull,
            r.ok[2] ? r.pstat & 7 : 99ull, mhz0, r.ok[3] ? ((r.pdef0 >> 63) ? "on" : "off") : "?",
            r.ok[5] ? ((r.en & 1) ? "1" : "0") : "?",
            (r.cap1 >> 24) & 0xff, (r.cap1 >> 16) & 0xff, (r.cap1 >> 8) & 0xff, r.cap1 & 0xff,
            r.req & 0xff, (r.req >> 8) & 0xff, (r.req >> 16) & 0xff, (r.req >> 24) & 0xff);
    }
}

// effective clock: APERF/MPERF on every CPU, twice, 200 ms apart
struct FreqSample { bool ok; uint64_t a, m, tsc, hw; };
static FreqSample gF0[kMaxCpu], gF1[kMaxCpu];
static FreqSample *gFdst;
static void sampleAll(void *)
{
    int c = cpu_number();
    if (c < 0 || c >= kMaxCpu) return;
    FreqSample &f = gFdst[c];
    f.ok = rd(MSR_APERF, &f.a) && rd(MSR_MPERF, &f.m);
    if (!rd(MSR_HW_PSTATE_STAT, &f.hw)) f.hw = ~0ull;
    f.tsc = rdtsc64();
}
static char gFreq[1536];
static void buildFreq()
{
    gFdst = gF0;
    mp_rendezvous_no_intrs(sampleAll, nullptr);
    IOSleep(200);
    gFdst = gF1;
    mp_rendezvous_no_intrs(sampleAll, nullptr);
    unsigned p0 = gRegs[0].ok[3] ? (unsigned)(gRegs[0].pdef0 & 0xfff) * 5 : 0;
    size_t n = (size_t)snprintf(gFreq, sizeof(gFreq), "P0 %u MHz; cpu: MHz while busy / busy %% / hwstat", p0);
    for (int c = 0; c < gNcpu && n + 48 < sizeof(gFreq); c++) {
        const FreqSample &x = gF0[c], &y = gF1[c];
        if (!x.ok || !y.ok || y.m <= x.m || y.tsc <= x.tsc) { n += (size_t)snprintf(gFreq + n, sizeof(gFreq) - n, " | %d ?", c); continue; }
        uint64_t da = y.a - x.a, dm = y.m - x.m, dt = y.tsc - x.tsc;
        unsigned mhz = (unsigned)(p0 * da / dm), busy = (unsigned)(dm * 100 / dt);
        n += (size_t)snprintf(gFreq + n, sizeof(gFreq) - n, " | %d %u/%u%%/%llx", c, mhz, busy > 100 ? 100 : busy,
                              y.hw == ~0ull ? 0ull : (y.hw & 0xffffffffull));
    }
}

static IOService *gSelf;
static IOLock *gLock;
static void refresh()
{
    mp_rendezvous_no_intrs(readAll, nullptr);
    // Reduce after the rendezvous: concurrent callbacks must not race on gNcpu.
    gNcpu = 0;
    for (int c = 0; c < kMaxCpu; c++) if (gRegs[c].present) gNcpu = c + 1;
    buildReport();
    if (gSelf) gSelf->setProperty("report", gReport);
}

// Read-only cache-type audit: the AMD boot PAT patch can override XNU's WC slot.
struct CacheRegs { bool ok; uint64_t pat, mtrrDef; };
static CacheRegs gCache[kMaxCpu];
static void sampleCache(void *)
{
    int c = cpu_number();
    if (c < 0 || c >= kMaxCpu) return;
    gCache[c].ok = rd(0x277, &gCache[c].pat) && rd(0x2ff, &gCache[c].mtrrDef);
}
static int cache_sysctl SYSCTL_HANDLER_ARGS
{
    IOLockLock(gLock);
    mp_rendezvous_no_intrs(sampleCache, nullptr);
    static char report[8192]; size_t n = 0;
    for (int c = 0; c < gNcpu && n + 128 < sizeof(report); c++) {
        if (!gRegs[c].present) continue;
        const CacheRegs &r = gCache[c];
        n += (size_t)snprintf(report + n, sizeof(report) - n,
            "%scpu%d PAT=%016llx PA6=%llu MTRRdef=%llx valid=%d",
            n ? " | " : "", c, r.pat, (r.pat >> 48) & 255, r.mtrrDef, r.ok);
    }
    report[n] = 0;
    int e = SYSCTL_OUT(req, report, n + 1);
    IOLockUnlock(gLock);
    return e;
}

static int report_sysctl SYSCTL_HANDLER_ARGS
{
    if (gLock) IOLockLock(gLock);
    refresh();
    int e = SYSCTL_OUT(req, gReport, strlen(gReport) + 1);
    if (gLock) IOLockUnlock(gLock);
    return e;
}
// SMN register through the root complex (bus 0, device 0, function 0): index at 0x60, data at 0x64 (Linux amd_smn_read)
static IOPCIDevice *gRoot;
static bool smnRead(uint32_t addr, uint32_t *val)
{
    if (!gRoot) {
        OSDictionary *m = IOService::serviceMatching("IOPCIDevice");
        if (m) {
            OSIterator *it = IOService::getMatchingServices(m);
            m->release();
            if (it) {
                while (OSObject *o = it->getNextObject()) {
                    IOPCIDevice *d = OSDynamicCast(IOPCIDevice, o);
                    if (d && d->getBusNumber() == 0 && d->getDeviceNumber() == 0 && d->getFunctionNumber() == 0 &&
                        d->configRead16(kIOPCIConfigVendorID) == 0x1022) {
                        d->retain();
                        gRoot = d;
                        break;
                    }
                }
                it->release();
            }
        }
    }
    if (!gRoot) return false;
    gRoot->configWrite32(0x60, addr);
    *val = gRoot->configRead32(0x64);
    return true;
}
static char gTemp[256];
static void buildTemp()
{
    uint32_t v = 0;
    uint64_t lim = 0;
    bool limOk = rd(MSR_PSTATE_CUR_LIM, &lim);
    if (!smnRead(SMN_THM_TCON_CUR, &v)) {
        snprintf(gTemp, sizeof(gTemp), "no host bridge");
        return;
    }
    int mc = (int)((v >> 21) * 125);                       // millidegrees
    if (v & (1u << 19)) mc -= 49000;                     // range select (k10temp ZEN_CUR_TEMP_RANGE_SEL_MASK)
    snprintf(gTemp, sizeof(gTemp), "Tctl %d.%d C (smn %08x); PStateCurLim %s cur %llu max %llu", mc / 1000, (mc % 1000) / 100, v,
             limOk ? "ok" : "?", limOk ? lim & 7 : 0ull, limOk ? (lim >> 4) & 7 : 0ull);
}
static bool tctlMilli(int *mc)
{
    uint32_t v = 0;
    if (!smnRead(SMN_THM_TCON_CUR, &v)) return false;
    *mc = (int)((v >> 21) * 125);
    if (v & (1u << 19)) *mc -= 49000;
    return true;
}
static uint64_t gLastEnergy, gLastNs, gLastMw;
static char gSensors[128];
static void buildSensors()
{
    int mc = 0;
    bool tOk = tctlMilli(&mc);
    uint64_t unit = 0, e = 0, mw = 0, now = 0;
    bool uOk = rd(MSR_RAPL_UNIT, &unit), eOk = uOk && rd(MSR_PKG_ENERGY, &e);
    if (eOk) {
        absolutetime_to_nanoseconds(mach_absolute_time(), &now);
        e &= 0xffffffffull;
        // sysctl(8) calls the handler twice in a row (size, then data): keep the last value for reads closer than 200 ms
        if (gLastNs && now - gLastNs < 200000000ull) { mw = gLastMw; goto out; }
        if (gLastNs && now > gLastNs) {
            uint64_t de = (e - gLastEnergy) & 0xffffffffull;     // 32-bit counter, wraps
            uint32_t esu = (uint32_t)(unit >> 8) & 0x1f;          // energy unit 1 / 2^esu J
            // mW = de / 2^esu J * 1000 / (dt ns / 1e9)
            mw = ((de * 1000000ull) >> esu) * 1000ull / ((now - gLastNs) / 1000ull ? (now - gLastNs) / 1000ull : 1);
        }
        gLastEnergy = e; gLastNs = now; gLastMw = mw;
    }
out:
    // the raw unit / counter follow, so a counter that never moves (or an MSR that faults) shows up in the string
    snprintf(gSensors, sizeof(gSensors), "tctl=%d pkg_mw=%llu rapl=%s%llx/%llx", tOk ? mc : -1, mw,
             !uOk ? "unit-fault " : !eOk ? "energy-fault " : "", unit, e);
}
static int sensors_sysctl SYSCTL_HANDLER_ARGS
{
    if (gLock) IOLockLock(gLock);
    buildSensors();
    int e = SYSCTL_OUT(req, gSensors, strlen(gSensors) + 1);
    if (gLock) IOLockUnlock(gLock);
    return e;
}
static int temp_sysctl SYSCTL_HANDLER_ARGS
{
    if (gLock) IOLockLock(gLock);
    buildTemp();
    int e = SYSCTL_OUT(req, gTemp, strlen(gTemp) + 1);
    if (gLock) IOLockUnlock(gLock);
    return e;
}

static int freq_sysctl SYSCTL_HANDLER_ARGS
{
    if (gLock) IOLockLock(gLock);
    buildFreq();
    int e = SYSCTL_OUT(req, gFreq, strlen(gFreq) + 1);
    if (gLock) IOLockUnlock(gLock);
    return e;
}
static int write_sysctl SYSCTL_HANDLER_ARGS
{
    int what = (int)arg2, v = -1;
    int e = sysctl_handle_int(oidp, &v, 0, req);
    if (e || !req->newptr) return e;
    if (what == W_PSTATE && v != 0) return EINVAL;
    if (what == W_EPP && (v < 0 || v > 255)) return EINVAL;
    if (what == W_BOOST && v != 0 && v != 1) return EINVAL;
    if (what == W_CPPC_EN && v != 1) return EINVAL;
    if (gLock) IOLockLock(gLock);
    refresh(); // preflight current values on every CPU
    // Preflight all CPUs before any writes; never silently succeed on unsupported/off CPPC.
    for (int c = 0; c < gNcpu; c++) {
        const CpuRegs &r = gRegs[c];
        if (!r.present) continue;
        bool ok = what == W_PSTATE ? r.ok[1] : what == W_BOOST ? r.ok[0] :
                  what == W_CPPC_EN ? r.ok[5] : r.ok[4] && r.ok[5] && r.ok[6] && (r.en & 1);
        if (what == W_EPP || what == W_CPPC_EN) {
            unsigned low = r.cap1 & 255, nl = (r.cap1 >> 8) & 255;
            unsigned nom = (r.cap1 >> 16) & 255, high = (r.cap1 >> 24) & 255;
            ok = ok && r.ok[4] && low && low <= nl && nl <= nom && nom <= high;
        }
        if (what == W_PSTATE) {
            // Only the validated enabled P0 definition is exposed by this driver.
            ok = ok && v == 0 && r.ok[3] && (r.pdef0 >> 63);
        }
        ok = ok && r.supported;
        if (!ok) { if (gLock) IOLockUnlock(gLock); return ENOTSUP; }
    }
    WriteReq w = { what, (uint64_t)v };
    mp_rendezvous_no_intrs(writeAll, &w);
    refresh();
    for (int c = 0; c < gNcpu; c++) {
        const CpuRegs &r = gRegs[c];
        if (!r.present) continue;
        bool applied = what == W_PSTATE ? r.ok[1] && (r.pctl & 7) == (uint64_t)v :
                       what == W_BOOST ? r.ok[0] && !(r.hwcr & HWCR_CPB_DIS) == (bool)v :
                       what == W_CPPC_EN ? r.ok[5] && (r.en & 1) :
                       r.ok[6] && (r.req & 0xff) == ((r.cap1 >> 24) & 0xff) &&
                       ((r.req >> 8) & 0xff) == ((r.cap1 >> 8) & 0xff) &&
                       ((r.req >> 16) & 0xff) == 0 && ((r.req >> 24) & 0xff) == (uint64_t)v;
        if (!applied) e = EIO;
    }
    IOLog("AmdCppc: %s=%d status=%d -> %s\n", oidp->oid_name, v, e, gReport);
    if (gLock) IOLockUnlock(gLock);
    return e;
}

SYSCTL_NODE(_debug, OID_AUTO, amdcppc, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "AmdCppc");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, cache, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, cache_sysctl, "A", "read-only PAT/MTRR cache audit");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, report, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, report_sysctl, "A", "registers");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, freq, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, freq_sysctl, "A", "effective clock");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, temp, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, temp_sysctl, "A", "Tctl");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, sensors, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, sensors_sysctl, "A", "Tctl + package power");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, pstate, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_PSTATE, write_sysctl, "I", "request P-state");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, boost, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_BOOST, write_sysctl, "I", "1 = boost allowed");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, cppc, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_CPPC_EN, write_sysctl, "I", "1 = enable CPPC");
SYSCTL_PROC(_debug_amdcppc, OID_AUTO, epp, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, W_EPP, write_sysctl, "I", "CPPC EPP");

// Wake invalidates the energy/time baseline; defer hardware access to normal readers/policy.
static IONotifier *gPowerNotifier;
static IOReturn powerNotify(void *, void *, UInt32 message, IOService *, void *argument, vm_size_t)
{
    if (message == kIOMessageSystemHasPoweredOn) {
        IOLockLock(gLock);
        gLastEnergy = gLastNs = gLastMw = 0;
        memset(gF0, 0, sizeof(gF0)); memset(gF1, 0, sizeof(gF1));
        IOLockUnlock(gLock);
    }
    if (message == kIOMessageSystemWillSleep || message == kIOMessageCanSystemSleep)
        acknowledgeSleepWakeNotification(argument);
    return kIOReturnSuccess;
}

class AmdCppc : public IOService {
    OSDeclareDefaultStructors(AmdCppc)
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
};
OSDefineMetaClassAndStructors(AmdCppc, IOService)

bool AmdCppc::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    gLock = IOLockAlloc();
    if (!gLock) { IOService::stop(provider); return false; }
    gSelf = this;
    refresh();
    IOLog("AmdCppc: %d CPUs: %s\n", gNcpu, gReport);
    sysctl_register_oid(&sysctl__debug_amdcppc);
    sysctl_register_oid(&sysctl__debug_amdcppc_cache);
    sysctl_register_oid(&sysctl__debug_amdcppc_report);
    sysctl_register_oid(&sysctl__debug_amdcppc_freq);
    sysctl_register_oid(&sysctl__debug_amdcppc_temp);
    sysctl_register_oid(&sysctl__debug_amdcppc_sensors);
    sysctl_register_oid(&sysctl__debug_amdcppc_pstate);
    sysctl_register_oid(&sysctl__debug_amdcppc_boost);
    sysctl_register_oid(&sysctl__debug_amdcppc_cppc);
    sysctl_register_oid(&sysctl__debug_amdcppc_epp);
    gPowerNotifier = registerSleepWakeInterest(powerNotify, this);
    if (!gPowerNotifier) { stop(provider); return false; }
    registerService();
    return true;
}

void AmdCppc::stop(IOService *provider)
{
    if (gPowerNotifier) { gPowerNotifier->remove(); gPowerNotifier = nullptr; }
    sysctl_unregister_oid(&sysctl__debug_amdcppc_epp);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_cppc);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_boost);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_pstate);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_sensors);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_temp);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_freq);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_report);
    sysctl_unregister_oid(&sysctl__debug_amdcppc_cache);
    sysctl_unregister_oid(&sysctl__debug_amdcppc);
    gSelf = nullptr;
    if (gRoot) { gRoot->release(); gRoot = nullptr; }
    if (gLock) { IOLockFree(gLock); gLock = nullptr; }
    IOService::stop(provider);
}
