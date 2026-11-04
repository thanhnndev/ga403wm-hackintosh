// SPDX-License-Identifier: BSD-3-Clause-Clear
// NMXBacklight: the brightness slider and keys for the OLED under NMXGPU (amdgpu DC).
// IOGraphics builds an AppleBacklightDisplay (slider, F-keys, dim on sleep) only if, at the framebuffer's first open, a
// service named "backlight" exists and the framebuffer's getAppleSense() says LCD. NMXGPUFB has neither. This kext
// matches the NMXAMDFB framebuffer and:
//   1. publishes an IODisplayParameterHandler named "backlight" under it (same handler as StrixGOP 0.1.6);
//   2. gives that one framebuffer object a private copy of its vtable in which only getAppleSense differs (LCD for
//      connection 0); every other slot is the original;
//   3. applies brightness through amdgpu's own path, from a thread call: xkpi's backlight registry
//      (nmx_backlight_next) -> linux_backlight_update_status (percent) -> amdgpu_dm_backlight_update_status ->
//      dc_link_set_backlight_level_nits (AUX nits on this panel, under DC's lock). No DPCD writes of our own.
// The NMXGPU functions are called by address: the load address comes from the framebuffer's vtable pointer, and every
// function is checked against its known bytes first. Any mismatch (another NMXGPU build) leaves everything untouched.
// Boot-arg -nmxbloff disables the backlight part; NMXPowerKeep (end of file) holds NMXGPU on during display sleep.
//   4. (0.4.0) the system wake work IOGraphics never does for NMXAMDFB. A system sleep clears the framebuffer's
//      pagingState (IOFramebuffer::systemWork, with kIOFBNotifyWillSleep to every client). IOGraphics sets it again
//      only from its own power work (IOFramebuffer::setPowerState -> checkPowerWork -> handleEvent(DidPowerOn, info)).
//      NMXAMDFB replaces setPowerState and acks at once, and its handleEvent() calls do nothing off the controller's
//      power thread, so after the first system sleep pagingState stayed clear and WindowServer slept in
//      IOFramebuffer::_extEntry forever (Step109 test 2026-11-04: ws_main_thread in IOGraphicsWorkLoop::sleepGate,
//      userspace watchdog panic 120 s later). Same bug and fix as NVRMFB's familyDidWake (nmxaccel PR #182): the
//      setPowerState slot of the private vtable wraps NMXAMDFB's; on power-on after a system sleep, if pagingState is
//      still clear, it delivers DidWake(true), DidWake(false) for each WillSleep(false), DidPowerOn(false), sets
//      pagingState and wakes WindowServer, all under a command gate on the framebuffer's workloop. A thread call 3 s
//      after the system power-on does the same if the power-on never reached the framebuffer. -nmxfbwakeoff disables it.
#include <IOKit/IOCommandGate.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/graphics/IOFramebuffer.h>
#include <IOKit/graphics/IODisplay.h>
#include <IOKit/ndrvsupport/IOMacOSVideo.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/pwr_mgt/RootDomain.h>
#include <kern/thread_call.h>
#include <libkern/OSAtomic.h>
#include <pexpert/pexpert.h>

extern "C" IOReturn _ZN13IOFramebuffer13getAppleSenseEiPjS0_S0_S0_(IOFramebuffer *, IOIndex, UInt32 *, UInt32 *,
                                                                    UInt32 *, UInt32 *);
extern "C" IOReturn _ZN9IOService13setPowerStateEmPS_(IOService *, unsigned long, IOService *);

// IOFramebuffer's protected state, read and driven from outside the class (never instantiated)
struct FBPeek : IOFramebuffer {
    static bool paging(IOFramebuffer *fb) { return static_cast<FBPeek *>(fb)->pagingState; }
    static void setPaging(IOFramebuffer *fb) { static_cast<FBPeek *>(fb)->pagingState = true; }
    static void *serverEvent(IOFramebuffer *fb) { return &static_cast<FBPeek *>(fb)->fServerConnect; }
    static IOReturn deliver(IOFramebuffer *fb, IOIndex event, void *info)
    {
        return static_cast<FBPeek *>(fb)->deliverFramebufferNotification(event, info);
    }
};

