// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// ItlXhciKick - makes macOS service the secondary xHCI event rings of AMD controllers that only have one MSI vector.
//
// Why (all of it read from the macOS 15 Recovery's AppleUSBXHCI / AppleUSBXHCIPCI and measured with ItlDiag):
//   * AppleUSBXHCI::start always programs 3 interrupters (ring 0: commands / port changes / MFINDEX wrap, ring 1: transfer
//     events of every non-isochronous endpoint, i.e. the USB keyboards and mice, ring 2: isochronous).
//   * AppleUSBXHCIPCI::start creates exactly ONE IOFilterInterruptEventSource, on the first MSI vector of the device. Its
//     filter (filterOccurred) calls the three per-interrupter filters and signals interruptOccurred(), which drains all three
//     rings unconditionally (primaryInterrupt / ioInterrupt / isochronousInterrupt, no IP / EINT test).
//   * The Strix Point xHCIs expose a single MSI / MSI-X vector. Only interrupter 0 ever raises it; events on interrupter 1 sit
//     in the ring until interrupter 0's MFINDEX-wrap event fires, every 2.048 s. Key-up reports arrive ~2 s late, which looks
//     like a stuck / repeating key.
// What this does: every millisecond it signals that same event source (IOFilterInterruptEventSource::signalInterrupt, public
// API) so interruptOccurred() runs and drains ring 1 / 2 through Apple's own code. Nothing in the controller or in the driver
// is written to or patched. The event source is found by walking the controller's work loop chain under the work loop gate,
// so a controller that goes away can not leave a dangling pointer.
//
// boot-arg itlkick=0 disables it, itlkick=<us> sets the period (default 1000), itlkickall=1 also kicks non-AMD controllers,
// itlkickidle=<n> kicks a controller with no USB devices only every n periods (default 16, 1 = every period).
//
// Pending check (itlkickpend, default 1; AMD controllers only, and off when the system has an IOMMU / IOMapper, since
// the ring addresses it reads are bus addresses): before kicking, the worker reads, for interrupters 0, 1 and 2, the
// ERSTSZ, ERSTBA and ERDP registers (BAR0 mapped read only; HCSPARAMS1 and RTSOFF once at setup; nothing else, no
// IMAN or USBSTS) and the cycle bit of the event TRB the ERDP points at (the event ring in host memory, mapped read
// only). The TRB belongs to the consumer when its cycle bit equals the consumer cycle state, which is the cycle bit of
// the TRB just before it (inverted across the ring's wrap). Only then is the work loop signalled. Anything it can not
// decide (BAR reads all-ones, ring not mappable, ERDP outside the ring) counts as pending: the 0.1.x kick every period.
// A forced kick still runs every itlkickidle periods of wall time (not worker ticks, so the backoff does not stretch
// it), so a wrong "nothing pending" can delay an event by at most that long (16 ms by default); the forced kick counts
// such misses (ERDP moved although nothing looked pending), shown as m<n> in itlz0. itlkickpend=0 = old behaviour.
// Known gap: a ring re-initialised at the same address without being zeroed can look empty for one lap; the forced
// kick drains it (one event 16 ms late, then it heals itself).
// Backoff (itlkickslow=<ms>, default 4): after 1 s with nothing pending on any controller the worker sleeps <ms>
// instead of one period, and returns to one period on the first pending event. itlkickslow=1 = always one period.
//
// Reading itlz0 after a boot: c<i>:<kicks>/<hits>/<miss>/d<devs>/s<skips>/u<unknown>/m<missed>. Working as intended:
// on a controller with devices, s grows by most of a thousand per second at rest, u stays 0, m stays near 0. If s
// stays near 0 while kicks grow ~1000/s at rest, the check always reads "pending" (for example Apple writes ERDP as
// the last processed TRB rather than the next one): safe, it is then the 0.1.x behaviour with no saving. u growing
// means the check could not decide (BAR all-ones, ring not mappable), also the 0.1.x behaviour.
// Linux has no equivalent: its xhci driver puts every event on interrupter 0, whose MSI fires.
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOEventSource.h>
#include <IOKit/IOInterruptEventSource.h>
#include <IOKit/IOFilterInterruptEventSource.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IORegistryEntry.h>
#include <libkern/c++/OSData.h>
#include <pexpert/pexpert.h>
#include <kern/clock.h>
#include <mach/mach_time.h>
#include <string.h>
#include <libkern/libkern.h>

