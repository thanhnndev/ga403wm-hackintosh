// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925WifiInterface, stage 2 (see itlmt7925_iface.h and docs/IO80211-ABI-2.md "Native stub, stage 2").
//
// Order of AppleBCMWLANSkywalkInterface::start(core, RegistrationInfo*) (0xffffff800156a576), which this follows:
//   IO80211InfraInterface::start(core) -> work queue of the interface -> (bus layer creates pool + queues) -> every Tx
//   submission queue, then the Tx completion and Rx completion queue go on the work queue as event sources -> headroom
//   (info+0x3c) is subtracted from info+0x48 / +0x4c -> registerInfraEthernetInterface(info, [Tx x n, TxC, RxC], n+2, pool, pool)
//   (result 0 = success). The pool and the queues are created here directly with the IOSkywalk factories.
#include "itlmt7925_iface.h"
#include "ether_checksum.h"

#include <IOKit/IOLib.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <stdarg.h>
#include <string.h>
#include <pexpert/pexpert.h>

#define super IO80211InfraProtocol
OSDefineMetaClassAndStructors(itlmt7925WifiInterface, IO80211InfraProtocol)

// IO80211Controller::postMessage(IO80211SkywalkInterface *, uint32_t code, void *data, unsigned long length, bool): what Apple's
// AppleBCMWLANCore calls for every event it sends to userland (0xffffff800222b340 in 24H32; non-virtual, hands the event to the
// controller's post office). Declared by symbol: the generated Family header keeps only the slot-exact virtuals.
extern "C" IOReturn itlmtPostMessage(IO80211Controller *controller, IO80211SkywalkInterface *iface, uint32_t code, void *data,
                                     unsigned long length, bool flag)
    __asm__("__ZN17IO80211Controller11postMessageEP23IO80211SkywalkInterfacejPvmb");   // assembler name: leading '_' + Itanium name

namespace {

// Sizes Apple's PCIe layer uses with its state words at 0 (ABI-2 section 2): TxSubmission/TxCompletion `a`, RxSubmission/
// RxCompletion `c`, pool `d` packets of `e` bytes.
const uint32_t kTxCapacity = 0x200;
const uint32_t kRxCapacity = 0x400;
const uint32_t kPoolPackets = 0x1300;
const uint32_t kPoolBufferSize = 0x800;

// Dequeue / completion callbacks. What a callback must do with the packets it is handed (ownership, completion) is NOT
// determined (stage 2 has no radio and never enables the queues); they take nothing and report no work.
uint32_t txSubmissionAction(OSObject *owner, IOSkywalkTxSubmissionQueue *, IOSkywalkPacket *const *packets, uint32_t count, void *)
{ return ((itlmt7925WifiInterface *)owner)->submitPackets(packets, count); }
uint32_t rxSubmissionAction(OSObject *, IOSkywalkRxSubmissionQueue *, IOSkywalkPacket *const *, uint32_t, void *) { return 0; }
uint32_t txCompletionAction(OSObject *, IOSkywalkTxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *) { return 0; }
uint32_t rxCompletionAction(OSObject *, IOSkywalkRxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *) { return 0; }

// RegistrationInfo is an opaque 0x130-byte block (ABI-2 section 2): only the words the registration path edits are touched.
template <typename T>
inline T &field(IOSkywalkEthernetInterface::RegistrationInfo *info, size_t off)
{
    return *(T *)((uint8_t *)info + off);
}

inline void rel(OSObject *o)
{
    if (o) o->release();
}

}

void itlmtTrace(IORegistryEntry *e, const char *fmt, ...)
{
    if (!e) return;
    char add[96];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(add, sizeof(add), fmt, ap);
    va_end(ap);
    IOLog("itlmt-native: %s\n", add); // also emit every milestone to the kernel log before registry work
    e->setProperty("itlmt_native_last", add);
    char buf[1536];
    buf[0] = 0;
    OSObject *snapshot = e->copyProperty("itlmt_native_trace");
    if (OSString *old = OSDynamicCast(OSString, snapshot))
        strlcpy(buf, old->getCStringNoCopy(), sizeof(buf));
    if (snapshot) snapshot->release();
    if (buf[0]) strlcat(buf, "; ", sizeof(buf));
    bool full = strlcat(buf, add, 1500) >= 1500;
    if (full) {
        // The startup prefix is full: keep going in a second append-only property (latest entry stays in itlmt_native_last).
        char tail[1536];
        tail[0] = 0;
        OSObject *ts = e->copyProperty("itlmt_native_trace_tail");
        if (OSString *old = OSDynamicCast(OSString, ts))
            strlcpy(tail, old->getCStringNoCopy(), sizeof(tail));
        if (ts) ts->release();
        if (tail[0]) strlcat(tail, "; ", sizeof(tail));
        if (strlcat(tail, add, 1500) < 1500)
            e->setProperty("itlmt_native_trace_tail", tail);
    }
    if (!full) e->setProperty("itlmt_native_trace", buf);
    uint32_t nvtrace = 0;
    if (PE_parse_boot_argn("itlmt_native_nvtrace", &nvtrace, sizeof(nvtrace)) && nvtrace) {
        // Low-frequency lifecycle checkpoints only, no packet bytes or network identifiers.
        // Best effort: a panic before NVRAM flush can still lose the latest checkpoint.
        IORegistryEntry *options = IORegistryEntry::fromPath("/options", gIODTPlane);
        if (options) {
            OSData *data = OSData::withBytes(full ? add : buf, (unsigned)strlen(full ? add : buf));
            if (data) {
                const char *key = full ? "itlmt-native-last" : "itlmt-native-trace";
                options->setProperty(key, data);
                data->release();
                options->setProperty("IONVRAM-FORCESYNCNOW-PROPERTY", key);
            }
            options->release();
        }
    }
}

namespace {

struct CallEntry {
    uint32_t id, count;
    uint32_t caller[3];
    char kind;
};
const uint32_t kCallCap = 160;
const size_t kCallText = 8192;
CallEntry *gCalls = nullptr;
uint32_t gCallN = 0, gCallOverflow = 0;
char *gCallText = nullptr;
IOLock *gCallLock = nullptr;

// Static address of an exported Family function (ABI-2: IO80211WorkQueue::workQueue); runtime minus this = KASLR slide.
const uint64_t kWorkQueueStatic = 0xffffff8002258fccull;

}

void itlmtCallInit()
{
    if (gCallLock) return;
    gCalls = (CallEntry *)IOMalloc(sizeof(CallEntry) * kCallCap);
    gCallText = (char *)IOMalloc(kCallText);
    gCallLock = IOLockAlloc();
    if (!gCalls || !gCallText || !gCallLock) {
        // recorder stays off: itlmtCall checks gCallLock
        if (gCallLock) { IOLockFree(gCallLock); gCallLock = nullptr; }
        if (gCalls) { IOFree(gCalls, sizeof(CallEntry) * kCallCap); gCalls = nullptr; }
        if (gCallText) { IOFree(gCallText, kCallText); gCallText = nullptr; }
        return;
    }
    bzero(gCalls, sizeof(CallEntry) * kCallCap);
    gCallText[0] = 0;
}

void itlmtCallFree()
{
    IOLock *l = gCallLock;
    if (!l) return;
    IOLockLock(l);
    gCallLock = nullptr;
    CallEntry *c = gCalls; gCalls = nullptr;
    char *t = gCallText; gCallText = nullptr;
    IOLockUnlock(l);
    IOLockFree(l);
    if (c) IOFree(c, sizeof(CallEntry) * kCallCap);
    if (t) IOFree(t, kCallText);
}

// Walks at most three saved-frame links above `fp` (the frame of the function that wants the callers). A link is accepted
// only when it lies a few hundred bytes above the previous one inside the same thread stack; anything else stops the walk
// (the recorder must never fault).
void itlmtCallers(uint32_t out[3], uintptr_t fp)
{
    out[0] = out[1] = out[2] = 0;
    if (fp < 0xffffff8000000000ull || (fp & 7)) return;     // kernel stack addresses only
    uint64_t slide = (uint64_t)(uintptr_t)&IO80211WorkQueue::workQueue - kWorkQueueStatic;
    uintptr_t start = fp;
    for (int i = 0; i < 3; i++) {
        uintptr_t *f = (uintptr_t *)fp;
        uintptr_t ra = f[1];
        out[i] = (uint32_t)((uint64_t)ra - slide);
        uintptr_t next = f[0];
        if (next <= fp || next - fp > 0x400 || next - start > 0x1800 || (next & 7) || next < 0xffffff8000000000ull) return;
        fp = next;
    }
}