namespace {
// NMXGPU (Step99 build and later caves; none of these move): file addresses.
constexpr uint64_t kVtable = 0x8f4f10;          // __ZTV8NMXGPUFB
constexpr uint64_t kVtableBytes = 0xb08;        // up to __ZTVN8NMXGPUFB9MetaClassE
constexpr uint64_t kUpdate = 0x6c3970;          // linux_backlight_update_status(device_t, struct backlight_props *)
constexpr uint64_t kGet = 0x6c39f0;             // linux_backlight_get_status(device_t, struct backlight_props *)
constexpr uint64_t kNext = 0x6d25f0;            // nmx_backlight_next(struct cdev *prev, device_t *devp)
const uint8_t kUpdateSig[24] = {0x55,0x48,0x89,0xe5,0x41,0x56,0x53,0x48,0x89,0xf3,0x49,0x89,0xfe,0xe8,0x2e,0x3b,0x01,0x00,0x48,0x83,0x78,0x10,0x00,0x74};
const uint8_t kGetSig[24]    = {0x55,0x48,0x89,0xe5,0x41,0x56,0x53,0x48,0x89,0xf3,0x49,0x89,0xfe,0xe8,0xae,0x3a,0x01,0x00,0x48,0x83,0x78,0x10,0x00,0x74};
const uint8_t kNextSig[24]   = {0x55,0x48,0x89,0xe5,0x41,0x56,0x53,0x48,0x89,0xf3,0x49,0x89,0xfe,0x48,0x8d,0x3d,0x6c,0x91,0x2b,0x00,0xe8,0x37,0x61,0x00};

struct backlight_props { uint32_t brightness; uint32_t nlevels; uint32_t levels[100]; };
typedef int (*status_fn)(void *dev, backlight_props *props);
typedef void *(*next_fn)(void *prev, void **devp);

uintptr_t gBase;
uintptr_t gOrigSense;
volatile bool gLcd;

// system wake work (part 4)
constexpr uintptr_t kServerConnectOff = 0x188;   // IOGraphics 600: _extEntry sleeps on this+0x188 (fServerConnect)
uintptr_t gOrigSetPS;
IOFramebuffer *gWakeFb;
IOCommandGate *gWakeGate;
thread_call_t gWakeLate;
volatile UInt32 gSysSlept;          // a WillSleep came from IOGraphics' system work since the last wake work
volatile SInt32 gWillSleepOff;      // WillSleep(false) notifications owed a DidWake(false)
UInt32 gWakeWorks;

IOReturn wakeGated(OSObject *, void *why, void *, void *, void *)
{
    IOFramebuffer *fb = gWakeFb;
    if (!fb || FBPeek::paging(fb)) return kIOReturnSuccess;   // already done (or IOGraphics did it after all)
    // DidWake(true), then as many DidWake(false) as WillSleep(false) arrived: IOGraphicsAccelerator2 counts
    // WillSleep(false) as a mode change in progress and stays disabled until each one is matched (NVRMFB 5583ee9)
    const SInt32 owed = gWillSleepOff;
    IOReturn r1 = FBPeek::deliver(fb, kIOFBNotifyDidWake, (void *)true);
    IOReturn r2 = FBPeek::deliver(fb, kIOFBNotifyDidWake, (void *)false);
    for (SInt32 i = 1; i < owed; ++i) r2 = FBPeek::deliver(fb, kIOFBNotifyDidWake, (void *)false);
    IOReturn r3 = FBPeek::deliver(fb, kIOFBNotifyDidPowerOn, (void *)false);
    FBPeek::setPaging(fb);
    gWakeGate->commandWakeup(FBPeek::serverEvent(fb), false);
    gWillSleepOff = 0;
    ++gWakeWorks;
    IOLog("NMXBacklight: paging wake (%s, #%u): DidWake true + %d x false (0x%x/0x%x), DidPowerOn 0x%x, paging on, "
          "WindowServer woken\n", static_cast<const char *>(why), unsigned(gWakeWorks), owed > 1 ? int(owed) : 1, r1, r2, r3);
    return kIOReturnSuccess;
}

void wakeWork(const char *why)
{
    if (!gWakeGate || !gWakeFb) return;
    if (!OSCompareAndSwap(1, 0, &gSysSlept)) return;   // no system sleep since the last wake work
    if (FBPeek::paging(gWakeFb)) { IOLog("NMXBacklight: %s: paging already on, nothing to do\n", why); return; }
    gWakeGate->runAction(&wakeGated, const_cast<char *>(why));
}

IOReturn nmxSetPowerState(IOService *self, unsigned long ordinal, IOService *device)
{
    IOReturn r = reinterpret_cast<decltype(&nmxSetPowerState)>(gOrigSetPS)(self, ordinal, device);
    if (ordinal && self == gWakeFb) wakeWork("framebuffer power-on");
    return r;
}

void wakeLateFire(thread_call_param_t, thread_call_param_t)
{
    // a dark wake leaves the framebuffer off: its own power-on does the work later
    if (gWakeFb && gWakeFb->getPowerState() > 0) wakeWork("3 s after system power-on");
}

IOReturn fbTap(OSObject *, void *, IOFramebuffer *fb, IOIndex event, void *info)
{
    if (fb != gWakeFb || event != kIOFBNotifyWillSleep) return kIOReturnSuccess;
    // only IOGraphics' system work sends WillSleep here: NMXAMDFB's own handleEvent(WillPowerOff) is a no-op off the
    // controller thread, and a display sleep does not clear pagingState
    gSysSlept = 1;
    if (!info) OSIncrementAtomic(&gWillSleepOff);
    return kIOReturnSuccess;
}

IOReturn nmxSense(IOFramebuffer *fb, IOIndex idx, UInt32 *senseType, UInt32 *primary, UInt32 *extended,
                  UInt32 *displayType)
{
    if (idx == 0 && gLcd) {
        if (senseType) *senseType = 0;
        if (primary) *primary = 0;
        if (extended) *extended = 0;
        if (displayType) *displayType = kGenericLCD;
        return kIOReturnSuccess;
    }
    return reinterpret_cast<decltype(&nmxSense)>(gOrigSense)(fb, idx, senseType, primary, extended, displayType);
}

bool sigOk(uint64_t at, const uint8_t *sig) { return memcmp(reinterpret_cast<const void *>(gBase + at), sig, 24) == 0; }

// The panel's device in xkpi's backlight registry, or nullptr while amdgpu has not registered it yet.
void *panelDev()
{
    void *dev = nullptr;
    void *c = reinterpret_cast<next_fn>(gBase + kNext)(nullptr, &dev);
    return c ? dev : nullptr;
}
}

