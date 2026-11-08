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
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOEventSource.h>
#include <IOKit/IOInterruptEventSource.h>
#include <IOKit/IOFilterInterruptEventSource.h>
#include <IOKit/IODeviceTreeSupport.h>
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

struct Target {
    IOService *ctrl;          // retained
    IOService *prov;          // the IOPCIDevice, not retained (parent of ctrl)
    IOWorkLoop *wl;           // retained
    uint64_t seenNs;
    uint32_t kicks, hits, miss;
    uint32_t devs;            // USB devices under this controller (IOUSB plane), refreshed with each scan
    bool active;
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
        tg[ntg].devs = 1;
        ntg++;
    }
    it->release();
    for (int i = 0; i < ntg; i++)
        if (tg[i].ctrl && !tg[i].ctrl->isInactive()) tg[i].devs = usbDevices(tg[i].ctrl);
}

static void worker(void *)
{
    uint32_t period = 1000, all = 0, idleDiv = 16;
    PE_parse_boot_argn("itlkick", &period, sizeof(period));
    PE_parse_boot_argn("itlkickall", &all, sizeof(all));
    PE_parse_boot_argn("itlkickidle", &idleDiv, sizeof(idleDiv));   // empty controllers: kick every idleDiv periods (1 = always)
    if (!idleDiv) idleDiv = 1;
    uint32_t tick = 0;
    if (!period) { IOLog("ItlXhciKick: itlkick=0, off\n"); return; }
    if (period < 200) period = 200;

    uint64_t t0 = nowNs(), lastScan = 0, lastLog = 0;
    for (;;) {
        uint64_t now = nowNs();
        if (now - lastScan > 3000000000ull) { scan(all != 0); lastScan = now; }
        uint32_t total = 0;
        for (int i = 0; i < ntg; i++) {
            Target &t = tg[i];
            if (!t.ctrl) continue;
            if (t.ctrl->isInactive()) {
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
            if (!t.devs && (tick % idleDiv) != 0) continue;
            KickCtx c = { t.wl, t.prov, 0 };
            t.wl->runAction(kickAction, nullptr, &c);
            t.kicks++;
            if (c.hit) t.hits += c.hit; else t.miss++;
            total += c.hit;
        }
        if (now - lastLog > (now - t0 < 120000000000ull ? 10000000000ull : 60000000000ull)) {
            lastLog = now;
            char b[200];
            int n = snprintf(b, sizeof(b), "kick up=%us p=%uus", (unsigned)((now - t0) / 1000000000ull), period);
            for (int i = 0; i < ntg && n < (int)sizeof(b) - 40; i++)
                n += snprintf(b + n, sizeof(b) - (size_t)n, " c%d:%u/%u/%u/d%u", i, tg[i].kicks, tg[i].hits, tg[i].miss, tg[i].devs);
            nvramSet("itlz0", b);
        }
        (void)total;
        tick++;
        if (period >= 1000) IOSleep(period / 1000);
        else IODelay(period);
    }
}

bool ItlXhciKick::start(IOService *provider)
{
    if (!super::start(provider)) return false;
    startThread(worker, nullptr);
    return true;
}