void itlmtCall(IORegistryEntry *e, char kind, uint32_t id, const uint32_t *callers)
{
    if (!e || !gCallLock) return;
    uint32_t walked[3];
    if (!callers && kind == 'S') {
        // interface stubs: the three return addresses above the stub (the Family dispatcher that asked for the property)
        uintptr_t fp = (uintptr_t)__builtin_frame_address(0);
        itlmtCallers(walked, fp ? *(uintptr_t *)fp : 0);
        callers = walked;
    }
    IOLockLock(gCallLock);
    if (!gCalls || !gCallText) { IOLockUnlock(gCallLock); return; }
    CallEntry *hit = nullptr;
    for (uint32_t n = 0; n < gCallN; n++) {
        CallEntry &c = gCalls[n];
        if (c.kind == kind && c.id == id &&
            (!callers || (c.caller[0] == callers[0] && c.caller[1] == callers[1] && c.caller[2] == callers[2]))) {
            hit = &c;
            break;
        }
    }
    bool publish = false;
    if (hit) {
        hit->count++;
        publish = (hit->count & (hit->count - 1)) == 0;     // 2, 4, 8, ...
    } else if (gCallN < kCallCap) {
        hit = &gCalls[gCallN++];
        hit->kind = kind;
        hit->id = id;
        hit->count = 1;
        for (int i = 0; i < 3; i++) hit->caller[i] = callers ? callers[i] : 0;
        publish = true;
    } else {
        gCallOverflow++;
        publish = (gCallOverflow & (gCallOverflow - 1)) == 0;
    }
    if (publish) {
        size_t len = 0;
        for (uint32_t n = 0; n < gCallN && len + 64 < kCallText; n++) {
            const CallEntry &c = gCalls[n];
            int w = snprintf(gCallText + len, kCallText - len, "%c:%x", c.kind, c.id);
            if (w < 0) break;
            len += (size_t)w;
            if (c.caller[0]) {
                w = snprintf(gCallText + len, kCallText - len, "@%08x/%08x/%08x", c.caller[0], c.caller[1], c.caller[2]);
                if (w < 0) break;
                len += (size_t)w;
            }
            w = snprintf(gCallText + len, kCallText - len, "x%u;", c.count);
            if (w < 0) break;
            len += (size_t)w;
        }
        if (gCallOverflow) snprintf(gCallText + len, kCallText - len, "ovf=%u", gCallOverflow);
        e->setProperty("itlmt_native_calls", gCallText);
    }
    IOLockUnlock(gCallLock);
}

itlmt7925WifiInterface *itlmt7925WifiInterface::withController(IO80211Controller *controller, uint32_t ifId, uint32_t role)
{
    // Same steps as AppleBCMWLANSkywalkInterface::initWithProviderAndParameters: init(), setInterfaceRole, setInterfaceId, attach
    itlmt7925WifiInterface *i = OSTypeAlloc(itlmt7925WifiInterface);
    if (!i) return nullptr;
    if (!i->init()) {
        i->release();
        return nullptr;
    }
    IOEthernetAddress station = {};
    if (controller->getHardwareAddress(&station) != kIOReturnSuccess ||
        !i->IO80211SkywalkInterface::init(controller, (ether_addr *)&station)) {
        i->release(); return nullptr;
    }
    // Seed station identity before start constructs Family MAC agent.
    i->setInterfaceRole(role);
    i->setInterfaceId(ifId);
    i->ctl = controller;
    if (!i->attach(controller)) {
        i->release();
        return nullptr;
    }
    return i;
}

bool itlmt7925WifiInterface::init()
{
    if (!super::init()) return false;
    rxLock = IOLockAlloc();
    itlmtCallInit();            // idempotent; the controller initialises it first, this covers a stand-alone interface
    return rxLock != nullptr;
}

bool itlmt7925WifiInterface::createPoolAndQueues()
{
    IOSkywalkPacketBufferPool::PoolOptions po;
    bzero(&po, sizeof(po));
    po.packets0 = po.packets1 = kPoolPackets;
    po.bufferSize = kPoolBufferSize;
    po.one = 1;
    po.zero = 0;
    po.flags = 1;
    pool = IOSkywalkPacketBufferPool::withName("itlmt7925WifiPool", this, 1, &po);
    itlmtTrace(ctl, "pool=%s", pool ? "ok" : "null");
    if (!pool) return false;

    // Apple creates the common Rx submission queue before any interface (queueId 0, capacity c); where it is registered is not
    // visible in the interface's start (only Tx x n, TxCompletion, RxCompletion are in the array): kept here, not registered.
    rxSub = IOSkywalkRxSubmissionQueue::withPool(pool, kRxCapacity, 0, 0, this, rxSubmissionAction, this, 0);
    for (uint32_t i = 0; i < kNumTx; i++) {
        // Service class of each queue (Apple: table {0, 0x00100080, 0x00380100, 0x00400180} by AC) is NOT set: the plain factory
        // has no parameter for it, the BCM subclass passes it to IOSkywalkTxSubmissionQueue::initWithPool.
        txSub[i] = IOSkywalkTxSubmissionQueue::withPool(pool, kTxCapacity, i, this, txSubmissionAction, this, 0);
        if (!txSub[i]) {
            itlmtTrace(ctl, "txSub[%u]=null", i);
            return false;
        }
    }
    txComp = IOSkywalkTxCompletionQueue::withPool(pool, kTxCapacity, kNumTx, this, txCompletionAction, this, 0);
    rxComp = IOSkywalkRxCompletionQueue::withPool(pool, kRxCapacity, kNumTx + 1, this, rxCompletionAction, this, 0);
    itlmtTrace(ctl, "queues rxSub=%d txComp=%d rxComp=%d", rxSub != nullptr, txComp != nullptr, rxComp != nullptr);
    return rxSub && txComp && rxComp;
}

bool itlmt7925WifiInterface::startWithInfo(IO80211Controller *controller, IOSkywalkEthernetInterface::RegistrationInfo *info)
{
    ctl = controller;
    if (!info || field<uint32_t>(info, 0) != 1 || field<uint32_t>(info, 4) != 0x130) {
        itlmtTrace(ctl, "sw:bad info");
        return false;
    }
    // AppleBCMWLANSkywalkInterface::start: for role 1 it calls deferBSDAttach(true) before IO80211InfraInterface::start
    if (getInterfaceRole() == 1) {
        IOReturn dr = deferBSDAttach(true);
        itlmtTrace(ctl, "sw:deferBSDAttach=%x", dr);
    }
    bool sup = super::start(controller);       // IO80211InfraInterface::start(IOService *)
    itlmtTrace(ctl, "sw:IO80211InfraInterface::start=%d", sup);
    if (!sup) return false;

    IO80211WorkQueue *wq = getWorkQueue();
    itlmtTrace(ctl, "sw:getWorkQueue=%s", wq ? "ok" : "null");
    if (!wq) return false;
    bool made = createPoolAndQueues();
    itlmtTrace(ctl, "sw:pool+queues=%d", made);
    if (!made) {
        destroyPoolAndQueues();
        return false;
    }

    IOSkywalkPacketQueue *queues[kNumTx + 2];
    uint32_t n = 0;
    for (uint32_t i = 0; i < kNumTx; i++) queues[n++] = txSub[i];
    queues[n++] = txComp;
    queues[n++] = rxComp;
    wq->retain();
    queued = wq;
    for (uint32_t i = 0; i < n; i++) {
        IOReturn r = wq->addEventSource(queues[i]);
        if (r != kIOReturnSuccess) {
            itlmtTrace(ctl, "sw:addEventSource[%u]=%x", i, r);
            // remove the ones already on the loop: destroyPoolAndQueues removes every non-null queue, a failed add is harmless
            destroyPoolAndQueues();
            return false;
        }
    }
    itlmtTrace(ctl, "sw:addEventSource x%u ok", n);
    uint32_t dp = 0;
    if (PE_parse_boot_argn("itlmt_native_dp", &dp, sizeof(dp)) && dp) {
        core = controller->getProvider();
        rxRing = (RxFrame *)IOMalloc(sizeof(RxFrame) * kRxRing);
        snap = (ItlNativeAp *)IOMalloc(sizeof(ItlNativeAp) * ITL_NATIVE_AP_MAX);
        dpTimer = IOTimerEventSource::timerEventSource(this, datapathTick);
        if (!core || !rxRing || !snap || !dpTimer || queued->addEventSource(dpTimer) != kIOReturnSuccess) {
            itlmtTrace(ctl, "dp:timer/ring setup failed");
            destroyPoolAndQueues();
            return false;
        }
        ItlNativeSink sink = {2, this, ctl, receiveFromCore, linkFromCore};
        IOReturn br = core->callPlatformFunction(ITL_NATIVE_BIND, false, &sink, nullptr, nullptr, nullptr);
        itlmtTrace(ctl, "dp:bind=%x", br);
        if (br != kIOReturnSuccess) { destroyPoolAndQueues(); return false; }
        IOLockLock(rxLock); bound = true; IOLockUnlock(rxLock);
        dpTimer->setTimeoutMS(kTickMs);
    }

    headroom = field<uint16_t>(info, 0x3c);
    field<uint32_t>(info, 0x48) -= headroom;
    field<uint32_t>(info, 0x4c) -= headroom;

    IOReturn rr = registerInfraEthernetInterface(info, queues, n, pool, pool);
    itlmtTrace(ctl, "sw:registerInfraEthernetInterface=%x", rr);
    if (rr != kIOReturnSuccess) {
        destroyPoolAndQueues();
        return false;
    }
    // AppleBCMWLANSkywalkInterface::start, after a successful registerInfraEthernetInterface: registerService(kIOServiceAsynchronous)
    // (call [vptr+0x5b0]) then setRunningState(false) (call [vptr+0x930]). Gated by itlmt_native_publish >= 1 (default 2).
    uint32_t publish = 2;
    PE_parse_boot_argn("itlmt_native_publish", &publish, sizeof(publish));
    if (getInterfaceRole() == 1 && publish >= 1) {
        registerService(kIOServiceAsynchronous);
        itlmtTrace(ctl, "sw:registerService(8) done");
        setRunningState(false);
        itlmtTrace(ctl, "sw:setRunningState(false) done");
    }
    return true;
}