// IOCreateThread() is deprecated: a detached kernel thread through the KPI does the same.
static void startThread(void (*fn)(void *), void *arg)
{
    thread_t th = nullptr;
    if (kernel_thread_start((thread_continue_t)fn, arg, &th) == KERN_SUCCESS) thread_deallocate(th);
}

class ItlXhciKick : public IOService {
    OSDeclareDefaultStructors(ItlXhciKick)
public:
    bool start(IOService *provider) override;
};

#define super IOService
OSDefineMetaClassAndStructors(ItlXhciKick, IOService)

// IOWorkLoop::eventChain is protected; reading it through a type derived from IOWorkLoop is the only access needed.
class WLPeek : public IOWorkLoop {
public:
    static IOEventSource *chain(IOWorkLoop *wl) { return static_cast<WLPeek *>(wl)->eventChain; }
};

// IOEventSource::getNext is protected as well.
class ESPeek : public IOEventSource {
public:
    static IOEventSource *next(IOEventSource *s) { return static_cast<ESPeek *>(s)->getNext(); }
};

// One secondary interrupter's event ring, mapped read only.
struct Ring {
    uint64_t erstba;          // ERSTBA the maps were made for (0 = none)
    uint32_t nseg;
    IOMemoryMap *seg[4];
    uint64_t base[4];         // bus address of each segment (= physical: the check is off when an IOMapper exists)
    uint32_t ntrb[4];
};

struct Target {
    IOService *ctrl;          // retained
    IOService *prov;          // the IOPCIDevice, not retained (parent of ctrl)
    IOWorkLoop *wl;           // retained
    uint64_t seenNs;
    uint32_t kicks, hits, miss;
    uint32_t devs;            // USB devices under this controller (IOUSB plane), refreshed with each scan
    uint64_t forcedNs;        // time of the last forced kick (the forced interval is wall time)
    bool active;
    IOMemoryMap *bar;         // BAR0, read only use (nullptr: pending check off for this controller)
    uint32_t rt;              // runtime register offset (RTSOFF)
    Ring ring[3];             // interrupters 0, 1 and 2
    uint32_t skips, unknown, missed;   // kicks skipped (nothing pending), checks that could not decide, events a forced kick found
    uint64_t fdp[2];          // ERDPs at the last forced kick that followed "nothing pending"
    bool fchk;                // compare fdp on the next pass (the work loop drains after the kick, not during it)
};
static Target tg[8];
static int ntg;

static uint64_t nowNs()
{
    uint64_t t = mach_absolute_time(), ns;
    absolutetime_to_nanoseconds(t, &ns);
    return ns;
}

static void nvramSet(const char *name, const char *s)
{
    IORegistryEntry *o = IORegistryEntry::fromPath("/options", gIODTPlane);
    if (!o) return;
    OSData *d = OSData::withBytes(s, (unsigned)strlen(s));
    if (d) { o->setProperty(name, d); d->release(); }
    o->setProperty("IONVRAM-FORCESYNCNOW-PROPERTY", name);
    o->release();
}

static inline uint32_t rd32(volatile const uint8_t *p) { return *(volatile const uint32_t *)p; }
static inline uint64_t rd64(volatile const uint8_t *p) { return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32); }

static IOMemoryMap *mapPhys(uint64_t pa, uint64_t len)
{
    IOMemoryDescriptor *md = IOMemoryDescriptor::withAddressRange(pa, len, kIODirectionIn | kIOMemoryTypePhysical64, TASK_NULL);
    if (!md) return nullptr;
    IOMemoryMap *m = md->map(kIOMapReadOnly);
    md->release();
    return m;
}