class NMXBacklight;

class NMXBacklightHandler : public IODisplayParameterHandler {
    OSDeclareDefaultStructors(NMXBacklightHandler)
    NMXBacklight *owner = nullptr;
    thread_call_t apply = nullptr;
    volatile SInt32 pending = -1;
    SInt32 level = 80;
    UInt32 rawCount = 0;
    static void applyFire(thread_call_param_t me, thread_call_param_t);
public:
    static NMXBacklightHandler *with(NMXBacklight *o, SInt32 percent);
    bool setDisplay(IODisplay *display) override;
    bool doIntegerSet(OSDictionary *params, const OSSymbol *paramName, UInt32 value) override;
    bool doDataSet(const OSSymbol *, OSData *) override { return false; }
    bool doUpdate() override { return true; }
    void free() override;
};

class NMXBacklight : public IOService {
    OSDeclareDefaultStructors(NMXBacklight)
    IOLock *lock = nullptr;
    NMXBacklightHandler *handler = nullptr;
    UInt32 writes = 0, failures = 0;
    IONotifier *tap = nullptr;
    int wakeSlot(IOFramebuffer *fb, const uintptr_t *vt);
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    bool setPercent(UInt32 percent);
};

OSDefineMetaClassAndStructors(NMXBacklight, IOService)
OSDefineMetaClassAndStructors(NMXBacklightHandler, IODisplayParameterHandler)