// Reverse of start; Apple's stop does for each queue: disable (IOEventSource::disable, IOSkywalkPacketQueue overrides it),
// removeEventSource, release.
void itlmt7925WifiInterface::destroyPoolAndQueues()
{
    bool wasBound = false;
    if (rxLock) { IOLockLock(rxLock); wasBound = bound; bound = false; IOLockUnlock(rxLock); }
    if (wasBound && core) {
        itlmtTrace(ctl, "dp:unbind begin");
        core->callPlatformFunction(ITL_NATIVE_UNBIND, false, this, nullptr, nullptr, nullptr);
    }
    dpEnabled = false;
    if (dpTimer) {
        dpTimer->cancelTimeout();
        if (queued) queued->removeEventSource(dpTimer);
        dpTimer->release(); dpTimer = nullptr;
    }
    // Reclaim submitted packets while the completion queue is still enabled.
    while (pendingCount && txComp) {
        IOReturn r = txComp->enqueuePackets(pendingTx, 1, 0);
        if (r != kIOReturnSuccess) {
            // Submission packet completion must notify its source queue before freeing.
            itlmtTrace(ctl, "dp:teardown completion blocked=%x pending=%u", r, pendingCount);
            break;
        }
        memmove(pendingTx, pendingTx + 1, (--pendingCount) * sizeof(pendingTx[0]));
    }
    if (rxRing) { IOFree(rxRing, sizeof(RxFrame) * kRxRing); rxRing = nullptr; }
    if (snap) { IOFree(snap, sizeof(ItlNativeAp) * ITL_NATIVE_AP_MAX); snap = nullptr; }
    scanActive = joinActive = false;
    core = nullptr;
    IOSkywalkPacketQueue *all[kNumTx + 2];
    uint32_t n = 0;
    for (uint32_t i = 0; i < kNumTx; i++) {
        all[n++] = txSub[i];
        txSub[i] = nullptr;
    }
    all[n++] = txComp;
    all[n++] = rxComp;
    txComp = nullptr;
    rxComp = nullptr;
    for (uint32_t i = 0; i < n; i++) {
        if (!all[i]) continue;
        all[i]->disable();
        if (queued) queued->removeEventSource(all[i]);
        all[i]->release();
    }
    rel(rxSub);
    rxSub = nullptr;
    rel(queued);
    queued = nullptr;
    rel(pool);
    pool = nullptr;
}

void itlmt7925WifiInterface::stop(IOService *provider)
{
    destroyPoolAndQueues();
    super::stop(provider);
}

void itlmt7925WifiInterface::free()
{
    destroyPoolAndQueues();
    if (rxLock) { IOLockFree(rxLock); rxLock = nullptr; }
    super::free();
}

CCLogStream *itlmt7925WifiInterface::getLogger() const
{
    return ctl ? ctl->getLogger() : nullptr;
}

IO80211Controller *itlmt7925WifiInterface::getController()
{
    return ctl;
}

uint32_t itlmt7925WifiInterface::getTxQueueDepth()
{
    return kTxCapacity;
}

uint32_t itlmt7925WifiInterface::getRxQueueCapacity()
{
    return kRxCapacity;
}

IOSkywalkPacketQueue *itlmt7925WifiInterface::getMultiCastQueue()
{
    return nullptr;     // optional in Apple's driver (state flag at +0xa2); not created here
}

uint16_t itlmt7925WifiInterface::getTxHeadroom()
{
    return headroom;
}

IOSkywalkRxCompletionQueue *itlmt7925WifiInterface::getRxCompQueue()
{
    return rxComp;
}

IOSkywalkTxCompletionQueue *itlmt7925WifiInterface::getTxCompQueue()
{
    return txComp;
}

IOSkywalkTxSubmissionQueue *itlmt7925WifiInterface::getTxSubQueue(apple80211_wme_ac ac)
{
    return (uint32_t)ac < kNumTx ? txSub[(uint32_t)ac] : nullptr;
}

IOSkywalkPacketBufferPool *itlmt7925WifiInterface::getTxPacketPool()
{
    return pool;
}

IOSkywalkPacketBufferPool *itlmt7925WifiInterface::getRxPacketPool()
{
    return pool;
}