static void ringFree(Ring &r)
{
    for (uint32_t i = 0; i < 4; i++) if (r.seg[i]) r.seg[i]->release();
    memset(&r, 0, sizeof(r));
}

static void targetFree(Target &t)
{
    for (int i = 0; i < 3; i++) ringFree(t.ring[i]);
    if (t.bar) t.bar->release();
    t.bar = nullptr;
}

// Maps the event ring segments listed in the ERST at erstba (n entries). False if anything looks wrong.
static bool ringMap(Ring &r, uint64_t erstba, uint32_t n)
{
    ringFree(r);
    if (n == 0 || n > 4) return false;
    IOMemoryMap *em = mapPhys(erstba, n * 16u);
    if (!em) return false;
    volatile const uint8_t *e = (volatile const uint8_t *)em->getVirtualAddress();
    bool ok = true;
    for (uint32_t i = 0; i < n && ok; i++) {
        uint64_t b = rd64(e + 16 * i) & ~0x3full;
        uint32_t sz = rd32(e + 16 * i + 8) & 0xffffu;
        if (!b || sz < 16 || sz > 4096) { ok = false; break; }
        r.base[i] = b; r.ntrb[i] = sz;
        r.seg[i] = mapPhys(b, (uint64_t)sz * 16u);
        if (!r.seg[i]) ok = false;
    }
    em->release();
    if (!ok) { ringFree(r); return false; }
    r.erstba = erstba; r.nseg = n;
    return true;
}

static inline uint32_t trbCycle(const Ring &r, uint32_t s, uint32_t i)
{
    return rd32((volatile const uint8_t *)r.seg[s]->getVirtualAddress() + 16u * i + 12) & 1u;
}

// 1 = an event waits on interrupter n (0, 1 or 2), 0 = none, -1 = can not tell (the caller kicks).
static int ringPending(Target &t, int n)
{
    volatile const uint8_t *ir = (volatile const uint8_t *)t.bar->getVirtualAddress() + t.rt + 0x20 + 32 * n;
    uint32_t szr = rd32(ir + 8);
    if (szr == 0xffffffffu) return -1;              // the controller does not answer (D3, surprise removal)
    uint32_t sz = szr & 0xffffu;
    uint64_t ba = rd64(ir + 0x10) & ~0x3full;
    uint64_t dp = rd64(ir + 0x18) & ~0xfull;
    if (!sz || !ba) return -1;                      // not set up (yet, or being reset): can not tell, kick as before
    Ring &r = t.ring[n];
    if ((r.erstba != ba || r.nseg != sz) && !ringMap(r, ba, sz)) return -1;
    for (uint32_t s = 0; s < r.nseg; s++) {
        if (dp < r.base[s] || dp >= r.base[s] + 16ull * r.ntrb[s]) continue;
        uint32_t i = (uint32_t)((dp - r.base[s]) / 16), ccs;
        if (i) ccs = trbCycle(r, s, i - 1);
        else if (s) ccs = trbCycle(r, s - 1, r.ntrb[s - 1] - 1);
        else ccs = trbCycle(r, r.nseg - 1, r.ntrb[r.nseg - 1] - 1) ^ 1u;   // dequeue at the ring start: the TRB before it is from the last lap
        return trbCycle(r, s, i) == ccs;
    }
    return -1;                                      // ERDP outside the mapped ring (ring was reallocated): remap next time
}

