// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Portions derived from the Linux mt76 driver, Copyright (C) 2020, 2023 MediaTek Inc. (BSD-3-Clause-Clear)
// itlmt7925 - PCI probe: map BAR0, take driver ownership from the firmware, read the chip id, then (boot-arg itlmt_m1)
// start the firmware / scan / connect worker implemented in itlmt7925_m1.cpp, _m2.cpp and _m3.cpp.
#include "itlmt7925.hpp"
#include "mt7925_regs.h"

#include <string.h>
#include <pexpert/pexpert.h>

// IOCreateThread() is deprecated: a detached kernel thread through the KPI does the same.
static void startThread(void (*fn)(void *), void *arg)
{
    thread_t th = nullptr;
    if (kernel_thread_start((thread_continue_t)fn, arg, &th) == KERN_SUCCESS) thread_deallocate(th);
}

#define super IOService
OSDefineMetaClassAndStructors(itlmt7925, IOService)

uint32_t itlmt7925::rd(uint32_t off)
{
    if (!regs || off + 4 > barSize) return 0xffffffffu;
    return *(volatile uint32_t *)(regs + off);   // x86 is little endian
}

void itlmt7925::wr(uint32_t off, uint32_t val)
{
    if (!regs || off + 4 > barSize) return;
    *(volatile uint32_t *)(regs + off) = val;
}

// Only the addresses M0 needs. The full table is in mt7925/pci.c (__mt7925_reg_addr).
uint32_t itlmt7925::rdMapped(uint32_t addr)
{
    if (addr < MT_BAR0_DIRECT_LIMIT)
        return rd(addr);

    // {0x7c060000, 0x0e0000, 0x10000}: CONN_INFRA host CSR (LPCTL lives here)
    if (addr >= 0x7c060000u && addr < 0x7c070000u)
        return rd(0x0e0000u + (addr - 0x7c060000u));

    // 0x70000000..0x78000000 is reached through the L1 remap window
    if (addr >= 0x70000000u && addr < 0x78000000u) {
        uint32_t base = addr >> 16;
        uint32_t off = addr & 0xffffu;
        uint32_t cur = rd(MT_HIF_REMAP_L1);
        wr(MT_HIF_REMAP_L1, (cur & ~MT_HIF_REMAP_L1_MASK) | (base << 16));
        (void)rd(MT_HIF_REMAP_L1);          // read back to push the write
        uint32_t v = rd(MT_HIF_REMAP_BASE_L1 + off);
        wr(MT_HIF_REMAP_L1, cur);           // restore
        return v;
    }
    return 0xffffffffu;
}

bool itlmt7925::driverOwn()
{
    // Matches __mt792xe_mcu_drv_pmctrl: write CLR_OWN, poll OWN_SYNC == 0
    const uint32_t lpctl = 0x0e0000u + (MT_CONN_ON_LPCTL - 0x7c060000u);
    for (int retry = 0; retry < 10; retry++) {
        wr(lpctl, PCIE_LPCR_HOST_CLR_OWN);
        for (int ms = 0; ms < 50; ms++) {
            if (!(rd(lpctl) & PCIE_LPCR_HOST_OWN_SYNC))
                return true;
            IODelay(1000);
        }
    }
    return false;
}

// Append a short message to the log buffer, print it, and mirror it to NVRAM variable
// 7C436110-AB2A-4BBB-A880-FE41995C9F82:itlmt7925-log (no keyboard/terminal needed to read it).
void itlmt7925::note(const char *fmt, uint32_t a, uint32_t b, uint32_t c)
{
    char tmp[80];
    snprintf(tmp, sizeof(tmp), fmt, a, b, c);
    IOLog("itlmt7925: %s\n", tmp);
    size_t n = strlen(tmp);
    if (loglen + n + 2 < sizeof(logbuf)) {
        memcpy(logbuf + loglen, tmp, n);
        loglen += n;
        logbuf[loglen++] = ';';
        logbuf[loglen] = 0;
    }
    setProperty("m0-log", logbuf);   // visible to ItlDiag / ioreg
    nvramLog(logbuf);
}