bool NMXBacklight::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    int off = 0;
    if (PE_parse_boot_argn("-nmxbloff", &off, sizeof off)) { IOLog("NMXBacklight: -nmxbloff, inert\n"); return false; }
    auto fb = OSDynamicCast(IOFramebuffer, provider);
    if (!fb) return false;
    uintptr_t vptr = *reinterpret_cast<uintptr_t *>(fb);
    gBase = vptr - (kVtable + 16);
    if (gBase & 0xfff) { IOLog("NMXBacklight: vtable %lx is not NMXGPUFB's, inert\n", vptr); return false; }
    if (!sigOk(kUpdate, kUpdateSig) || !sigOk(kGet, kGetSig) || !sigOk(kNext, kNextSig)) {
        IOLog("NMXBacklight: NMXGPU at %lx is not the known build, inert\n", gBase);
        return false;
    }
    // the one getAppleSense slot (not overridden by NMXGPUFB: it holds IOFramebuffer's)
    auto vt = reinterpret_cast<uintptr_t *>(vptr);
    uintptr_t base = reinterpret_cast<uintptr_t>(&_ZN13IOFramebuffer13getAppleSenseEiPjS0_S0_S0_);
    int slot = -1, hits = 0;
    for (unsigned i = 0; i < (kVtableBytes - 16) / 8; i++)
        if (vt[i] == base) { slot = int(i); hits++; }
    if (hits != 1) { IOLog("NMXBacklight: getAppleSense slot found %d times, inert\n", hits); return false; }

    lock = IOLockAlloc();
    void *dev = panelDev();
    SInt32 initial = 80;
    if (dev) {
        backlight_props p {};
        if (reinterpret_cast<status_fn>(gBase + kGet)(dev, &p) == 0 && p.brightness <= 100) initial = SInt32(p.brightness);
    }
    handler = NMXBacklightHandler::with(this, initial);
    if (!lock || !handler) { IOLog("NMXBacklight: allocation failed\n"); return false; }

    const int psSlot = wakeSlot(fb, vt);

    // private vtable copy for this object only; never freed (the object may outlive the kext's interest in it)
    auto copy = static_cast<uintptr_t *>(IOMalloc(kVtableBytes));
    if (!copy) return false;
    memcpy(copy, reinterpret_cast<void *>(vptr - 16), kVtableBytes);
    gOrigSense = base;
    copy[2 + slot] = reinterpret_cast<uintptr_t>(&nmxSense);
    if (psSlot >= 0) {
        gOrigSetPS = vt[psSlot];
        copy[2 + psSlot] = reinterpret_cast<uintptr_t>(&nmxSetPowerState);
    }
    gLcd = true;
    __atomic_store_n(reinterpret_cast<uintptr_t *>(fb), reinterpret_cast<uintptr_t>(copy + 2), __ATOMIC_RELEASE);

    handler->setName("backlight");
    if (!handler->attach(fb)) { IOLog("NMXBacklight: handler attach failed\n"); return false; }
    handler->registerService(kIOServiceSynchronous);
    bool shown = false;
    if (auto it = fb->getChildIterator(gIOServicePlane)) {
        while (auto o = it->getNextObject())
            if (OSDynamicCast(IODisplayConnect, o) && static_cast<IOService *>(o)->getChildEntry(gIOServicePlane)) shown = true;
        it->release();
    }
    setProperty("Backlight,Slot", uint32_t(slot), 32);
    setProperty("PagingWake,Slot", uint64_t(int64_t(psSlot)), 32);
    setProperty("Backlight,Initial", uint32_t(initial), 32);
    setProperty("Backlight,PanelAtStart", dev != nullptr);
    setProperty("Backlight,DisplayBeforeUs", shown);
    IOLog("NMXBacklight: NMXGPU at %lx, sense slot %d, panel %s, initial %d%%, display %s; handler published; "
          "paging wake %s (setPowerState slot %d)\n", gBase, slot, dev ? "registered" : "not yet", int(initial),
          shown ? "ALREADY matched (slider needs a re-probe)" : "not yet", psSlot >= 0 ? "on" : "OFF", psSlot);
    registerService();
    return true;
}

