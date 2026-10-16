// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925WifiInterface - native Wi-Fi interface (interface ABI macOS 26.7.1 / 25G241; originally ported from 15.8.1 / 24H32).
//
// Shape taken from Apple's AppleBCMWLANSkywalkInterface (docs/IO80211-ABI-2.md, "Native stub, stage 2"; 25G241 deltas in
// docs/IO80211-ABI.md, "Tahoe port"): a subclass of the Family's IO80211InfraProtocol (0x130 bytes on 25G241, 199 pure
// get/set handlers + setMacAddress), created by the controller, attached to it, started with an initialised RegistrationInfo,
// which registers [TxSubmission x4, TxCompletion, RxCompletion] and the packet pool with registerInfraEthernetInterface.
#pragma once
#include "../itlmt7925/io80211/IO80211Controller.h"
#include "../itlmt7925/io80211/IO80211WorkQueue.h"
#include "../itlmt7925/io80211/IO80211InfraProtocol.h"
#include "skywalk_min.h"
#include "../itlmt7925/itl_native_bridge.h"
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOLocks.h>


// Appends "; <text>" to the registry property "itlmt_native_trace" of `e` (cap 480 bytes). IOLog output of third-party kexts was
// not found in the collected logs of stage A/B, a registry property survives and is read with `ioreg -l`.
void itlmtTrace(IORegistryEntry *e, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

// Call recorder: one table of (kind, id, up to 3 caller addresses) -> count, published as the registry property
// "itlmt_native_calls" of `e` whenever an entry is new or its count reaches a power of two, so it survives panic-free runs and
// costs nothing on the hot path. kinds: 'I' controller isCommandProhibited(cmd) + 3 return addresses (kernel-slide corrected,
// decode against the dumps), 'S' interface handler stub (id = vtable slot), 'C' controller handler (id: see itlmt7925_wifi.cpp),
// 'U' newUserClient (id = type), 'B' BSD command. Init/free are called by the controller.
void itlmtCallInit();
void itlmtCallFree();
void itlmtCall(IORegistryEntry *e, char kind, uint32_t id, const uint32_t *callers = nullptr);
// Static (slide-free) low 32 bits of the three return addresses above the caller's frame; zeros where the walk is not safe.
void itlmtCallers(uint32_t out[3], uintptr_t fp);

class itlmt7925WifiInterface : public IO80211InfraProtocol {
    OSDeclareDefaultStructors(itlmt7925WifiInterface)

public:
    static const uint32_t kNumTx = 4;       // AppleBCMWLANSkywalkInterface::withProvider fixes numTx = 4 (ACs 0..3)

    // Creates the object: alloc, init(), role and id (initWithProviderAndParameters), attach(controller). Not started yet.
    static itlmt7925WifiInterface *withController(IO80211Controller *controller, uint32_t ifId, uint32_t role);

    // The equivalent of AppleBCMWLANSkywalkInterface::start(core, RegistrationInfo*) (slot 657 there, not a Family virtual).
    bool startWithInfo(IO80211Controller *controller, IOSkywalkEthernetInterface::RegistrationInfo *info);

    bool init() override;
    void free() override;
    void stop(IOService *provider) override;
    IOReturn enable(uint32_t options) override;
    IOReturn disable(uint32_t options) override;
    void setInterfaceEnable(bool enabled) override;
    // 25G241 moved this from the protocol handler table (0x1c6, pure) to a base-implemented virtual of IO80211InfraInterface
    // (slot 468); Apple's base calls setLinkState itself, this override records the update and leaves the core's radio link
    // as the only driver of setLinkState (applyRadioLink).
    IOReturn setWCL_LINK_STATE_UPDATE(apple80211_wcl_update_link_state *d) override;
    uint32_t getHardwareAssists() override;
    IOReturn processBSDCommand(__ifnet *netif, uint32_t command, void *data) override;
    IOReturn newUserClient(task_t task, void *securityID, UInt32 type, OSDictionary *properties, IOUserClient **handler) override;
    using IO80211InfraProtocol::newUserClient;

    // Accessors the Family calls on its interface (IO80211SkywalkInterface slots 418-439; AppleBCMWLANSkywalkInterface overrides them)
    CCLogStream *getLogger() const override;
    IO80211Controller *getController() override;
    uint32_t getTxQueueDepth() override;
    uint32_t getRxQueueCapacity() override;
    IOSkywalkPacketQueue *getMultiCastQueue() override;
    uint16_t getTxHeadroom() override;
    IOSkywalkRxCompletionQueue *getRxCompQueue() override;
    IOSkywalkTxCompletionQueue *getTxCompQueue() override;
    IOSkywalkTxSubmissionQueue *getTxSubQueue(apple80211_wme_ac ac) override;
    IOSkywalkPacketBufferPool *getTxPacketPool() override;
    IOSkywalkPacketBufferPool *getRxPacketPool() override;
    IOReturn enableDatapath() override;
    IOReturn disableDatapath() override;
    uint8_t getNumTxQueues() override;
    uint32_t submitPackets(IOSkywalkPacket *const *, uint32_t);
    static void receiveFromCore(OSObject *, const uint8_t *, uint32_t);
    static void linkFromCore(OSObject *, bool, uint64_t);
    static IOReturn applyRadioLink(OSObject *, void *, void *, void *, void *);
    static void datapathTick(OSObject *, IOTimerEventSource *);

#define ITL_IFACE_DECLS
#include "itlmt7925_iface_stubs.inc"
#undef ITL_IFACE_DECLS

private:
    void drainDatapath();
    bool linkUp();
    // scan / join (stage 3): requests are handed to the core through ITL_NATIVE_*; results are posted from the datapath tick
    void pollControl();
    void deliverScanResults();
    void finishJoin(const ItlNativeStatus &st, bool ok);
    void postLinkStatus(const uint8_t *bssid, bool up, uint32_t reason);
    void postEvent(uint32_t code, void *data, size_t length);
    bool queryStatus(ItlNativeStatus *st);
    ItlNativeAp *snap = nullptr;            // ITL_NATIVE_AP_MAX entries: scratch for ITL_NATIVE_NETS (tick thread only)
    bool scanActive = false, scanImmediate = false, joinActive = false;
    uint32_t scanGenAtReq = 0, scanTicks = 0, joinSeq = 0, joinTicks = 0, controlTicks = 0, scanTraced = 0;
    uint32_t homeAwayTraced = 0, linkUpDoneTraced = 0, linkStateTraced = 0, bssInfoTraced = 0, linkStatusTraced = 0,
             extBssTraced = 0, fastLaneTraced = 0;
    // the family's link state as the driver told it (event 0xd8): set when the join completes, cleared on a link loss
    bool nmLinkUp = false, linkDownPending = false;
    bool nmEverJoined = false;              // a join of the family's asking completed: the core may later restore the link by itself
    uint32_t reannounceTicks = 0, reannounceTraced = 0;
    uint8_t nmBssid[6] = {};
    uint8_t scanSsidLen = 0;
    char scanSsid[32] = {};
    uint64_t osFeatureFlags = 0;            // setOS_FEATURE_FLAGS payload (qword at +0), kept as Apple's core does
    IOService *core = nullptr;
    IOTimerEventSource *dpTimer = nullptr;
    IOLock *rxLock = nullptr;
    struct RxFrame { uint32_t length; uint8_t bytes[1600]; };
    // Measured 2026-10-14: a 64-frame ring drained 32 frames per 10 ms tick dropped 9.8 % of received frames (all ring-full) and
    // collapsed TCP to about 0.5 Mb/s. 512 frames, up to 128 per 2 ms tick; the pool (0x1300 packets) and RX queue (0x400) hold that.
    static const uint32_t kRxRing = 512, kRxBatch = 128, kTickMs = 2;
    RxFrame *rxRing = nullptr;
    uint32_t rxHead = 0, rxTail = 0;
    uint32_t rxRingFull = 0, rxOversize = 0, rxPeak = 0;       // reasons behind rxDropped (guarded by rxLock)
    IOSkywalkPacket *pendingTx[512] = {};
    uint32_t pendingCount = 0;
    bool dpEnabled = false, bound = false, radioUp = false;
    bool firstTxTrace = false, firstRxTrace = false, firstCompletionTrace = false;
    uint32_t rxFailureTraceCount = 0;
    bool assistsTraced = false;
    bool mediaTraced[2] = {};
    IOReturn lastMediaResult[2] = {kIOReturnSuccess, kIOReturnSuccess};
    uint32_t mediaQueryCount = 0;
    uint8_t txScratch[1600] = {};
    uint32_t txChecksumFailures = 0;
    uint64_t radioSpeed = 0;
    uint32_t txSent = 0, txDropped = 0, txStalled = 0, txCompleted = 0;
    uint32_t rxReceived = 0, rxDropped = 0, rxDelivered = 0, ticks = 0;
    bool createPoolAndQueues();
    void destroyPoolAndQueues();

    IO80211Controller *ctl = nullptr;           // not retained: the controller owns the interface's lifetime
    IOSkywalkPacketBufferPool *pool = nullptr;
    IOSkywalkTxSubmissionQueue *txSub[kNumTx] = {};
    IOSkywalkTxCompletionQueue *txComp = nullptr;
    IOSkywalkRxCompletionQueue *rxComp = nullptr;
    IOSkywalkRxSubmissionQueue *rxSub = nullptr;   // common Rx submission queue (Apple creates it before any interface)
    IOWorkLoop *queued = nullptr;           // work queue the event sources were added to (retained)
    uint16_t headroom = 0;
};