// Pending on interrupter 0, 1 or 2: 1 yes, 0 no, -1 unknown. Also returns the ERDPs of 1 and 2 (to spot what a forced
// kick drained). Ring 0 has a working MSI; it is checked only as cheap insurance (an event there is normally drained by
// the interrupt before we look).
static int pending(Target &t, uint64_t *dp)
{
    if (!t.bar) return -1;
    volatile const uint8_t *rt = (volatile const uint8_t *)t.bar->getVirtualAddress() + t.rt;
    dp[0] = rd64(rt + 0x20 + 32 + 0x18) & ~0xfull;
    dp[1] = rd64(rt + 0x20 + 64 + 0x18) & ~0xfull;
    int unknown = 0;
    for (int n = 1; n <= 3; n++) {
        const int i = n % 3;                        // 1, 2, then 0
        const int r = ringPending(t, i);
        if (r == 1) return 1;
        if (r < 0) { t.ring[i].erstba = 0; unknown = 1; }
    }
    return unknown ? -1 : 0;
}

// BAR0 of the controller for the pending check. Read only: nothing in the controller is ever written.
static void barSetup(Target &t)
{
    if (!t.prov) return;
    IOMemoryMap *m = t.prov->mapDeviceMemoryWithIndex(0, kIOMapReadOnly);   // the IOPCIDevice's BAR0 (IOService API, no IOPCIFamily link)
    if (!m) return;
    volatile const uint8_t *b = (volatile const uint8_t *)m->getVirtualAddress();
    const uint32_t cap = rd32(b), hcs1 = rd32(b + 4), rts = rd32(b + 0x18);
    // A controller already in D3 reads all-ones: RTSOFF would be 0xffffffe0, past the BAR. Reject it, and check the bound
    // in 64 bits so no register value can wrap it.
    if (cap == 0xffffffffu || hcs1 == 0xffffffffu || rts == 0xffffffffu) { m->release(); return; }
    uint32_t maxIntrs = (hcs1 >> 8) & 0x7ffu, rtsoff = rts & ~0x1fu;
    if (maxIntrs < 3 || !rtsoff || (uint64_t)rtsoff + 0x20 + 3 * 32 > m->getLength()) { m->release(); return; }
    t.bar = m; t.rt = rtsoff;
}

struct KickCtx { IOWorkLoop *wl; IOService *prov; uint32_t hit; };

// Runs with the controller's work loop gate held: the event source chain can not change under us.
static IOReturn kickAction(OSObject *, void *a0, void *, void *, void *)
{
    KickCtx *c = (KickCtx *)a0;
    for (IOEventSource *s = WLPeek::chain(c->wl); s; s = ESPeek::next(s)) {
        IOFilterInterruptEventSource *f = OSDynamicCast(IOFilterInterruptEventSource, s);
        if (f && f->getProvider() == c->prov) { f->signalInterrupt(); c->hit++; }
    }
    return kIOReturnSuccess;
}

static bool wantController(IOService *prov, bool all)
{
    if (all) return true;
    OSData *v = prov ? OSDynamicCast(OSData, prov->getProperty("vendor-id")) : nullptr;
    if (!v || v->getLength() < 2) return false;
    uint16_t vid;
    memcpy(&vid, v->getBytesNoCopy(), 2);
    return vid == 0x1022;
}

// Number of devices attached to a controller. A controller with none only needs the slow kick: a hot-plug arrives as a
// port-status change on interrupter 0, whose MSI does fire, and the slow kick then covers enumeration on ring 1.
static uint32_t usbDevices(IOService *ctrl)
{
    const IORegistryPlane *pl = IORegistryEntry::getPlane("IOUSB");
    if (!pl) return 1;                       // no IOUSB plane: be safe, treat as busy
    OSIterator *it = ctrl->getChildIterator(pl);
    if (!it) return 1;
    uint32_t n = 0;
    while (it->getNextObject()) n++;
    it->release();
    return n;
}

static uint32_t pendOn = 1;

// The pending check reads event rings at the bus addresses the controller holds, which are physical addresses only
// without an IOMMU. AMD has no macOS IOMMU driver, but if any IOMapper is registered, stay with the plain kick.
static bool iommuPresent()
{
    OSDictionary *m = IOService::serviceMatching("IOMapper");
    if (!m) return true;
    IOService *s = IOService::copyMatchingService(m);
    m->release();
    if (!s) return false;
    s->release();
    return true;
}