IOReturn itlmt7925WifiInterface::enableDatapath()
{
    if (!bound || !core || !dpTimer) return kIOReturnNotReady;
    if (dpEnabled) return kIOReturnSuccess;
    itlmtTrace(ctl, "dp:enable queues begin");
    itlmtTrace(ctl, "dp:TX completion enable"); txComp->enable();
    itlmtTrace(ctl, "dp:RX completion enable"); rxComp->enable();
    for (uint32_t i = 0; i < kNumTx; i++) {
        itlmtTrace(ctl, "dp:TX submission %u enable", i);
        txSub[i]->enable();
    }
    dpEnabled = true;
    setRunningState(true);
    setProperty("itlmt_datapath_enabled", true);
    dpTimer->setTimeoutMS(kTickMs);
    itlmtTrace(ctl, "dp:enabled");
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::disableDatapath()
{
    if (!dpEnabled) return kIOReturnSuccess;
    itlmtTrace(ctl, "dp:disable queues");
    dpEnabled = false;
    setRunningState(false);
    for (uint32_t i = 0; i < kNumTx; i++) if (txSub[i]) txSub[i]->disable();
    // Completion queues remain active until outstanding TX ownership is returned.
    setProperty("itlmt_datapath_enabled", false);
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::enable(uint32_t options)
{
    itlmtCall(ctl, 'E', 1);
    itlmtTrace(ctl, "if:enable begin options=%x", options);
    IOReturn result = IO80211InfraProtocol::enable(options);
    if (result == kIOReturnSuccess && bound) result = enableDatapath();
    itlmtTrace(ctl, "if:enable result=%x", result);
    return result;
}

IOReturn itlmt7925WifiInterface::disable(uint32_t options)
{
    itlmtCall(ctl, 'E', 0);
    itlmtTrace(ctl, "if:disable begin options=%x", options);
    disableDatapath();
    IOReturn result = IO80211InfraProtocol::disable(options);
    itlmtTrace(ctl, "if:disable result=%x", result);
    return result;
}

// Which user-client types userland (airportd, CoreWLAN, wifivelocityd) opens on the interface, and what the Family answers.
IOReturn itlmt7925WifiInterface::newUserClient(task_t task, void *securityID, UInt32 type, OSDictionary *properties, IOUserClient **handler)
{
    itlmtCall(ctl, 'W', type);
    IOReturn r = super::newUserClient(task, securityID, type, properties, handler);
    itlmtCall(ctl, 'w', (type << 16) | ((uint32_t)r & 0xffff));
    return r;
}

IOReturn itlmt7925WifiInterface::processBSDCommand(__ifnet *netif, uint32_t command, void *data)
{
    bool media = command == 0xc02c6938 || command == 0xc0286938;
    uint32_t index = command == 0xc0286938 ? 1 : 0;
    bool firstMedia = media && !mediaTraced[index];
    itlmtCall(ctl, 'B', command);
    if (firstMedia || command == 0x80206910)
        itlmtTrace(ctl, "if:bsd cmd=%x begin", command);
    IOReturn result = IO80211InfraProtocol::processBSDCommand(netif, command, data);
    // Record only media queries and interface flags; never dump ioctl payloads.
    if (firstMedia || command == 0x80206910 || (media && result != lastMediaResult[index]))
        itlmtTrace(ctl, "if:bsd cmd=%x result=%x", command, result);
    if (media) {
        mediaTraced[index] = true;
        lastMediaResult[index] = result;
        if ((++mediaQueryCount & 63) == 1)
            setProperty("itlmt_media_query_count", (uint64_t)mediaQueryCount, 64);
    }
    return result;
}

uint32_t itlmt7925WifiInterface::getHardwareAssists()
{
    // Core TX accepts complete Ethernet frames. It has no checksum/TSO offload.
    if (!assistsTraced) { assistsTraced = true; itlmtTrace(ctl, "if:hardware assists=0"); }
    setProperty("itlmt_hw_assists", (uint64_t)0, 32);
    return 0;
}

IOReturn itlmt7925WifiInterface::setMacAddress(mloAddrArray &address)
{
    // Tahoe (25G241) hands the station/MLO address array; only the primary address (first ether_addr) is compared. The MLO
    // link addresses are not consumed: the core's firmware setup uses the single station address.
    IOEthernetAddress current = {};
    if (!ctl || ctl->getHardwareAddress(&current) != kIOReturnSuccess) return kIOReturnNotReady;
    bool same = memcmp(&address, &current, 6) == 0;
    itlmtTrace(ctl, "if:setMacAddress %s", same ? "station identity unchanged" : "change refused");
    // Initial MAC is already scheduled into core firmware setup. Do not falsely
    // accept a new address without rebuilding firmware device/BSS configuration.
    // WCLJoinManager issues this (ioctl 0x170) before every join and tolerates success and kIOReturnNotPermitted (a private
    // address that is not applied) but not other codes, so a refusal is NotPermitted.
    return same ? kIOReturnSuccess : kIOReturnNotPermitted;
}

void itlmt7925WifiInterface::setInterfaceEnable(bool enabled)
{
    itlmtTrace(ctl, "if:setInterfaceEnable=%u begin", enabled);
    IO80211InfraProtocol::setInterfaceEnable(enabled);
    itlmtTrace(ctl, "if:setInterfaceEnable=%u done", enabled);
}

uint8_t itlmt7925WifiInterface::getNumTxQueues()
{
    return kNumTx;
}

uint32_t itlmt7925WifiInterface::submitPackets(IOSkywalkPacket *const *packets, uint32_t count)
{
    if (!dpEnabled || !core || !packets) return 0;
    IOLockLock(rxLock);
    bool up = radioUp;
    IOLockUnlock(rxLock);
    if (!up) { txStalled++; return 0; }
    bool first = !firstTxTrace;
    if (first) { firstTxTrace = true; itlmtTrace(ctl, "dp:TX callback begin"); }
    uint32_t used = 0;
    for (; used < count && pendingCount < 512; used++) {
        IOSkywalkPacket *p = packets[used];
        if (!p) break;
        bool single = p->getPacketBufferCount() == 1;
        uint32_t len = p->getDataLength(), size = single ? p->getBufferSize() : 0;
        uint16_t offset = single ? p->getDataOffset() : 0;
        void *base = single ? p->getDataVirtualAddress() : nullptr;
        int result = -1;
        if (base && len >= 14 && len <= 1600 && offset <= size && len <= size - offset) {
            memcpy(txScratch, (const uint8_t *)base + offset, len);
            if (first && used == 0)
                itlmtTrace(ctl, "dp:TX len=%u offset=%u type=%x", len, offset, itl_checksum::read16(txScratch + 12));
            if (itl_checksum::ethernet(txScratch, len)) {
                ItlNativeTx tx = {txScratch, len, -1};
                IOReturn r = core->callPlatformFunction(ITL_NATIVE_TX, false, &tx, nullptr, nullptr, nullptr);
                if (r == kIOReturnSuccess) result = tx.result;
            } else txChecksumFailures++;
        }
        if (result > 0) { txStalled++; break; } // callback takes no ownership of this packet; retry on next tick
        if (result == 0) txSent++; else txDropped++;
        // Complete only after submission callback returns and the queue records consumption.
        pendingTx[pendingCount++] = p;
    }
    if (used && txSent + txDropped <= used) itlmtTrace(ctl, "dp:first TX consumed=%u", used);
    return used;
}

void itlmt7925WifiInterface::receiveFromCore(OSObject *owner, const uint8_t *bytes, uint32_t length)
{
    auto *i = (itlmt7925WifiInterface *)owner;
    if (!i->rxLock) return;
    IOLockLock(i->rxLock);
    uint32_t next = (i->rxHead + 1) % kRxRing;
    if (!i->rxRing || !bytes || length < 14 || length > 1600) { i->rxDropped++; i->rxOversize++; }
    else if (next == i->rxTail) { i->rxDropped++; i->rxRingFull++; }
    else {
        RxFrame &f = i->rxRing[i->rxHead];
        f.length = length; memcpy(f.bytes, bytes, length);
        i->rxHead = next; i->rxReceived++;
        uint32_t depth = (next + kRxRing - i->rxTail) % kRxRing;
        if (depth > i->rxPeak) i->rxPeak = depth;
    }
    IOLockUnlock(i->rxLock);
}

void itlmt7925WifiInterface::linkFromCore(OSObject *owner, bool up, uint64_t speed)
{
    auto *i = (itlmt7925WifiInterface *)owner;
    if (!i->rxLock) return;
    IOLockLock(i->rxLock);
    i->radioUp = up; i->radioSpeed = speed;
    if (!up && i->nmLinkUp) i->linkDownPending = true;      // pollControl tells the family (event 0xd8) from the tick thread
    IOWorkLoop *loop = i->bound ? i->queued : nullptr;
    if (loop) loop->retain();
    IOLockUnlock(i->rxLock);
    // Core worker calls outside bridge lock with owner/controller retained.
    // runAction enters gate on that caller, not the work-loop event thread.
    if (loop) { loop->runAction(applyRadioLink, i); loop->release(); }
}

IOReturn itlmt7925WifiInterface::applyRadioLink(OSObject *owner, void *, void *, void *, void *)
{
    auto *i = (itlmt7925WifiInterface *)owner;
    if (!i->bound || !i->ctl || !i->queued) return kIOReturnNotAttached;
    if (!i->queued->inGate() || i->queued->onThread()) {
        itlmtTrace(i->ctl, "dp:Family link rejected gate/thread"); return kIOReturnNotPermitted;
    }
    IOLockLock(i->rxLock);
    bool up = i->radioUp;
    uint64_t speed = i->radioSpeed;
    IOLockUnlock(i->rxLock);
    i->ctl->setLinkStatus(kIONetworkLinkValid | (up ? kIONetworkLinkActive : 0),
                         up ? i->ctl->getSelectedMedium() : nullptr, up ? speed : 0);
    itlmtTrace(i->ctl, "dp:Family link=%u begin gate=1 thread=0", up);
    // 25G241: setLinkState (InfraInterface slot 463) takes a5 = reason/percent; Apple's own WCL path passes the update's
    // dword at +0xc. The digital core's link events carry no reason, so 0 (setLinkStateInternal only records it).
    bool ok = i->IO80211InfraInterface::setLinkState((IO80211LinkState)(up ? 2 : 1), 0, false, 0, 0);
    itlmtTrace(i->ctl, "dp:Family link=%u result=%u state=%u", up, ok, i->IO80211InfraInterface::linkState());
    i->ctl->setLinkStatus(kIONetworkLinkValid | (up ? kIONetworkLinkActive : 0),
                         up ? i->ctl->getSelectedMedium() : nullptr, up ? speed : 0);
    i->setProperty("itlmt_radio_link", up);
    return ok ? kIOReturnSuccess : kIOReturnError;
}

void itlmt7925WifiInterface::datapathTick(OSObject *owner, IOTimerEventSource *)
{
    ((itlmt7925WifiInterface *)owner)->drainDatapath();
}

void itlmt7925WifiInterface::drainDatapath()
{
    if (!bound || !core || !dpTimer) return;
    // TX staging has already copied packet bytes. Return Skywalk ownership exactly once.
    while (pendingCount) {
        if (!firstCompletionTrace) {
            firstCompletionTrace = true; itlmtTrace(ctl, "dp:TX completion begin");
        }
        IOReturn r = txComp->enqueuePackets(pendingTx, 1, 0);
        if (r != kIOReturnSuccess) {
            if (ticks == 0 || ticks == 100 || ticks == 200)
                itlmtTrace(ctl, "dp:TX completion=%x pending=%u", r, pendingCount);
            break;
        }
        memmove(pendingTx, pendingTx + 1, (--pendingCount) * sizeof(pendingTx[0]));
        txCompleted++;
    }
    if (dpEnabled) {
        // RX copies are moved onto the native gate; core worker never acquires this gate.
        for (uint32_t batch = 0; batch < kRxBatch; batch++) {
            RxFrame f;
            IOLockLock(rxLock);
            bool ready = rxHead != rxTail;
            if (ready) { f = rxRing[rxTail]; rxTail = (rxTail + 1) % kRxRing; }
            IOLockUnlock(rxLock);
            if (!ready) break;
            if (!firstRxTrace) { firstRxTrace = true; itlmtTrace(ctl, "dp:RX allocation/enqueue begin"); }
            IOSkywalkPacket *p = nullptr;
            IOReturn r = pool->allocatePacket(1, &p, 1); // no-sleep allocation on the native work loop
            const char *step = "allocate";
            if (r == kIOReturnSuccess && p) {
                step = "prepare";
                // Allocation acquires only handle. Prepare materializes buflets
                // for CPU copy; RX enqueue completes/finalizes for networking.
                uint32_t before = p->getPacketBufferCount();
                r = p->prepareWithQueue(nullptr, 0, 0);
                uint32_t buffers = p->getPacketBufferCount();
                if (rxDelivered == 0 && rxFailureTraceCount == 0)
                    itlmtTrace(ctl, "dp:RX prepare=%x buffers=%u->%u", r, before, buffers);
                bool single = buffers == 1;
                void *data = r == kIOReturnSuccess && single ? p->getDataVirtualAddress() : nullptr;
                if (r == kIOReturnSuccess) step = "buffer";
                if (r != kIOReturnSuccess) { /* preserve preparation error */ }
                else if (!data || p->getBufferSize() < f.length)
                    r = kIOReturnNoSpace;
                else {
                    memcpy(data, f.bytes, f.length);
                    step = "length";
                    r = p->setDataOffsetAndLength(0, f.length);
                    if (r == kIOReturnSuccess) {
                        step = "metadata";
                        auto *network = static_cast<IOSkywalkNetworkPacket *>(p);
                        uint32_t l2 = 14;
                        uint16_t type = itl_checksum::read16(f.bytes + 12);
                        for (uint32_t tag = 0; tag < 2 && (type == 0x8100 || type == 0x88a8); tag++) {
                            if (f.length < l2 + 4) { r = kIOReturnBadArgument; break; }
                            type = itl_checksum::read16(f.bytes + l2 + 2); l2 += 4;
                        }
                        bool broadcast = true;
                        for (uint32_t b = 0; b < 6; b++) if (f.bytes[b] != 0xff) broadcast = false;
                        if (r == kIOReturnSuccess) r = network->setHeadroom(0);
                        if (r == kIOReturnSuccess) r = network->setLinkHeaderLength((uint8_t)l2);
                        // The bool argument of both setters is ignored by IOSkywalk (24H32 0xffffff800297f262 / ...f290 call
                        // kern_packet_set_link_broadcast/_multicast unconditionally), so a call is itself the flag: call only when true.
                        // Calling them for every frame marked unicast IPv4 as link broadcast and the stack dropped it.
                        if (r == kIOReturnSuccess && broadcast) r = network->setIsLinkBroadcast(true);
                        else if (r == kIOReturnSuccess && (f.bytes[0] & 1)) r = network->setIsLinkMulticast(true);
                        // No hardware checksum-validation claim; stack validates received IP.
                        if (r == kIOReturnSuccess) r = network->setRxChecksumInfo(0, 0);
                    }
                    if (r == kIOReturnSuccess) { step = "enqueue"; r = rxComp->enqueuePackets(&p, 1, 0); }
                }
                if (r != kIOReturnSuccess) pool->deallocatePacket(p);
            }
            if ((r != kIOReturnSuccess || !p) && rxFailureTraceCount++ < 8)
                itlmtTrace(ctl, "dp:RX failed step=%s rc=%x packet=%u len=%u", step, r, p != nullptr, f.length);
            if (r == kIOReturnSuccess && p) rxDelivered++;
            else { IOLockLock(rxLock); rxDropped++; IOLockUnlock(rxLock); }
            if (r == kIOReturnSuccess && p && rxDelivered == 1) itlmtTrace(ctl, "dp:first RX delivered");
        }
        for (uint32_t i = 0; i < kNumTx; i++) txSub[i]->requestDequeue(nullptr, 1);
    }
    if ((++ticks % 500) == 0) {         // once a second at the 2 ms tick
        IOLockLock(rxLock);
        uint32_t received = rxReceived, dropped = rxDropped, full = rxRingFull, oversize = rxOversize, peak = rxPeak;
        IOLockUnlock(rxLock);
        setProperty("itlmt_rx_ringfull", (uint64_t)full, 64);
        setProperty("itlmt_rx_oversize", (uint64_t)oversize, 64);
        setProperty("itlmt_rx_ringpeak", (uint64_t)peak, 32);
        setProperty("itlmt_tx_sent", (uint64_t)txSent, 64);
        setProperty("itlmt_tx_drop", (uint64_t)txDropped, 64);
        setProperty("itlmt_tx_stall", (uint64_t)txStalled, 64);
        setProperty("itlmt_tx_completed", (uint64_t)txCompleted, 64);
        setProperty("itlmt_rx_received", (uint64_t)received, 64);
        setProperty("itlmt_rx_delivered", (uint64_t)rxDelivered, 64);
        setProperty("itlmt_rx_drop", (uint64_t)dropped, 64);
        setProperty("itlmt_tx_pending", (uint64_t)pendingCount, 32);
        setProperty("itlmt_tx_checksum_failed", (uint64_t)txChecksumFailures, 64);
    }
    if ((ticks % (10 / kTickMs)) == 0) pollControl();   // scan/join/re-announce timeouts count in 10 ms polls
    dpTimer->setTimeoutMS(kTickMs);
}

// ---- IO80211InfraProtocol handlers with layouts taken from Apple's AppleBCMWLANCore (24H32) ---------------------------------
//
// Apple's handlers answer from firmware and BSS-manager state; this driver has neither, so each one reports the idle, not-
// associated answer Apple's own code gives for that state and nothing else. The link state is the core driver's (radioUp).
// Error codes: 0xe0822403 is what getRSSI/getRATE return while not associated (0xffffff80015f2238, 0xffffff80015f23de);
// 0xe0822801 is the value getCHANNEL returns when no current channel can be read (0xffffff80015f159c).
namespace {
const IOReturn kNotAssociated = (IOReturn)0xe0822403;
const IOReturn kNoChannel = (IOReturn)0xe0822801;
template <typename T>
inline void store(void *base, size_t off, T v)
{
    memcpy((uint8_t *)base + off, &v, sizeof(v));
}
}

bool itlmt7925WifiInterface::linkUp()
{
    if (!rxLock) return false;
    IOLockLock(rxLock);
    bool up = radioUp;
    IOLockUnlock(rxLock);
    return up;
}

// apple80211_channel_data: u32 version at +0, then an apple80211_channel {version, channel, flags} at +4
// (AppleBCMWLANCore::getCHANNEL 0xffffff80015f1506 passes data+4 to IO80211BssManager::getCurrentChannel / ChanSpecConvToApple80211Channel).
// Flags are the 20 MHz base channel: band bit (0x8 2.4 GHz, 0x10 5 GHz) | 0x2 (20 MHz).
IOReturn itlmt7925WifiInterface::getCHANNEL(apple80211_channel_data *d)
{
    itlmtCall(ctl, 'S', 471);
    if (!d) return kIOReturnBadArgument;
    ItlNativeStatus st;
    if (!queryStatus(&st) || st.state != ITL_NATIVE_UP || !st.channel) return kNoChannel;
    store<uint32_t>(d, 0, 1);
    store<uint32_t>(d, 4, 1);
    store<uint32_t>(d, 8, st.channel);
    store<uint32_t>(d, 0xc, (st.channel > 14 ? 0x10u : 0x8u) | 0x2u);
    return kIOReturnSuccess;
}

// 0xffffff80015f2550: [data+4] = stored power-save mode. Power save is never configured here, so 0.
IOReturn itlmt7925WifiInterface::getPOWERSAVE(apple80211_powersave_data *d)
{
    itlmtCall(ctl, 'S', 472);
    if (!d) return kIOReturnBadArgument;
    store<uint32_t>(d, 4, 0);
    return kIOReturnSuccess;
}

// 0xffffff80015f23aa: [data+8] = current rate in Mb/s (the core's value is kb/s, divided by 1000); not associated -> 0xe0822403.
IOReturn itlmt7925WifiInterface::getRATE(apple80211_rate_data *d)
{
    itlmtCall(ctl, 'S', 474);
    if (!d) return kIOReturnBadArgument;
    ItlNativeStatus st;
    if (!queryStatus(&st) || st.state != ITL_NATIVE_UP) return kNotAssociated;
    store<uint32_t>(d, 8, st.rateMbps);
    return kIOReturnSuccess;
}

// 0xffffff80015f2088: qword at +0 = 1 (version 1, mode word 0), then +4 |= mode bits of the BSS manager when associated.
// The bit is APPLE80211_M_STA = 0x1 (apple80211_var.h; 0x2 is IBSS: round 20 answered 2 and System Information showed the
// current network as "Computer to Computer Network").
IOReturn itlmt7925WifiInterface::getOP_MODE(apple80211_opmode_data *d)
{
    itlmtCall(ctl, 'S', 475);
    if (!d) return (IOReturn)0x16;
    ItlNativeStatus st;
    bool assoc = queryStatus(&st) && st.state == ITL_NATIVE_UP;
    store<uint32_t>(d, 0, 1);
    store<uint32_t>(d, 4, assoc ? 1u : 0u);                                  // APPLE80211_M_STA
    return kIOReturnSuccess;
}

// 0xffffff80015f21fa: associated -> 0x30 bytes at +4 cleared, [+0] = 1, per-chain RSSI (four dwords) at +0xc, number of chains with
// a value at +4, their average at +0x1c; not associated -> 0xe0822403. The core reports one combined value: chain 0, one chain.
IOReturn itlmt7925WifiInterface::getRSSI(apple80211_rssi_data *d)
{
    itlmtCall(ctl, 'S', 476);
    if (!d) return kIOReturnBadArgument;
    ItlNativeStatus st;
    if (!queryStatus(&st) || st.state != ITL_NATIVE_UP) return kNotAssociated;
    bzero((uint8_t *)d + 4, 0x30);
    store<uint32_t>(d, 0, 1);
    if (st.rssi) {
        store<int32_t>(d, 0xc, st.rssi);
        store<int32_t>(d, 0x1c, st.rssi);
        store<uint32_t>(d, 4, 1);
    }
    return kIOReturnSuccess;
}

// Apple's handler (0xffffff8001610836) forwards the notification to firmware iovars (asym_mit_ext_usb[_chg]) and returns 0 for
// chips that do not use them. The MT7925 here is on PCIe; there is nothing to forward, so the notification is accepted.
IOReturn itlmt7925WifiInterface::setUSB_HOST_NOTIFICATION(apple80211_usb_host_notification_data *d)
{
    itlmtCall(ctl, 'S', 582);
    return d ? kIOReturnSuccess : kIOReturnBadArgument;
}

// 0xffffff80016431c8: the qword at data+0 is stored in the core context (feature bits that gate firmware setup); returns 0.
IOReturn itlmt7925WifiInterface::setOS_FEATURE_FLAGS(apple80211_feature_flags *d)
{
    itlmtCall(ctl, 'S', 614);
    if (!d) return kIOReturnBadArgument;
    memcpy(&osFeatureFlags, d, sizeof(osFeatureFlags));
    return kIOReturnSuccess;
}

// 0xffffff800164404c: non-null argument -> 0, null -> 0xe00002bc (kIOReturnError); nothing else is done.
IOReturn itlmt7925WifiInterface::setINFRA_ENUMERATED(apple80211_infra_enumerated *d)
{
    itlmtCall(ctl, 'S', 640);
    return d ? kIOReturnSuccess : kIOReturnError;
}

// ---- scan and join (stage 3) -----------------------------------------------------------------------------------------------
//
// Apple's driver is event driven: the SCAN_REQ / ASSOCIATE ioctls return at once and the outcome reaches userland as events
// posted with IO80211Controller::postMessage (ids and payload layouts taken from AppleBCMWLANCore / AppleBCMWLANJoinAdapter,
// 24H32; the beacon-message header was re-checked against 25G241 on 2026-10-16, see the note on the layout below):
//   0xc9  one scan result: beacon message (below), length 0x44 + ie_len        0xed  scan finished, 4-byte status (0 = ok)
//   0x4e  association result, 8 bytes {status1, status2}
//   0xd3  join result, 0x1c bytes: u16 ieee status, u16 aux, u8 flag, bssid[6] at +5, status1 at +0x14, status2 at +0x18
//   0xd5  connect complete, 0xa4 bytes: u16 ieee status, u16 aux, 10 x {bssid[6], pad[2], u32 status1, u32 status2}
// Beacon message (apple80211_beacon_msg as built by AppleBCMWLANBSSBeacon::getBeaconMsgFromWLBSSInfo; offsets verified on the
// 25G241 BootKernelExtensions.kc): +0 u32 ie_len, +4 u16 channel spec (bits 0-7 channel, 11-13 bandwidth index 2 = 20 MHz,
// 14-15 band, 0xc000 = 5 GHz), +6 ssid[32], +0x26 ssid_len, +0x27 primary channel, +0x29 bssid[6], +0x30 s32 rssi, +0x34
// s16 noise, +0x36 u16 (Apple sets it from wl_bss_info, left zero here), +0x38 u16 beacon interval, +0x3a u16 capability,
// +0x3c u32 (Apple never writes it in either builder, left zero), +0x40 u32 flags (2 always, 0x80 from a beacon, 0x4000 when
// rssi is valid), +0x44 information elements (Apple: ie_len + 0x44 bytes total, IEs capped at 0x800 and the meta buffer is
// 0x844 = 0x44 + 0x800). The header is 0x44, not 0x40: with 0x40 the IE area sat 4 bytes early, so every IE (SSID element
// included) was parsed from the middle of its neighbour - the Wi-Fi list came up with garbled names on Tahoe.
// Not determined (left zero): the u8 flag and +0xc/+0x10 words of 0xd3, the aux words, status values on failure.
namespace {
const uint32_t kBeaconHeader = 0x44;
const uint32_t kEventScanResult = 0xc9, kEventScanDone = 0xed, kEventAssoc = 0x4e, kEventJoin = 0xd3, kEventFirstBeacon = 0xd4,
               kEventConnect = 0xd5, kEventLinkStatus = 0xd8;
// 20 MHz channels the core's scan covers (itlmt7925_m2.cpp): the only channels a result can come from.
const uint8_t kScanChannels[] = {1, 6, 11, 36, 40, 44, 48, 149, 153, 157, 161, 165};
const uint32_t kScanTimeoutTicks = 2500;       // 25 s at the 10 ms tick: the core blocks up to 15 s per scan
const uint32_t kJoinTimeoutTicks = 4500;       // 45 s: scan for the AP, authentication, association, handshake

void buildBeacon(uint8_t *m, const uint8_t *bssid, uint8_t channel, const char *ssid, uint8_t ssidLen, int8_t rssi, uint16_t cap,
                 uint16_t interval, const uint8_t *ie, uint16_t ieLen, bool probe)
{
    bzero(m, kBeaconHeader + ieLen);
    store<uint32_t>(m, 0, ieLen);
    store<uint16_t>(m, 4, (uint16_t)(channel | 0x1000 | (channel > 14 ? 0xC000 : 0)));
    memcpy(m + 6, ssid, ssidLen > 32 ? 32 : ssidLen);
    m[0x26] = ssidLen > 32 ? 32 : ssidLen;
    m[0x27] = channel;
    memcpy(m + 0x29, bssid, 6);
    store<int32_t>(m, 0x30, rssi);
    store<uint16_t>(m, 0x38, interval);
    store<uint16_t>(m, 0x3a, cap);
    store<uint32_t>(m, 0x40, 2u | (probe ? 0u : 0x80u) | (rssi ? 0x4000u : 0u));
    memcpy(m + kBeaconHeader, ie, ieLen);
}
}

bool itlmt7925WifiInterface::queryStatus(ItlNativeStatus *st)
{
    if (!core || !bound) return false;
    st->version = 1;
    return core->callPlatformFunction(ITL_NATIVE_STATUS, false, st, nullptr, nullptr, nullptr) == kIOReturnSuccess;
}

void itlmt7925WifiInterface::postEvent(uint32_t code, void *data, size_t length)
{
    itlmtCall(ctl, 'P', code);
    if (ctl) itlmtPostMessage(ctl, this, code, data, length, true);
}

// getSUPPORTED_CHANNELS / getHW_SUPPORTED_CHANNELS: apple80211_sup_channel_data = u32 version (1), u32 count, then 12-byte
// apple80211_channel entries {version 1, channel, flags}; flags = band (0x8 2.4 GHz, 0x10 5 GHz) | 0x2 (20 MHz) | 0x80 (active
// scan allowed). Apple's own filter words (+0x12c8..) are not applied: every entry is a channel the core can scan and join.
static IOReturn fillSupportedChannels(void *d)
{
    if (!d) return kIOReturnBadArgument;
    const uint32_t n = sizeof(kScanChannels);
    store<uint32_t>(d, 0, 1);
    store<uint32_t>(d, 4, n);
    for (uint32_t i = 0; i < n; i++) {
        uint32_t ch = kScanChannels[i];
        store<uint32_t>(d, 8 + 12 * i, 1);
        store<uint32_t>(d, 8 + 12 * i + 4, ch);
        store<uint32_t>(d, 8 + 12 * i + 8, (ch > 14 ? 0x10u : 0x8u) | 0x2u | 0x80u);
    }
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::getSUPPORTED_CHANNELS(apple80211_sup_channel_data *d)
{
    itlmtCall(ctl, 'S', 477);
    return fillSupportedChannels(d);
}

IOReturn itlmt7925WifiInterface::getHW_SUPPORTED_CHANNELS(apple80211_sup_channel_data *d)
{
    itlmtCall(ctl, 'S', 496);
    return fillSupportedChannels(d);
}

// apple80211ScanRequest (partial, from the layout AppleBCMWLANCore's scan handler reads): +0x1c u32 ssid_len, +0x20 ssid[32]. The
// core always scans its fixed channel list with a wildcard probe; a requested SSID only filters what is reported.
IOReturn itlmt7925WifiInterface::setWCL_SCAN_REQ(apple80211ScanRequest *d)
{
    itlmtCall(ctl, 'S', 603);
    ItlNativeStatus st;
    if (!d) return kIOReturnBadArgument;
    if (!bound || !core || !queryStatus(&st)) return kIOReturnNotReady;
    uint32_t ssidLen = 0;
    memcpy(&ssidLen, (const uint8_t *)d + 0x1c, 4);
    if (ssidLen > 32) return kIOReturnBadArgument;
    ItlNativeScan sc = {1, 0};
    IOReturn r = core->callPlatformFunction(ITL_NATIVE_SCAN, false, &sc, nullptr, nullptr, nullptr);
    if (r != kIOReturnSuccess) return r;
    IOLockLock(rxLock);
    scanSsidLen = (uint8_t)ssidLen;
    memcpy(scanSsid, (const uint8_t *)d + 0x20, ssidLen);
    scanGenAtReq = st.scanGen;
    scanImmediate = sc.started == 0;       // the cached table is current: delivered on the next tick (never inside the ioctl)
    scanTicks = 0;
    scanActive = true;
    IOLockUnlock(rxLock);
    if (scanTraced++ < 4) itlmtTrace(ctl, "scan:request started=%u ssidLen=%u", sc.started, ssidLen);
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::setWCL_SCAN_ABORT(void *)
{
    itlmtCall(ctl, 'S', 598);
    IOLockLock(rxLock);
    bool was = scanActive;
    scanActive = false;
    IOLockUnlock(rxLock);
    if (was) {
        uint32_t status = 0;
        postEvent(kEventScanDone, &status, sizeof(status));
    }
    return kIOReturnSuccess;
}

// apple80211AssocCandidates (partial): +0x1c u32 ssid_len, +0x20 ssid[32], +0x40 apple80211_key {+4 key_len, +8 cipher_type,
// +0x10 key[]}. Apple's supplicant runs in userland: cipher_type 6 / 9 with a 32-byte key is the pairwise master key (derived
// from the passphrase), 0 is "no key". The 4-way handshake and the data keys are the core's; it supports WPA2-PSK / CCMP only.
IOReturn itlmt7925WifiInterface::setWCL_ASSOCIATE(apple80211AssocCandidates *d)
{
    itlmtCall(ctl, 'S', 604);
    if (!d) return kIOReturnBadArgument;
    if (!bound || !core) return kIOReturnNotReady;
    const uint8_t *b = (const uint8_t *)d;
    uint32_t ssidLen = 0, keyLen = 0, cipher = 0;
    memcpy(&ssidLen, b + 0x1c, 4);
    memcpy(&keyLen, b + 0x44, 4);
    memcpy(&cipher, b + 0x48, 4);
    itlmtTrace(ctl, "assoc:request ssidLen=%u cipher=%u keyLen=%u", ssidLen, cipher, keyLen);
    if (ssidLen == 0 || ssidLen > 32) return kIOReturnBadArgument;
    if (!((cipher == 6 || cipher == 9) && keyLen == 32)) return kIOReturnUnsupported;   // open / SAE / enterprise: not implemented
    ItlNativeJoin j;
    bzero(&j, sizeof(j));
    j.version = 1;
    j.ssidLen = (uint8_t)ssidLen;
    memcpy(j.ssid, b + 0x20, ssidLen);
    memcpy(j.pmk, b + 0x50, 32);
    IOReturn r = core->callPlatformFunction(ITL_NATIVE_JOIN, false, &j, nullptr, nullptr, nullptr);
    bzero(&j, sizeof(j));
    if (r != kIOReturnSuccess) { itlmtTrace(ctl, "assoc:core join=%x", r); return r; }
    ItlNativeStatus st;
    bzero(&st, sizeof(st));
    queryStatus(&st);
    IOLockLock(rxLock);
    joinSeq = st.joinSeq;
    joinTicks = 0;
    joinActive = true;
    IOLockUnlock(rxLock);
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::setWCL_LEAVE_NETWORK(apple80211_leave_network *)
{
    itlmtCall(ctl, 'S', 592);
    IOLockLock(rxLock);
    joinActive = false;
    IOLockUnlock(rxLock);
    if (!core || !bound) return kIOReturnNotReady;
    IOReturn r = core->callPlatformFunction(ITL_NATIVE_LEAVE, false, nullptr, nullptr, nullptr, nullptr);
    itlmtTrace(ctl, "assoc:leave=%x", r);
    return kIOReturnSuccess;
}

IOReturn itlmt7925WifiInterface::setWCL_JOIN_ABORT(apple80211_wcl_abort_join *)
{
    itlmtCall(ctl, 'S', 601);
    IOLockLock(rxLock);
    bool was = joinActive;
    joinActive = false;
    IOLockUnlock(rxLock);
    if (was && core && bound) core->callPlatformFunction(ITL_NATIVE_LEAVE, false, nullptr, nullptr, nullptr, nullptr);
    return kIOReturnSuccess;
}

// ---- the rest of the join sequence the family's WCL layer drives (WCLJoinManager / WCLNetManager, 24H32) -----------------------
//
// WCLJoinManager::handleJoinRequest (0xffffff800220ac36) starts every join with a GET of 0x1ab WCL_LOW_LATENCY_INFO into a
// 4-byte buffer and aborts the join (setAssociateRequest fails) when the call fails or the dword is nonzero. Zero = no
// low-latency session is active, which is the only state this driver has. A null buffer is kIOReturnError (0xe00002bc).
IOReturn itlmt7925WifiInterface::getWCL_LOW_LATENCY_INFO(apple80211_low_latency_info *d)
{
    itlmtCall(ctl, 'S', 525);
    if (!d) return kIOReturnError;
    store<uint32_t>(d, 0, 0);
    return kIOReturnSuccess;
}

// 0x1be: WCL tells the driver how long to stay on the home channel and away between scan channels. The core's scan has its own
// fixed dwell; the request is accepted and its first dword traced (the layout is not otherwise determined).
IOReturn itlmt7925WifiInterface::setWCL_SET_SCAN_HOME_AWAY_TIME(scanHomeAndAwayTime *d)
{
    itlmtCall(ctl, 'S', 607);
    if (!d) return kIOReturnBadArgument;
    uint32_t w0 = 0, w1 = 0;
    memcpy(&w0, d, 4);
    memcpy(&w1, (const uint8_t *)d + 4, 4);
    if (homeAwayTraced++ < 4) itlmtTrace(ctl, "wcl:home/away words %x %x", w0, w1);
    return kIOReturnSuccess;
}

// 0x1eb WNM_OPS: BSS-transition / DMS configuration. No WNM feature is offered by the core, so nothing is configured.
IOReturn itlmt7925WifiInterface::setWCL_WNM_OPS(apple80211_wcl_wnm_config_t *d)
{
    itlmtCall(ctl, 'S', 628);
    if (!d) return kIOReturnError;
    return kIOReturnSuccess;
}

// 0x1b7 TRIGGER_CC: WCL asks the driver to re-run its country-code step after a failed join (the abort path of
// handleSendCandidateToDriver). The core's regulatory domain is fixed, so there is nothing to re-run.
IOReturn itlmt7925WifiInterface::setWCL_TRIGGER_CC(triggerCC *)
{
    itlmtCall(ctl, 'S', 602);
    return kIOReturnSuccess;
}

// 0x1bc LINK_UP_DONE: WCLNetManager::linkUp tells the driver the family finished its link-up work (BSS manager, neighbor
// cache, link-change event). Apple's driver uses it to start its own post-link services; the core has none to start.
IOReturn itlmt7925WifiInterface::setWCL_LINK_UP_DONE(void *)
{
    itlmtCall(ctl, 'S', 606);
    if (linkUpDoneTraced++ < 4) itlmtTrace(ctl, "wcl:link up done");
    return kIOReturnSuccess;
}

// 0x1c6 LINK_STATE_UPDATE (apple80211_wcl_update_link_state): +0 ether_addr bssid, +6 u8 link up, +7/+8 flags, +0xc u32 down
// reason. In Apple's driver it drives AppleBCMWLANNetAdapter::setLinkUp / setLinkDown. The core's link state already follows its
// own association (linkFromCore -> applyRadioLink), so this is accepted and recorded; the values are traced for the next round.
IOReturn itlmt7925WifiInterface::setWCL_LINK_STATE_UPDATE(apple80211_wcl_update_link_state *d)
{
    itlmtCall(ctl, 'S', 468);
    if (!d) return kIOReturnBadArgument;
    const uint8_t *b = (const uint8_t *)d;
    uint32_t reason = 0;
    memcpy(&reason, b + 0xc, 4);
    if (linkStateTraced++ < 8)
        itlmtTrace(ctl, "wcl:link state up=%u flags=%u/%u reason=%u radio=%u", b[6], b[7], b[8], reason, linkUp());
    return kIOReturnSuccess;
}

// The current BSS as a beacon message (AppleBCMWLANCore::getWCL_BSS_INFO builds it from the firmware's BSS info;
// 0xe00002bc while not associated). Here the core's target AP (captured from its beacon / probe response).
IOReturn itlmt7925WifiInterface::getWCL_BSS_INFO(apple80211_beacon_msg *d)
{
    itlmtCall(ctl, 'S', 526);
    if (!d) return kIOReturnBadArgument;
    ItlNativeStatus st;
    if (!queryStatus(&st) || st.state != ITL_NATIVE_UP) return kIOReturnError;
    buildBeacon((uint8_t *)d, st.bssid, st.channel, st.ssid, st.ssidLen, st.rssi, st.capability, st.beaconInterval, st.ie,
                st.ieLen, false);
    if (bssInfoTraced++ < 4) itlmtTrace(ctl, "wcl:bss info answered ch=%u ssidLen=%u ie=%u", st.channel, st.ssidLen, st.ieLen);
    return kIOReturnSuccess;
}

// 0x1cc WCL_EXTENDED_BSS_INFO (0x1e0 bytes, asked by WCLNetManager::setCurrentBSS right after 0x1b1; any failure there aborts the
// link-up and the family leaves the network itself - round 19 boot: `I:1b1 I:1cc I:1a9`).
// Layout from AppleBCMWLANNetAdapter::getExtendedBssInfo (0xffffff800155499c, 24H32) and its three helpers:
//   +0x00 apple80211_rate_set_data (0xbc): u32 version (left as the caller set it), u16 count at +4 (updateRateSetSync maps the
//         firmware's wl_rateset {u32 count, u8 rates[16]} with mapBcomRatesetToAppleRateset 0xffffff80016522bf: count capped at
//         16 there, 15 here as the array holds), entry i at +8 + 12 i = {u32 version (left alone), u32 (rate byte >> 1) & 0x3f
//         = Mb/s, u32 rate byte >> 7 = basic}
//   +0xbc apple80211_mcs_index_set_data (16): u32 version, +4 up to 10 bytes of the HT RX MCS bitmask (updateMCSSet 0xffffff8001554e72)
//   +0xcc apple80211_vht_mcs_index_set_data (8): u32 version, +4 u16 map, 2 bits per stream (IEEE VHT-MCS map), 0xffff = none
//   +0xd4 apple80211_he_mcs_index_set_data (8): u32 version, +4 u16 map, 2 bits per stream (IEEE HE-MCS map), 0xffff = none
//   +0xdc u8 MLO connection (only written when feature bit 0x73 is set; 0 here)
//   +0xdd 0x101 bytes: the firmware's "wpaie" iovar output as is (getAssociatedWPARSNIESync 0xffffff8001554ca6; the result is
//         ignored): the raw WPA/RSN information element, id and length included. Here the AP's RSN element (id 0x30) the join
//         was made against, else its WPA vendor element, or nothing.
// Rates come from the AP's Supported Rates / Extended Supported Rates, the MCS sets from the core's negotiated plan (all empty
// on the legacy 6 Mb/s path, where HT/VHT/HE are not in use).
IOReturn itlmt7925WifiInterface::getWCL_EXTENDED_BSS_INFO(apple80211_extended_bss_info *d)
{
    itlmtCall(ctl, 'S', 533);
    if (!d) return kIOReturnError;
    uint8_t *b = (uint8_t *)d;
    uint32_t ver[4];
    static const uint32_t verOff[4] = {0, 0xbc, 0xcc, 0xd4};
    for (int i = 0; i < 4; i++) memcpy(&ver[i], b + verOff[i], 4);
    bzero(d, 0x1e0);
    for (int i = 0; i < 4; i++) memcpy(b + verOff[i], &ver[i], 4);

    ItlNativeStatus st;
    bool have = queryStatus(&st) && st.state == ITL_NATIVE_UP;
    uint32_t nrates = 0, rsnLen = 0;
    if (have) {
        const uint8_t *ie = st.ie;
        const uint32_t n = st.ieLen < sizeof(st.ie) ? st.ieLen : (uint32_t)sizeof(st.ie);
        const uint8_t *wpa = nullptr;
        uint32_t wpaLen = 0;
        for (uint32_t p = 0; p + 2 <= n; p += 2 + ie[p + 1]) {
            const uint8_t id = ie[p], l = ie[p + 1];
            if (p + 2 + l > n) break;
            const uint8_t *v = ie + p + 2;
            if ((id == 1 || id == 50) && nrates < 15) {                              // Supported / Extended Supported Rates
                for (uint8_t k = 0; k < l && nrates < 15; k++, nrates++) {
                    const uint8_t r = v[k];
                    store<uint32_t>(b, 8 + 12 * nrates + 4, (r >> 1) & 0x3f);
                    store<uint32_t>(b, 8 + 12 * nrates + 8, (uint32_t)(r >> 7));
                }
            } else if (id == 0x30 && !rsnLen && l + 2u <= 0x101) {                   // RSN
                memcpy(b + 0xdd, ie + p, l + 2u);
                rsnLen = l + 2u;
            } else if (id == 0xdd && !wpa && l >= 4 && v[0] == 0x00 && v[1] == 0x50 && v[2] == 0xf2 && v[3] == 0x01 &&
                       l + 2u <= 0x101) {                                            // WPA vendor element
                wpa = ie + p;
                wpaLen = l + 2u;
            }
        }
        if (!rsnLen && wpa) {
            memcpy(b + 0xdd, wpa, wpaLen);
            rsnLen = wpaLen;
        }
        store<uint16_t>(b, 4, (uint16_t)nrates);
        if (st.fastActive) {
            memcpy(b + 0xbc + 4, st.htMcs, sizeof(st.htMcs));
            store<uint16_t>(b, 0xcc + 4, st.vhtMcs);
            store<uint16_t>(b, 0xd4 + 4, st.heMcs);
        } else {
            store<uint16_t>(b, 0xcc + 4, 0xffff);                                    // "none", as Apple's default
            store<uint16_t>(b, 0xd4 + 4, 0xffff);
        }
    }
    if (extBssTraced++ < 4)
        itlmtTrace(ctl, "wcl:extended bss info rates=%u rsn=%u fast=%u nss=%u ht=%02x vht=%04x he=%04x", nrates, rsnLen,
                   have ? st.fastActive : 0, have ? st.fastNss : 0, have ? st.htMcs[0] : 0, have ? st.vhtMcs : 0xffff,
                   have ? st.heMcs : 0xffff);
    return kIOReturnSuccess;
}

// 0x1f6 WCL_UPDATE_FAST_LANE (2 bytes, both the beacon's vtable+0x3a0 answer; setCurrentBSS fails when this SET fails). Fast lane
// is a QoS marking for a peer feature this driver does not offer; accepted and recorded.
IOReturn itlmt7925WifiInterface::setWCL_UPDATE_FAST_LANE(apple80211_fastlane *d)
{
    itlmtCall(ctl, 'S', 635);
    if (!d) return kIOReturnBadArgument;
    if (fastLaneTraced++ < 4) itlmtTrace(ctl, "wcl:fast lane %02x%02x", ((const uint8_t *)d)[0], ((const uint8_t *)d)[1]);
    return kIOReturnSuccess;
}

// 0x1b2 WCL_TRAFFIC_COUNTERS (0x38 bytes, WCLNetManager::linkUp; the result is not checked). The core keeps no per-AC counters.
IOReturn itlmt7925WifiInterface::getWCL_TRAFFIC_COUNTERS(apple80211_wcl_traffic_counters *d)
{
    itlmtCall(ctl, 'S', 527);
    if (!d) return kIOReturnError;
    bzero(d, 0x38);
    return kIOReturnSuccess;
}

// Link-path SETs that configure features the core does not have (power-save mode, ARP-mode, QoS parameters for the protect-IP
// window, roam lock); each is accepted and only recorded, as for 0x1be.
IOReturn itlmt7925WifiInterface::setPM_MODE(apple80211_pm_mode *) { itlmtCall(ctl, 'S', 587); return kIOReturnSuccess; }
IOReturn itlmt7925WifiInterface::setWCL_ARP_MODE(apple80211_wcl_arp_mode *) { itlmtCall(ctl, 'S', 600); return kIOReturnSuccess; }
IOReturn itlmt7925WifiInterface::setWCL_QOS_PARAMS(apple80211_wcl_qos_params *) { itlmtCall(ctl, 'S', 605); return kIOReturnSuccess; }
IOReturn itlmt7925WifiInterface::setWCL_SET_ROAM_LOCK(apple80211_set_roam_lock *) { itlmtCall(ctl, 'S', 594); return kIOReturnSuccess; }

void itlmt7925WifiInterface::deliverScanResults()
{
    ItlNativeNets n;
    bzero(&n, sizeof(n));
    n.version = 1;
    n.max = ITL_NATIVE_AP_MAX;
    n.aps = snap;
    uint32_t posted = 0, seen = 0;
    if (snap && core && core->callPlatformFunction(ITL_NATIVE_NETS, false, &n, nullptr, nullptr, nullptr) == kIOReturnSuccess) {
        IOLockLock(rxLock);
        uint8_t wantLen = scanSsidLen;
        char want[32];
        memcpy(want, scanSsid, sizeof(want));
        IOLockUnlock(rxLock);
        uint8_t msg[kBeaconHeader + ITL_NATIVE_IE_MAX];
        seen = n.count;
        for (uint32_t i = 0; i < n.count; i++) {
            const ItlNativeAp &a = snap[i];
            if (a.ageMs > 60000 || !a.channel) continue;                           // not heard in the last minute
            if (wantLen && (a.ssidLen != wantLen || memcmp(a.ssid, want, wantLen))) continue;
            buildBeacon(msg, a.bssid, a.channel, a.ssid, a.ssidLen, a.rssi, a.capability, a.beaconInterval, a.ie, a.ieLen,
                        a.probeResponse);
            postEvent(kEventScanResult, msg, kBeaconHeader + a.ieLen);
            posted++;
        }
    }
    uint32_t status = 0;
    postEvent(kEventScanDone, &status, sizeof(status));
    if (scanTraced++ < 8) itlmtTrace(ctl, "scan:delivered %u of %u", posted, seen);
}

// Association outcome (0x4e, 0xd3, then on success 0xd5). On failure the ieee status is 1 (unspecified failure); the codes Apple
// derives from the firmware event are not determined.
void itlmt7925WifiInterface::finishJoin(const ItlNativeStatus &st, bool ok)
{
    // The family's WCLNetManager only leaves LINK_DOWN on a link status indication (0xd8, byte +6 != 0): its LINK_UP event runs
    // firstLinkUp -> linkUp -> updateBss (GET 0x1b1 WCL_BSS_INFO -> current BSS, which is what GET SSID/BSSID/CHANNEL answer from).
    // It has to precede the join events: WCLNetManager's CONNECT_COMPLETE (from 0xd5) is only accepted after LINK_UP.
    if (ok) {
        IOLockLock(rxLock);
        memcpy(nmBssid, st.bssid, 6);
        nmLinkUp = true;
        nmEverJoined = true;
        linkDownPending = false;
        IOLockUnlock(rxLock);
        postLinkStatus(st.bssid, true, 0);
    }
    uint32_t assoc[2] = {ok ? 0u : 1u, 0};
    postEvent(kEventAssoc, assoc, sizeof(assoc));
    uint8_t join[0x1c];
    bzero(join, sizeof(join));
    store<uint16_t>(join, 0, ok ? 0 : 1);
    memcpy(join + 5, st.bssid, 6);
    store<uint32_t>(join, 0x14, assoc[0]);
    postEvent(kEventJoin, join, sizeof(join));
    if (ok) {
        // apple80211_first_beacon_event (WCLJoinManager::firstBeaconEventHandler wants exactly 0x14 bytes;
        // WCLJoinRequest::updateFirstBeaconEvent): u16 status, u16 ieee status (both 0 = success), +4 ether_addr compared
        // with the candidate's, +0xc a u64 kept with the candidate (not determined, left zero).
        uint8_t first[0x14];
        bzero(first, sizeof(first));
        memcpy(first + 4, st.bssid, 6);
        postEvent(kEventFirstBeacon, first, sizeof(first));
        uint8_t done[0xa4];
        bzero(done, sizeof(done));
        memcpy(done + 4, st.bssid, 6);
        postEvent(kEventConnect, done, sizeof(done));
    }
    itlmtTrace(ctl, "assoc:result ok=%u stage=%u", ok, st.failStage);
}

// Event 0xd8 (WCLNetManager::linkStatusInd): +0 ether_addr bssid, +6 u8 link up (0 = down), +8 u32 down reason
// (WCLNetManager::linkDownInd switches on it; 1 is the plain "link lost" answer: no debounce or recreate path, the family just
// issues its leave-network command, which the driver's 0x1a9 handler turns into a core leave).
void itlmt7925WifiInterface::postLinkStatus(const uint8_t *bssid, bool up, uint32_t reason)
{
    uint8_t p[0x10];
    bzero(p, sizeof(p));
    memcpy(p, bssid, 6);
    p[6] = up ? 1 : 0;
    if (!up) store<uint32_t>(p, 8, reason);
    postEvent(kEventLinkStatus, p, sizeof(p));
    if (linkStatusTraced++ < 8) itlmtTrace(ctl, "wcl:link status posted up=%u reason=%u", up, reason);
}

// Runs every 10 ms tick on the interface's work queue; asks the core every 100 ms while a scan or join is outstanding.
void itlmt7925WifiInterface::pollControl()
{
    if (!bound || !core) return;
    IOLockLock(rxLock);
    bool sa = scanActive, ja = joinActive, imm = scanImmediate, down = false;
    uint8_t downBssid[6];
    if (linkDownPending) {
        linkDownPending = false;
        if (nmLinkUp) { nmLinkUp = false; down = true; memcpy(downBssid, nmBssid, 6); }
    }
    IOLockUnlock(rxLock);
    if (down) postLinkStatus(downBssid, false, 1);
    // The core can restore the link without being asked (a fast-mode ladder step, or the AP dropped us and the supervisor
    // rejoined). The family was told the link went down, so it has to be told again, with the sequence a requested join uses.
    if (!ja && (++reannounceTicks % 50) == 0) {
        IOLockLock(rxLock);
        bool want = nmEverJoined && radioUp && !nmLinkUp && !linkDownPending;
        IOLockUnlock(rxLock);
        ItlNativeStatus rs;
        if (want && queryStatus(&rs) && rs.state == ITL_NATIVE_UP && rs.channel) {
            if (reannounceTraced++ < 4) itlmtTrace(ctl, "wcl:link restored by core, announcing again ch=%u", rs.channel);
            finishJoin(rs, true);
        }
    }
    if (!sa && !ja) return;
    bool poll = imm || (++controlTicks % 10) == 0;
    if (!poll) return;
    ItlNativeStatus st;
    if (!queryStatus(&st)) return;
    if (sa) {
        IOLockLock(rxLock);
        bool done = scanImmediate || (st.scanGen != scanGenAtReq && !st.scanBusy) || (scanTicks += 10) >= kScanTimeoutTicks;
        if (done) { scanActive = false; scanImmediate = false; }
        IOLockUnlock(rxLock);
        if (done) deliverScanResults();
    }
    if (ja) {
        IOLockLock(rxLock);
        bool mine = st.joinSeq == joinSeq;
        bool timeout = (joinTicks += 10) >= kJoinTimeoutTicks;
        bool up = mine && st.state == ITL_NATIVE_UP, failed = mine && st.state == ITL_NATIVE_FAILED;
        if (up || failed || timeout) joinActive = false;
        IOLockUnlock(rxLock);
        if (up) finishJoin(st, true);
        else if (failed || timeout) {
            if (timeout && !failed) core->callPlatformFunction(ITL_NATIVE_LEAVE, false, nullptr, nullptr, nullptr, nullptr);
            finishJoin(st, false);
        }
    }
}

#define ITL_IFACE_DEFS
#include "itlmt7925_iface_stubs.inc"
#undef ITL_IFACE_DEFS