// Same recipe as ItlDiag: the value must be OSData, and the sync has to be forced or it never reaches the firmware variable store
// (string properties were silently dropped: itlmt7925-log never showed up in Windows).
// NVRAM logging is for bring-up without a working macOS (read from Windows/Linux after a hang). Each write forces a flash
// update through the firmware, so it is off unless the boot-arg itlmt_nvlog=1 is set; the same text is always in the registry
// (ioreg -rc itlmt7925: m0-log .. m3-log, stat-log, ba-log).
static int gNvlog = -1;
static bool nvlogOn()
{
    if (gNvlog < 0) { uint32_t v = 0; gNvlog = (PE_parse_boot_argn("itlmt_nvlog", &v, sizeof(v)) && v) ? 1 : 0; }
    return gNvlog == 1;
}
static void nvramSet(IORegistryEntry *opt, const char *name, const char *s, size_t n)
{
    if (!nvlogOn()) return;
    OSData *d = OSData::withBytes(s, (unsigned)n);
    if (d) { opt->setProperty(name, d); d->release(); }
    opt->setProperty("IONVRAM-FORCESYNCNOW-PROPERTY", name);
}

void itlmt7925::nvramLog(const char *msg)
{
    IORegistryEntry *opt = IORegistryEntry::fromPath("/options", gIODTPlane);
    if (!opt) { IOLog("itlmt7925: no /options node\n"); return; }
    nvramSet(opt, "itlmt7925-log", msg, strlen(msg));
    opt->release();
}

// Whole m3 log in 380 byte pieces (itlk0..itlk4), written only when a piece changed. Lets the log reach Windows even when
// ItlDiag is disabled (it is the thing under suspicion for the input lag).
void itlmt7925::nvramChunks(const char *buf)
{
    static char last[8][384];
    IORegistryEntry *opt = IORegistryEntry::fromPath("/options", gIODTPlane);
    if (!opt) return;
    size_t len = strlen(buf);
    for (int c = 0; c < 8 && (size_t)c * 380 < len; c++) {
        char piece[384], name[8];
        size_t from = (size_t)c * 380, n = len - from > 380 ? 380 : len - from;
        memcpy(piece, buf + from, n);
        piece[n] = 0;
        if (strcmp(piece, last[c]) == 0) continue;
        strlcpy(last[c], piece, sizeof(last[c]));
        snprintf(name, sizeof(name), "itlk%d", c);
        nvramSet(opt, name, piece, n);
    }
    opt->release();
}

// Block Ack / fast-mode log (itlb0..itlb2), 380 characters per variable. Separate from itlk* because that log is full by link-up.
void itlmt7925::nvramBa(const char *buf)
{
    static char last[3][384];
    IORegistryEntry *opt = IORegistryEntry::fromPath("/options", gIODTPlane);
    if (!opt) return;
    size_t len = strlen(buf);
    for (int c = 0; c < 3 && (size_t)c * 380 < len; c++) {
        char piece[384], name[8];
        size_t from = (size_t)c * 380, n = len - from > 380 ? 380 : len - from;
        memcpy(piece, buf + from, n);
        piece[n] = 0;
        if (strcmp(piece, last[c]) == 0) continue;
        strlcpy(last[c], piece, sizeof(last[c]));
        snprintf(name, sizeof(name), "itlb%d", c);
        nvramSet(opt, name, piece, n);
    }
    opt->release();
}

// Rolling one-line status of the data path (itls0), overwritten each time.
void itlmt7925::nvramStat(const char *msg)
{
    setProperty("stat-log", msg);    // ItlDiag mirrors it into ITLLOG.BIN; the NVRAM variable below does not always land
    IORegistryEntry *opt = IORegistryEntry::fromPath("/options", gIODTPlane);
    if (!opt) return;
    nvramSet(opt, "itls0", msg, strlen(msg));
    opt->release();
}

void itlmt7925::dumpState()
{
    uint32_t chip = rdMapped(MT_HW_CHIPID);
    uint32_t rev  = rdMapped(MT_HW_REV);
    uint32_t lp   = rd(0x0e0000u + (MT_CONN_ON_LPCTL - 0x7c060000u));
    note("CHIP=%08x REV=%08x LP=%08x", chip, rev, lp);
    IOLog("itlmt7925: ASIC revision: %04x%02x (expect 7925xx)\n", chip & 0xffff, rev & 0xff);
}