static void scan(bool all)
{
    OSDictionary *m = IOService::serviceMatching("AppleUSBXHCIPCI");
    if (!m) return;
    OSIterator *it = IOService::getMatchingServices(m);
    m->release();
    if (!it) return;
    while (OSObject *o = it->getNextObject()) {
        IOService *c = OSDynamicCast(IOService, o);
        if (!c || c->isInactive()) continue;
        bool known = false;
        for (int i = 0; i < ntg; i++) if (tg[i].ctrl == c) known = true;
        if (known || ntg >= 8) continue;
        IOService *prov = c->getProvider();
        if (!wantController(prov, all)) continue;
        IOWorkLoop *wl = c->getWorkLoop();
        if (!wl) continue;
        c->retain();
        wl->retain();
        tg[ntg].ctrl = c; tg[ntg].prov = prov; tg[ntg].wl = wl;
        tg[ntg].seenNs = nowNs(); tg[ntg].active = false;
        tg[ntg].kicks = tg[ntg].hits = tg[ntg].miss = 0;
        tg[ntg].devs = 1; tg[ntg].forcedNs = 0;
        tg[ntg].bar = nullptr; tg[ntg].skips = tg[ntg].unknown = tg[ntg].missed = 0; tg[ntg].fchk = false;
        memset(tg[ntg].ring, 0, sizeof(tg[ntg].ring));
        if (pendOn && wantController(prov, false) && !iommuPresent()) barSetup(tg[ntg]);
        ntg++;
    }
    it->release();
    for (int i = 0; i < ntg; i++)
        if (tg[i].ctrl && !tg[i].ctrl->isInactive()) tg[i].devs = usbDevices(tg[i].ctrl);
}