// Part 4 setup: the setPowerState slot (found in this class's own vtable, where it still holds IOService's), the
// WillSleep tap and the command gate on the framebuffer's workloop. -1 leaves the slot alone (wake work off).
int NMXBacklight::wakeSlot(IOFramebuffer *fb, const uintptr_t *vt)
{
    if (PE_parse_boot_argn("-nmxfbwakeoff", nullptr, 0)) { IOLog("NMXBacklight: -nmxfbwakeoff, no paging wake\n"); return -1; }
    if (reinterpret_cast<uintptr_t>(FBPeek::serverEvent(fb)) - reinterpret_cast<uintptr_t>(fb) != kServerConnectOff) {
        IOLog("NMXBacklight: fServerConnect not at 0x188 in this SDK, no paging wake\n");
        return -1;
    }
    const uintptr_t ios = reinterpret_cast<uintptr_t>(&_ZN9IOService13setPowerStateEmPS_);
    const uintptr_t *mine = *reinterpret_cast<uintptr_t *const *>(this);
    // first hit: this class's vtable comes first; the next one in the kext (the handler's) holds it too
    int ps = -1;
    for (unsigned i = 0; i < (kVtableBytes - 16) / 8 && ps < 0; i++)
        if (mine[i] == ios) ps = int(i);
    // NMXAMDFB overrides it: the framebuffer's slot must point into NMXGPU's text
    if (ps < 0 || vt[ps] < gBase || vt[ps] >= gBase + kVtable) {
        IOLog("NMXBacklight: setPowerState slot %d (fb %lx) is not NMXAMDFB's, no paging wake\n", ps,
              ps >= 0 ? vt[ps] : 0UL);
        return -1;
    }
    IOWorkLoop *wl = fb->getWorkLoop();
    gWakeFb = fb;
    tap = fb->addFramebufferNotification(&fbTap, this, nullptr);
    gWakeGate = IOCommandGate::commandGate(this);
    if (gWakeGate && wl && wl->addEventSource(gWakeGate) != kIOReturnSuccess) OSSafeReleaseNULL(gWakeGate);
    gWakeLate = thread_call_allocate(wakeLateFire, nullptr);
    if (!tap || !gWakeGate || !gWakeLate || !wl) {
        IOLog("NMXBacklight: paging wake setup failed (tap %d gate %d call %d wl %d)\n", tap != nullptr,
              gWakeGate != nullptr, gWakeLate != nullptr, wl != nullptr);
        if (tap) { tap->remove(); tap = nullptr; }
        if (gWakeGate) { if (wl) wl->removeEventSource(gWakeGate); OSSafeReleaseNULL(gWakeGate); }
        gWakeFb = nullptr;
        return -1;
    }
    return ps;
}

void nmxWakeLate()
{
    if (gWakeLate && gWakeFb) {
        uint64_t d;
        clock_interval_to_deadline(3, kSecondScale, &d);
        thread_call_enter_delayed(gWakeLate, d);
    }
}

void NMXBacklight::stop(IOService *provider)
{
    gLcd = false;   // the vtable copy stays; its sense slot falls back to IOFramebuffer's
    // the setPowerState slot stays wrapped too: wakeWork() does nothing once gWakeFb is cleared
    if (tap) { tap->remove(); tap = nullptr; }
    gWakeFb = nullptr;
    if (gWakeLate) { thread_call_cancel(gWakeLate); }
    if (handler) { handler->detach(provider); handler->release(); handler = nullptr; }
    IOService::stop(provider);
}

bool NMXBacklight::setPercent(UInt32 percent)
{
    if (percent > 100) percent = 100;
    IOLockLock(lock);
    void *dev = panelDev();
    int rc = -1;
    if (dev) {
        backlight_props p {};
        p.brightness = percent;
        rc = reinterpret_cast<status_fn>(gBase + kUpdate)(dev, &p);
    }
    bool ok = dev && rc == 0;
    if (ok) writes++; else failures++;
    UInt32 w = writes, f = failures;
    IOLockUnlock(lock);
    setProperty("Backlight,Writes", w, 32);
    setProperty("Backlight,Failures", f, 32);
    setProperty("Backlight,LastRc", uint32_t(rc), 32);
    if (ok) setProperty("Backlight,Percent", percent, 32);
    if ((ok && w <= 40) || (!ok && f <= 8))
        IOLog("NMXBacklight: %u%% %s (rc %d)\n", percent, ok ? "applied" : dev ? "failed" : "no panel backlight yet", rc);
    return ok;
}