// Debug aid: with boot-arg itlmt_hold=<seconds> repeat the log on the verbose console so it can be photographed.
void itlmt7925::holdLog()
{
    uint32_t hold = 0;
    if (PE_parse_boot_argn("itlmt_hold", &hold, sizeof(hold)) && hold) {
        for (uint32_t t = 0; t < hold; t += 3) {
            IOLog("itlmt7925: [t=%us] %s\n", t, logbuf);
            IOSleep(3000);
        }
    }
}

bool itlmt7925::start(IOService *provider)
{
    if (!super::start(provider)) return false;
    uint32_t m1 = 0;
    bool runM1 = false;
    txLock = IOLockAlloc();
    cmdLock = IOLockAlloc();
    nativeLock = IOLockAlloc();
    if (!nativeLock) return false;
    uint32_t nativeDP = 0;
    nativeMode = PE_parse_boot_argn("itlmt_native_dp", &nativeDP, sizeof(nativeDP)) && nativeDP;
    setProperty("wifi-state", "off");                         // until M3 runs (boot-arg itlmt_m3=1)

    pci = OSDynamicCast(IOPCIDevice, provider);
    if (!pci) { IOLog("itlmt7925: provider is not IOPCIDevice\n"); return false; }
    pci->retain();
    if (!pci->open(this)) { IOLog("itlmt7925: open failed\n"); pci->release(); pci = nullptr; return false; }

    uint16_t vid = pci->configRead16(kIOPCIConfigVendorID);
    uint16_t did = pci->configRead16(kIOPCIConfigDeviceID);
    uint16_t cmd = pci->configRead16(kIOPCIConfigCommand);
    note("start %04x:%04x cmd=%04x", vid, did, cmd);

    pci->setMemoryEnable(true);
    pci->setBusMasterEnable(false);   // M0 does no DMA

    bar0 = pci->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress0);
    if (!bar0) { IOLog("itlmt7925: BAR0 map failed\n"); goto fail; }
    regs = (volatile uint8_t *)bar0->getVirtualAddress();
    barSize = (uint32_t)bar0->getLength();
    note("bar0 size=%x", barSize);
    if (barSize < MT_BAR0_DIRECT_LIMIT) { IOLog("itlmt7925: BAR0 too small\n"); goto fail; }

    note("lp0=%08x", rd(0x0e0000u + (MT_CONN_ON_LPCTL - 0x7c060000u)));
    if (!driverOwn())
        note("own FAIL");
    else
        note("own OK");
    dumpState();

    holdLog();

    // M1 only runs when asked for: boot-arg itlmt_m1=<seconds to wait before touching DMA/firmware>
    runM1 = PE_parse_boot_argn("itlmt_m1", &m1, sizeof(m1)) && !m1Started;
    // Native mode: the Wi-Fi interface takes its station address from this service when it matches, and the address the radio
    // uses on air is the firmware's, read by M2. Publishing the service before that would give the interface a different
    // address from the one in the 802.11 headers (DHCP / ARP replies are then addressed to a station the AP never heard of).
    // The worker publishes (publishService) as soon as the address is known, or when M1 / M2 gave up.
    if (nativeMode && runM1) regPending = true;
    else registerService();
    if (runM1) {
        m1Started = true;
        startThread(m1Thread, this);
    }
    return true;

fail:
    holdLog();
    stop(provider);
    return false;
}

// Once only, from the worker thread (or from start() when no worker runs).
void itlmt7925::publishService()
{
    if (__atomic_exchange_n(&regPending, false, __ATOMIC_ACQ_REL)) {
        note(getProperty("itlmt_mac_source") ? "registerService (native: address known)" : "registerService (native: address not read)");
        registerService();
    }
}

void itlmt7925::stop(IOService *provider)
{
    if (bar0) { bar0->release(); bar0 = nullptr; regs = nullptr; }
    if (pci) { pci->close(this); pci->release(); pci = nullptr; }
    super::stop(provider);
}

void itlmt7925::free()
{
    super::free();
}