static void worker(void *arg)
{
    IOService *self = (IOService *)arg;
    uint32_t period = 1000, all = 0, idleDiv = 16;
    PE_parse_boot_argn("itlkick", &period, sizeof(period));
    PE_parse_boot_argn("itlkickall", &all, sizeof(all));
    PE_parse_boot_argn("itlkickidle", &idleDiv, sizeof(idleDiv));   // empty controllers: kick every idleDiv periods (1 = always)
    if (!idleDiv) idleDiv = 1;
    uint32_t slowMs = 4;
    PE_parse_boot_argn("itlkickpend", &pendOn, sizeof(pendOn));
    PE_parse_boot_argn("itlkickslow", &slowMs, sizeof(slowMs));
    if (!slowMs) slowMs = 1;
    uint64_t lastPend = 0;
    if (!period) { IOLog("ItlXhciKick: itlkick=0, off\n"); return; }
    if (period < 200) period = 200;
    const uint64_t forcedNs = (uint64_t)idleDiv * period * 1000ull;

    uint64_t t0 = nowNs(), lastScan = 0, lastLog = 0;
    char lastHealth[160] = "";
    for (;;) {
        uint64_t now = nowNs();
        if (now - lastScan > 3000000000ull) { scan(all != 0); lastScan = now; }
        uint32_t total = 0;
        for (int i = 0; i < ntg; i++) {
            Target &t = tg[i];
            if (!t.ctrl) continue;
            if (t.ctrl->isInactive()) {
                targetFree(t);
                t.wl->release();
                t.ctrl->release();
                t.ctrl = nullptr; t.wl = nullptr;
                continue;
            }
            // the controller was registered after its start() finished; give it a few more seconds before the first kick
            if (!t.active) {
                if (now - t.seenNs < 3000000000ull) continue;
                t.active = true;
            }
            // Every kick wakes the controller's work loop thread (one IPI each); an empty controller has no ring-1 traffic to drain.
            // Forced kick: idleDiv periods of wall time since the last kick, so the backoff does not stretch it (a device
            // plugged into an empty controller enumerates through ring 1 at that pace).
            bool forced = now - t.forcedNs >= forcedNs;
            uint64_t dp[2] = { 0, 0 };
            // Only controllers with USB devices are read: an empty one may be powered down (runtime D3), and its BAR is not
            // touched at all; it keeps the 0.1.x behaviour (a kick every itlkickidle periods).
            int p = (pendOn && t.bar && t.devs) ? pending(t, dp) : -1;
            if (t.fchk && p >= 0) {                                       // the last forced kick drained events we had not seen (upper bound:
                t.fchk = false;                                           // an event that arrived after that check counts too)
                if (dp[0] != t.fdp[0] || dp[1] != t.fdp[1]) { t.missed++; lastPend = now; }
            }
            if (p == 1) lastPend = now;
            if (p < 0 && t.bar && t.devs) t.unknown++;
            if (p < 0 && t.devs) lastPend = now;                          // can not tell: no backoff, the 0.1.x kick every period
            if (p == 0 && !forced) { t.skips++; continue; }              // nothing queued on ring 0/1/2: no work loop wakeup
            if (p < 0 && !t.devs && !forced) continue;                    // old behaviour for an empty controller
            KickCtx c = { t.wl, t.prov, 0 };
            t.wl->runAction(kickAction, nullptr, &c);
            t.forcedNs = now;                                             // any kick drains everything: restart the forced interval
            if (p == 0) { t.fdp[0] = dp[0]; t.fdp[1] = dp[1]; t.fchk = true; }   // forced kick after "nothing pending": check next pass
            t.kicks++;
            if (c.hit) t.hits += c.hit; else t.miss++;
            total += c.hit;
        }
        if (now - lastLog > (now - t0 < 120000000000ull ? 10000000000ull : 60000000000ull)) {
            lastLog = now;
            char b[320];
            int n = snprintf(b, sizeof(b), "kick up=%us p=%uus", (unsigned)((now - t0) / 1000000000ull), period);
            for (int i = 0; i < ntg && n < (int)sizeof(b) - 40; i++)
                n += snprintf(b + n, sizeof(b) - (size_t)n, " c%d:%u/%u/%u/d%u/s%u/u%u/m%u", i, tg[i].kicks, tg[i].hits, tg[i].miss,
                              tg[i].devs, tg[i].skips, tg[i].unknown, tg[i].missed);
            // Full counters go to the registry every time (free). NVRAM is flash: during the first two minutes it gets
            // the full line every 10 s as before (it survives a panic in early boot); after that only when the health
            // line changes (a controller gained/lost its event source, started missing, or gained/lost devices).
            if (self) {
                OSString *str = OSString::withCString(b);
                if (str) { self->setProperty("itlz0", str); str->release(); }
            }
            if (now - t0 < 120000000000ull) {
                nvramSet("itlz0", b);
            } else {
                char h[160];
                int m = snprintf(h, sizeof(h), "kick p=%uus", period);
                for (int i = 0; i < ntg && m < (int)sizeof(h) - 24; i++)
                    m += snprintf(h + m, sizeof(h) - (size_t)m, " c%d:%s%s/d%u", i, tg[i].hits ? "hit" : "nohit",
                                  tg[i].miss ? "+miss" : "", tg[i].devs ? 1u : 0u);
                if (strcmp(h, lastHealth) != 0) {
                    strlcpy(lastHealth, h, sizeof(lastHealth));
                    snprintf(b, sizeof(b), "%s up=%us", h, (unsigned)((now - t0) / 1000000000ull));
                    nvramSet("itlz0", b);
                }
            }
        }
        (void)total;
        if (pendOn && slowMs > 1 && now - lastPend > 1000000000ull) IOSleep(slowMs);   // quiet for 1 s: back off
        else if (period >= 1000) IOSleep(period / 1000);
        else IODelay(period);
    }
}

bool ItlXhciKick::start(IOService *provider)
{
    if (!super::start(provider)) return false;
    retain();                       // the worker thread never exits and uses this object
    startThread(worker, this);
    return true;
}