NMXBacklightHandler *NMXBacklightHandler::with(NMXBacklight *o, SInt32 percent)
{
    auto h = OSTypeAlloc(NMXBacklightHandler);
    if (!h || !h->init()) { if (h) h->release(); return nullptr; }
    h->owner = o;
    h->level = percent;
    h->apply = thread_call_allocate(applyFire, h);
    if (!h->apply) { h->release(); return nullptr; }
    return h;
}

void NMXBacklightHandler::free()
{
    if (apply) {
        thread_call_cancel(apply);
        while (!thread_call_free(apply)) { thread_call_cancel(apply); IOSleep(1); }
        apply = nullptr;
    }
    IODisplayParameterHandler::free();
}

// The framebuffer reports no display parameters, so IODisplayParameters may not exist yet; IODisplay::setProperties()
// only accepts parameters listed there.
bool NMXBacklightHandler::setDisplay(IODisplay *display)
{
    if (!display) return false;
    OSObject *old = display->copyProperty(gIODisplayParametersKey);
    OSDictionary *cur = OSDynamicCast(OSDictionary, old);
    OSDictionary *params = cur ? OSDictionary::withDictionary(cur) : OSDictionary::withCapacity(2);
    if (old) old->release();
    if (!params) return false;
    IODisplay::addParameter(params, gIODisplayBrightnessKey, 0, 100);
    IODisplay::setParameter(params, gIODisplayBrightnessKey, level);
    IODisplay::addParameter(params, gIODisplayLinearBrightnessKey, 0, 100);
    IODisplay::setParameter(params, gIODisplayLinearBrightnessKey, level);
    display->setProperty(gIODisplayParametersKey, params);
    params->release();
    IOLog("NMXBacklight: brightness parameters on %s (%s) at %d%%\n", display->getName(),
          display->getMetaClass()->getClassName(), int(level));
    return true;
}

// IODisplay calls this with the framebuffer lock held: the amdgpu call runs from the thread call.
bool NMXBacklightHandler::doIntegerSet(OSDictionary *, const OSSymbol *paramName, UInt32 value)
{
    if (rawCount < 40) {
        ++rawCount;
        IOLog("NMXBacklight: set %s = %u\n", paramName ? paramName->getCStringNoCopy() : "?", unsigned(value));
    }
    if (paramName != gIODisplayBrightnessKey && paramName != gIODisplayLinearBrightnessKey) return false;
    pending = value > 100 ? 100 : SInt32(value);
    if (apply) thread_call_enter(apply);
    return true;
}

void NMXBacklightHandler::applyFire(thread_call_param_t p, thread_call_param_t)
{
    auto me = static_cast<NMXBacklightHandler *>(p);
    SInt32 v;
    do { v = me->pending; } while (!OSCompareAndSwap(UInt32(v), UInt32(-1), (volatile UInt32 *)&me->pending));
    if (v < 0 || !me->owner) return;
    if (me->owner->setPercent(UInt32(v))) me->level = v;
}

// NMXPowerKeep: keeps NMXGPU powered while the system is awake.
// NMXGPU registers two power states but never asks for one itself, so its state follows its children: when display
// sleep takes the framebuffer down, NMXGPU drops to 0 and runs a full amdgpu suspend under WindowServer and NMXAccel
// (the 2026-10-17 hang: "NMXGPU slow (SetState 0, 708 ms)", WindowServer timeout, silent hang). This service joins the
// power tree as a child of NMXGPU and asks for state 1, which needs NMXGPU's kIOPMPowerOn, so display sleep becomes
// the framebuffer's own DPMS off/on only. On system sleep the power domain goes down from the top and this child
// follows it to 0 as any device does. Boot-arg -nmxkeepoff leaves it inert; nmxkeep_dsleep=0 keeps the logging but
// lets display sleep suspend NMXGPU (test harness). It also logs the system sleep/wake timeline (PowerKeep,Sys*).
class NMXPowerKeep : public IOService {
    OSDeclareDefaultStructors(NMXPowerKeep)
    bool pm = false;
    UInt32 changes = 0;
    IONotifier *sysNote = nullptr;
    uint64_t tSleep = 0;
    UInt32 sleeps = 0, wakes = 0;
    static IOReturn sysPower(void *target, void *ref, UInt32 type, IOService *provider, void *arg, vm_size_t size);
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    IOReturn setPowerState(unsigned long state, IOService *device) override;
};

OSDefineMetaClassAndStructors(NMXPowerKeep, IOService)

bool NMXPowerKeep::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    if (PE_parse_boot_argn("-nmxkeepoff", nullptr, 0)) { IOLog("NMXPowerKeep: -nmxkeepoff, inert\n"); return false; }
    static IOPMPowerState states[2] = {
        { kIOPMPowerStateVersion1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { kIOPMPowerStateVersion1, kIOPMPowerOn, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    PMinit();
    provider->joinPMtree(this);
    if (registerPowerDriver(this, states, 2) != kIOReturnSuccess) {
        IOLog("NMXPowerKeep: registerPowerDriver failed, inert\n");
        PMstop();
        return false;
    }
    pm = true;
    // nmxkeep_dsleep=0: do not hold NMXGPU, so display sleep runs NMXGPU's own suspend/resume while the system stays
    // awake (a harness for the NMXGPU suspend path, sleep plan stage 2b; the default 1 is the Step106 behaviour)
    UInt32 hold = 1;
    PE_parse_boot_argn("nmxkeep_dsleep", &hold, sizeof hold);
    if (hold) changePowerStateTo(1);
    setProperty("PowerKeep,Wanted", uint64_t(hold ? 1 : 0), 32);
    // system sleep/wake timeline for the stage 2a tests (logs only; never delays sleep)
    sysNote = registerPrioritySleepWakeInterest(&NMXPowerKeep::sysPower, this, nullptr);
    setProperty("PowerKeep,SysSleeps", 0ULL, 32);
    IOLog("NMXPowerKeep: %s %s while the system is awake; sleep/wake interest %s\n", hold ? "holding" : "NOT holding",
          provider->getName(), sysNote ? "on" : "FAILED");
    registerService();
    return true;
}

void NMXPowerKeep::stop(IOService *provider)
{
    if (sysNote) { sysNote->remove(); sysNote = nullptr; }
    if (pm) PMstop();
    pm = false;
    IOService::stop(provider);
}

IOReturn NMXPowerKeep::setPowerState(unsigned long state, IOService *)
{
    UInt32 n = ++changes;
    setProperty("PowerKeep,State", uint64_t(state), 32);
    setProperty("PowerKeep,Changes", n, 32);
    if (n <= 64) IOLog("NMXPowerKeep: power state %lu (change %u)\n", state, unsigned(n));
    return kIOPMAckImplied;
}

IOReturn NMXPowerKeep::sysPower(void *target, void *, UInt32 type, IOService *, void *arg, vm_size_t)
{
    auto me = static_cast<NMXPowerKeep *>(target);
    auto note = static_cast<IOPowerStateChangeNotification *>(arg);
    uint64_t now = mach_absolute_time(), ns = 0;
    switch (type) {
    case kIOMessageCanSystemSleep:
        if (note) note->returnValue = 0;
        break;
    case kIOMessageSystemWillSleep:
        me->tSleep = now;
        me->sleeps++;
        me->setProperty("PowerKeep,SysSleeps", me->sleeps, 32);
        IOLog("NMXPowerKeep: system will sleep (#%u), keep state %u\n", unsigned(me->sleeps),
              unsigned(me->getPowerState()));
        if (note) note->returnValue = 0;
        break;
    case kIOMessageSystemWillPowerOn:
        if (me->tSleep) absolutetime_to_nanoseconds(now - me->tSleep, &ns);
        IOLog("NMXPowerKeep: system will power on, %llu ms after will-sleep\n", ns / 1000000);
        nmxWakeLate();   // HasPoweredOn did not arrive in the 2026-11-04 test: arm the fallback here already
        break;
    case kIOMessageSystemHasPoweredOn:
        me->wakes++;
        if (me->tSleep) absolutetime_to_nanoseconds(now - me->tSleep, &ns);
        me->setProperty("PowerKeep,SysWakes", me->wakes, 32);
        me->setProperty("PowerKeep,LastWakeMs", ns / 1000000, 64);
        IOLog("NMXPowerKeep: system has powered on (#%u), %llu ms after will-sleep, keep state %u\n",
              unsigned(me->wakes), ns / 1000000, unsigned(me->getPowerState()));
        nmxWakeLate();
        break;
    default:
        break;
    }
    return kIOReturnSuccess;
}
