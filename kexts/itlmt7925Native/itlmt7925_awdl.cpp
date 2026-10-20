// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AWDL front end implementation (see itlmt7925_awdl.h). Phase 2: the virtual interface exists and is registered; no RF work
// yet (phases 3-5 of docs/ROADMAP-AWDL.md: channel slicing, action frames, data path).
//
// Creation order (docs/ROADMAP-AWDL.md §9.5): init -> attach -> deferBSDAttach(true) -> start(ctl) -> register the ifnet ->
// registerService + setRunningState(false) -> setAwdlInterface -> deferBSDAttach(false). The start(ctl) call is mandatory:
// it is what stores the controller at ivars+0x30 (getController), which IO80211VirtualInterface::attachToBpf dereferences
// from the BSD client's start - skipping it panics on the first BSD attach (Kernel-2026-10-17-163303/165042).
#include "itlmt7925_awdl.h"
#include "itlmt7925_iface.h"

#include "../itlmt7925/io80211/IO80211AWDLProtocol.h"
#include <IOKit/IOLib.h>
#include <pexpert/pexpert.h>
#include <string.h>

// -----------------------------------------------------------------------------------------------------------------------
// The virtual interface: IO80211VirtualInterface with the AWDL BSD name prefix.
//
// Apple's Broadcom path instantiates AppleBCMWLANProximityInterface (IO80211AWDLProtocol : IO80211VirtualInterface) whose
// getBSDNamePrefix returns "awdl" and whose AWDL protocol slots talk to firmware. The Family's generic
// IO80211VirtualInterface would take the default prefix ("en", IOSkywalkEthernetInterface::getBSDNamePrefix) and could never
// show up as awdl0, so this subclass overrides the prefix and leaves everything else to the Family (init, attach, the ifnet
// registration and - later - createPeerManager -> IO80211AWDLPeerManager -> IO80211P2PSupervisor).
// -----------------------------------------------------------------------------------------------------------------------
// Base is the Family's AWDL protocol class (not plain IO80211VirtualInterface): the AWDL ioctl dispatchers cast the
// interface to IO80211AWDLProtocol (apple80211setCOMPANION_SKYWALK_IF_CREATE at 0xffffff800226a32f: safeMetaCast
// against IO80211AWDLProtocol::gMetaClass, then the slot-562 call) and the AWDL peer manager drives the protocol
// virtuals. Without the subclass link every AWDL ioctl answers 0xe082280e before reaching this driver.
class itlmt7925AwdlInterface : public IO80211AWDLProtocol {
    OSDeclareDefaultStructors(itlmt7925AwdlInterface)

public:
    // IOSkywalkNetworkInterface::getBSDNamePrefix (slot 319): the BSD name the Family builds is <prefix><unit>.
    const char *getBSDNamePrefix() override;
    // Slot 490 is ___cxa_pure_virtual in Apple's binary and in IO80211AWDLProtocol (no override anywhere in the Family - the
    // Broadcom subclass implements it). Nothing on this path calls it; implemented so the subclass is concrete.
    void _unnamedPure490() override;
    // ---------------------------------------------------------------------------------------------------------------
    // IO80211AWDLProtocol (slots 507..569): the Family's AWDL ioctls and the AWDL peer manager call these. Phase 3
    // groundwork: each logs its first calls and answers kIOReturnUnsupported, so the Family's ioctls fail cleanly
    // instead of hitting an unimplemented pure virtual. The companion create (562) is in the .cpp.
    IOReturn awdlProto(const char *name);
    // Phase 3 step 2 - the configure handshake. IO80211AWDLPeerManager::configure aborts on the first slot that answers
    // unsupported: the trace on 2026-10-19 21:27 shows "configure Unable to set BSSID ret e00002c7" -> "doEnable:2839
    // ERROR: cannot configure AWDL after enabling interface" -> AWDL disabled, i.e. slot 540 (setAWDL_BSSID) alone kept the
    // whole stack down. awdlAccept() answers success and traces the slot; the values whose layout is public (the four AWDL
    // structs in IOKit/80211/apple80211_ioctl.h) are stored/printed as well. The configure sequence is only a parameter
    // handshake - the RF work (channel slicing, PSF frames, peer table) is what follows it.
    IOReturn awdlAccept(const char *name);
    /* 507 */ IOReturn getSSID(apple80211_ssid_data*a1) override { return awdlProto("getSSID"); }
    /* 508 */ IOReturn getCHANNEL(apple80211_channel_data*a1) override { return awdlProto("getCHANNEL"); }
    /* 509 */ IOReturn getBSSID(apple80211_bssid_data*a1) override { return awdlProto("getBSSID"); }
    /* 510 */ IOReturn getSTATE(apple80211_state_data*a1) override { return awdlProto("getSTATE"); }
    /* 511 */ IOReturn getAWDL_SYNC_PARAMS(apple80211_awdl_sync_params*a1) override { return awdlProto("getAWDL_SYNC_PARAMS"); }
    /* 512 */ IOReturn getAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled*a1) override;
    /* 513 */ IOReturn getAWDL_EXTENSION_STATE_MACHINE_PARAMETERS(apple80211_awdl_extension_state_machine_parameter*a1) override { return awdlProto("getAWDL_EXTENSION_STATE_MACHINE_PARAMETERS"); }
    /* 514 */ IOReturn getAWDL_ELECTION_ID(apple80211_awdl_election_id*a1) override { return awdlProto("getAWDL_ELECTION_ID"); }
    /* 515 */ IOReturn getAWDL_ELECTION_METRIC(apple80211_awdl_election_metric*a1) override { return awdlProto("getAWDL_ELECTION_METRIC"); }
    /* 516 */ IOReturn getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE(apple80211_awdl_sync_channel_sequence*a1) override { return awdlProto("getAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE"); }
    /* 517 */ IOReturn getPEER_CACHE_MAXIMUM_SIZE(apple80211_peer_cache_maximum_size*a1) override { return awdlProto("getPEER_CACHE_MAXIMUM_SIZE"); }
    /* 518 */ IOReturn getAWDL_MASTER_CHANNEL(apple80211_awdl_master_channel*a1) override { return awdlProto("getAWDL_MASTER_CHANNEL"); }
    /* 519 */ IOReturn getAWDL_SYNC_STATE(apple80211_awdl_sync_state*a1) override { return awdlProto("getAWDL_SYNC_STATE"); }
    /* 520 */ IOReturn getAWDL_ELECTION_RSSI_THRESHOLDS(apple80211_awdl_election_rssi_thresholds*a1) override { return awdlProto("getAWDL_ELECTION_RSSI_THRESHOLDS"); }
    /* 521 */ IOReturn getAWDL_PRESENCE_MODE(apple80211_awdl_presence_mode*a1) override { return awdlProto("getAWDL_PRESENCE_MODE"); }
    /* 522 */ IOReturn getAWDL_ELECTION_PARAMS(apple80211_awdl_election_params*a1) override { return awdlProto("getAWDL_ELECTION_PARAMS"); }
    /* 523 */ IOReturn getAWDL_DEVICE_CAPABILITIES(apple80211_awdl_device_capabilities*a1) override { return awdlProto("getAWDL_DEVICE_CAPABILITIES"); }
    /* 524 */ IOReturn getAWDL_SECONDARY_MASTER_CHANNEL(apple80211_awdl_secondary_master_channel*a1) override { return awdlProto("getAWDL_SECONDARY_MASTER_CHANNEL"); }
    /* 525 */ IOReturn getAWDL_AF_TX_MODE(apple80211_awdl_af_tx_mode*a1) override { return awdlProto("getAWDL_AF_TX_MODE"); }
    /* 526 */ IOReturn getAWDL_MIN_RATE(apple80211_awdl_min_rate*a1) override { return awdlProto("getAWDL_MIN_RATE"); }
    /* 527 */ IOReturn getAWDL_ENCRYPTION_TYPE(apple80211_encrypt*a1) override { return awdlProto("getAWDL_ENCRYPTION_TYPE"); }
    /* 528 */ IOReturn getAWDL_TXCAL_PERIOD(apple80211_awdl_txcal_period*a1) override { return awdlProto("getAWDL_TXCAL_PERIOD"); }
    /* 529 */ IOReturn getAWDL_DEV_STATS(apple80211_awdl_dev_stats*a1) override { return awdlProto("getAWDL_DEV_STATS"); }
    /* 530 */ IOReturn getAWDL_DFSP_CONFIG(apple80211_awdl_dfsp_config*a1) override { return awdlProto("getAWDL_DFSP_CONFIG"); }
    /* 531 */ IOReturn getAWDL_CCA(apple80211_awdl_cca*a1) override { return awdlProto("getAWDL_CCA"); }
    /* 532 */ IOReturn getAWDL_AF_SECONDARY_PAYLOAD_CAPABILITIES(apple80211_awdl_cap*a1) override { return awdlProto("getAWDL_AF_SECONDARY_PAYLOAD_CAPABILITIES"); }
    /* 533 */ IOReturn getLLW_PARAMS(apple80211_llw_params*a1) override { return awdlProto("getLLW_PARAMS"); }
    /* 534 */ IOReturn setSSID(apple80211_ssid_data*a1) override { return awdlAccept("setSSID"); }
    /* 535 */ IOReturn setCHANNEL(apple80211_channel_data*a1) override { return awdlAccept("setCHANNEL"); }
    /* 536 */ IOReturn setAWDL_SYNC_PARAMS(apple80211_awdl_sync_params*a1) override { return awdlAccept("setAWDL_SYNC_PARAMS"); }
    /* 537 */ IOReturn setAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled*a1) override;
    /* 538 */ IOReturn setAWDL_EXTENSION_STATE_MACHINE_PARAMETERS(apple80211_awdl_extension_state_machine_parameter*a1) override { return awdlAccept("setAWDL_EXTENSION_STATE_MACHINE_PARAMETERS"); }
    /* 539 */ IOReturn setAWDL_ELECTION_ID(apple80211_awdl_election_id*a1) override { return awdlAccept("setAWDL_ELECTION_ID"); }
    /* 540 */ IOReturn setAWDL_BSSID(apple80211_awdl_bssid*a1) override;
    /* 541 */ IOReturn setAWDL_ELECTION_METRIC(apple80211_awdl_election_metric*a1) override;
    /* 542 */ IOReturn setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE(apple80211_awdl_sync_channel_sequence*a1) override { return awdlAccept("setAWDL_SYNCHRONIZATION_CHANNEL_SEQUENCE"); }
    /* 543 */ IOReturn setAWDL_MASTER_CHANNEL(apple80211_awdl_master_channel*a1) override { return awdlAccept("setAWDL_MASTER_CHANNEL"); }
    /* 544 */ IOReturn setAWDL_SYNC_STATE(apple80211_awdl_sync_state*a1) override { return awdlAccept("setAWDL_SYNC_STATE"); }
    /* 545 */ IOReturn setAWDL_ELECTION_RSSI_THRESHOLDS(apple80211_awdl_election_rssi_thresholds*a1) override { return awdlAccept("setAWDL_ELECTION_RSSI_THRESHOLDS"); }
    /* 546 */ IOReturn setAWDL_PRESENCE_MODE(apple80211_awdl_presence_mode*a1) override { return awdlAccept("setAWDL_PRESENCE_MODE"); }
    /* 547 */ IOReturn setPEER_CACHE_CONTROL(apple80211_peer_cache_control*a1) override { return awdlAccept("setPEER_CACHE_CONTROL"); }
    /* 548 */ IOReturn setAWDL_OOB_REQUEST(apple80211_awdl_oob_request*a1) override { return awdlProto("setAWDL_OOB_REQUEST"); }
    /* 549 */ IOReturn setAWDL_SYNC_FRAME_TEMPLATE(apple80211_awdl_sync_frame_template*a1) override;
    /* 550 */ IOReturn setAWDL_ELECTION_PARAMS(apple80211_awdl_election_params*a1) override { return awdlAccept("setAWDL_ELECTION_PARAMS"); }
    /* 551 */ IOReturn setAWDL_PEER_TRAFFIC_REGISTRATION(apple80211_awdl_peer_traffic_registration*a1) override;
    /* 552 */ IOReturn setAWDL_SECONDARY_MASTER_CHANNEL(apple80211_awdl_secondary_master_channel*a1) override { return awdlAccept("setAWDL_SECONDARY_MASTER_CHANNEL"); }
    /* 553 */ IOReturn setAWDL_AF_TX_MODE(apple80211_awdl_af_tx_mode*a1) override { return awdlAccept("setAWDL_AF_TX_MODE"); }
    /* 554 */ IOReturn setAWDL_MIN_RATE(apple80211_awdl_min_rate*a1) override { return awdlAccept("setAWDL_MIN_RATE"); }
    /* 555 */ IOReturn setAWDL_ENCRYPTION_KEYS(apple80211_key*a1) override { return awdlAccept("setAWDL_ENCRYPTION_KEYS"); }
    /* 556 */ IOReturn setAWDL_ENCRYPTION_TYPE(apple80211_encrypt*a1) override { return awdlAccept("setAWDL_ENCRYPTION_TYPE"); }
    /* 557 */ IOReturn setAWDL_OOB_AUTO_REQUEST(apple80211_awdl_oob_request*a1) override { return awdlProto("setAWDL_OOB_AUTO_REQUEST"); }
    /* 558 */ IOReturn setAWDL_TXCAL_PERIOD(apple80211_awdl_txcal_period*a1) override { return awdlAccept("setAWDL_TXCAL_PERIOD"); }
    /* 559 */ IOReturn setAWDL_AWDL_ADVERTISERS(awdl_peer_advert_add*a1) override { return awdlAccept("setAWDL_AWDL_ADVERTISERS"); }
    /* 560 */ IOReturn setAWDL_DFSP_CONFIG(apple80211_awdl_dfsp_config*a1) override { return awdlAccept("setAWDL_DFSP_CONFIG"); }
    /* 561 */ IOReturn setAWDL_DFSP_UCSA_CONFIG(apple80211_awdl_dfsp_ucsa_config*a1) override { return awdlAccept("setAWDL_DFSP_UCSA_CONFIG"); }
    /* 562 */ IOReturn setCOMPANION_SKYWALK_IF_CREATE(apple80211_companion_skywalk_if_create*a1) override;
    /* 563 */ IOReturn setAWDL_OOB_SEC_PAYLOAD_REQUEST(apple80211_awdl_af_sec_payload_request*a1) override { return awdlProto("setAWDL_OOB_SEC_PAYLOAD_REQUEST"); }
    /* 564 */ IOReturn setLLW_PARAMS(apple80211_llw_params*a1) override { return awdlProto("setLLW_PARAMS"); }
    /* 565 */ IOReturn setTX_RATE(apple80211_tx_rate*a1) override { return awdlAccept("setTX_RATE"); }
    /* 566 */ IOReturn setP2P_COEX_PROTECTION(apple80211_p2p_coex_protection*a1) override { return awdlAccept("setP2P_COEX_PROTECTION"); }
    /* 567 */ IOReturn setPSF_DWELL(apple80211_awdl_psf_dwell_params*a1) override { return awdlAccept("setPSF_DWELL"); }
    /* 568 */ IOReturn setAWDL_CONFIG(apple80211_awdl_config_request*a1) override { return awdlAccept("setAWDL_CONFIG"); }
    /* 569 */ IOReturn setAWDL_RTG_PEER_STATS_CONFIG(apple80211_rtg_peer_stats_cfg*a1) override { return awdlAccept("setAWDL_RTG_PEER_STATS_CONFIG"); }

    // Phase 3, step 2: the core's link thread transmits the PSF frame (ROC on the AWDL channel + a management TX). The core
    // service pointer comes from the vif-create handler, which runs in the infrastructure interface that owns it.
    void setNativeCore(IOService *c) { coreDev = c; }

    // Creates the pool and the (three) queues and registers the ifnet from a RegistrationInfo filled like
    // AppleBCMWLANCore::createProxInterface fills it. Keeps the objects for the interface's lifetime.
    IOReturn registerAwdlInterface(const uint8_t *mac);
    void freeAwdlRegistration();

private:
    uint32_t awdlProtoLogged = 0;              // trace budget for the AWDL protocol stubs
    uint32_t awdlAccepted = 0;                 // trace budget for the accepted (configure-handshake) slots
    uint32_t awdlSyncEnabled = 0;              // last setAWDL_SYNC_ENABLED value, answered back by getAWDL_SYNC_ENABLED
    uint8_t awdlBssid[6] = {};                 // last setAWDL_BSSID bytes (traced only: the layout is not public)
    uint32_t awdlElectionMetric = 0;           // last setAWDL_ELECTION_METRIC
    uint32_t awdlSyncFrameLen = 0;             // last setAWDL_SYNC_FRAME_TEMPLATE payload_len (phase 4: the PSF frame)
    uint32_t awdlSyncTxLogged = 0;             // trace budget for the core handoff
    IOService *coreDev = nullptr;              // the core service (itlmt-native-awdl-sync-v1)
    IOSkywalkPacketBufferPool *awdlPool = nullptr;
    IOSkywalkPacketQueue *awdlQueues[3] = {};
};

#undef super
#define super IO80211AWDLProtocol
OSDefineMetaClassAndStructors(itlmt7925AwdlInterface, IO80211AWDLProtocol)

const char *itlmt7925AwdlInterface::getBSDNamePrefix() { return "awdl"; }
void itlmt7925AwdlInterface::_unnamedPure490() {}

// The AWDL protocol slots (507..569) answer unsupported until the real implementation (channel sequence, PSF frames, peer
// table - phases 3/4). The trace goes through the controller's itlmt_native_trace ring (mirrored to NVRAM with
// itlmt_native_nvtrace=1): IOLog from this kext does not reach the unified log on this machine, so NVRAM/ioreg is the only
// way to see which slots the Family and the AWDL peer manager actually call, in what order.
IOReturn itlmt7925AwdlInterface::awdlProto(const char *name)
{
    if (awdlProtoLogged < 96) {
        awdlProtoLogged++;
        itlmtTrace(getController(), "awdl:proto %s", name);
    }
    return kIOReturnUnsupported;
}

// -----------------------------------------------------------------------------------------------------------------------
// Phase 3 step 2: the configure handshake (see the class comment). The peer manager hands the driver its parameters through
// these slots and aborts the whole configure sequence on the first unsupported answer, so they accept (and the four values
// whose layout is public are stored/printed). This is deliberately not RF work: no channel is switched and no frame is
// sent yet - it is what lets configure() finish so the next missing piece (the channel sequence / PSF path) becomes visible
// in the trace.
// -----------------------------------------------------------------------------------------------------------------------
IOReturn itlmt7925AwdlInterface::awdlAccept(const char *name)
{
    if (awdlAccepted < 96) {
        awdlAccepted++;
        itlmtTrace(getController(), "awdl:accept %s", name);
    }
    return kIOReturnSuccess;
}

// apple80211_awdl_sync_enabled { u32 version; u32 unk1; u32 enabled } (IOKit/80211/apple80211_ioctl.h, packed).
IOReturn itlmt7925AwdlInterface::setAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled *a1)
{
    awdlSyncEnabled = a1 ? *(const uint32_t *)((const uint8_t *)a1 + 8) : 1;
    itlmtTrace(getController(), "awdl:set SYNC_ENABLED=%u", (unsigned)awdlSyncEnabled);
    return kIOReturnSuccess;
}

IOReturn itlmt7925AwdlInterface::getAWDL_SYNC_ENABLED(apple80211_awdl_sync_enabled *a1)
{
    if (a1) {
        *(uint32_t *)((uint8_t *)a1 + 0) = 1;               // version
        *(uint32_t *)((uint8_t *)a1 + 4) = 0;               // unk1
        *(uint32_t *)((uint8_t *)a1 + 8) = awdlSyncEnabled; // enabled
    }
    return kIOReturnSuccess;
}

// Slot 540 - the first call that failed ("configure Unable to set BSSID ret e00002c7"). The struct is u32 version + the
// BSSID the peer manager derived for this interface; the address part is read as six bytes at +4 (the layout is not in the
// public header) and only traced, so a wrong guess cannot corrupt anything.
IOReturn itlmt7925AwdlInterface::setAWDL_BSSID(apple80211_awdl_bssid *a1)
{
    if (a1) {
        memcpy(awdlBssid, (const uint8_t *)a1 + 4, sizeof(awdlBssid));
        itlmtTrace(getController(), "awdl:set BSSID %02x:%02x:%02x:%02x:%02x:%02x",
                   awdlBssid[0], awdlBssid[1], awdlBssid[2], awdlBssid[3], awdlBssid[4], awdlBssid[5]);
    } else {
        itlmtTrace(getController(), "awdl:set BSSID (null)");
    }
    return kIOReturnSuccess;
}

// apple80211_awdl_election_metric { u32 version; u32 metric }.
IOReturn itlmt7925AwdlInterface::setAWDL_ELECTION_METRIC(apple80211_awdl_election_metric *a1)
{
    awdlElectionMetric = a1 ? *(const uint32_t *)((const uint8_t *)a1 + 4) : 0;
    itlmtTrace(getController(), "awdl:set ELECTION_METRIC=%u", (unsigned)awdlElectionMetric);
    return kIOReturnSuccess;
}

// apple80211_awdl_sync_frame_template { u32 version; u32 payload_len; void *payload } - the PSF/action frame body the
// driver is expected to transmit on the AWDL channels (phase 4). Only the length is traced here.
IOReturn itlmt7925AwdlInterface::setAWDL_SYNC_FRAME_TEMPLATE(apple80211_awdl_sync_frame_template *a1)
{
    awdlSyncFrameLen = a1 ? *(const uint32_t *)((const uint8_t *)a1 + 4) : 0;
    const void *payload = a1 ? *(void *const *)((const uint8_t *)a1 + 8) : nullptr;
    itlmtTrace(getController(), "awdl:set SYNC_FRAME_TEMPLATE len=%u", (unsigned)awdlSyncFrameLen);
    // Hand the frame to the core's link thread: it holds the radio on the AWDL social channel (ROC) and transmits it. The
    // Family re-issues this template every sync period, so every call is one PSF transmission on the air.
    if (coreDev && payload && awdlSyncFrameLen >= 24 && awdlSyncFrameLen <= 256) {
        ItlNativeAwdlSync req = { 1, (const uint8_t *)payload, awdlSyncFrameLen, 6, 60 };
        IOReturn r = coreDev->callPlatformFunction(ITL_NATIVE_AWDL_SYNC, false, &req, nullptr, nullptr, nullptr);
        if (awdlSyncTxLogged < 8) {
            awdlSyncTxLogged++;
            itlmtTrace(getController(), "awdl:sync tx queued len=%u rc=%x", (unsigned)awdlSyncFrameLen, r);
        }
    } else if (awdlSyncTxLogged < 8) {
        awdlSyncTxLogged++;
        itlmtTrace(getController(), "awdl:sync tx skipped core=%d len=%u", coreDev ? 1 : 0, (unsigned)awdlSyncFrameLen);
    }
    return kIOReturnSuccess;
}

// apple80211_awdl_peer_traffic_registration { u32 version; void *addr; u32 name_len; char name[152]; u32 active } packed -
// the real-time group registration ("Can't send peer traffic registration to the driver" in the 21:27 log came from here).
IOReturn itlmt7925AwdlInterface::setAWDL_PEER_TRAFFIC_REGISTRATION(apple80211_awdl_peer_traffic_registration *a1)
{
    if (a1) {
        const uint8_t *p = (const uint8_t *)a1;
        uint32_t nameLen = *(const uint32_t *)(p + 12);
        uint32_t active = *(const uint32_t *)(p + 168);
        char name[17];
        size_t n = nameLen < sizeof(name) - 1 ? nameLen : sizeof(name) - 1;
        memcpy(name, p + 16, n);
        name[n] = 0;
        for (size_t i = 0; i < n; i++)
            if (name[i] < 0x20 || name[i] > 0x7e) name[i] = '.';
        itlmtTrace(getController(), "awdl:set PEER_TRAFFIC_REG active=%u len=%u name=%s",
                   (unsigned)active, (unsigned)nameLen, name);
    } else {
        itlmtTrace(getController(), "awdl:set PEER_TRAFFIC_REG (null)");
    }
    return kIOReturnSuccess;
}

// Slot 562. AppleBCMWLANProximityInterface::setCOMPANION_SKYWALK_IF_CREATE (0xffffff8001722ef2) reads action at +4
// (0 = destroy the companion, 1 = create one), builds apple80211SkywalkIfCreateParams_t {class, MAC, 9, 2}, calls
// AppleBCMWLANCore::createSkywalkInterface(&vif->companion, params, vif), then setCompanionInterfaceId(parent) and copies
// the companion's BSD name into the request at +8 (apple80211_companion_skywalk_if_create: version, action, bsd_name[16]).
// The LLW skywalk interface does not exist yet, so answer unsupported: wifip2pd logs it as a missing optional companion and
// continues (16:36:03 log: the failure is followed by the normal power-state / eligibility bring-up).
IOReturn itlmt7925AwdlInterface::setCOMPANION_SKYWALK_IF_CREATE(apple80211_companion_skywalk_if_create *a1)
{
    uint32_t action = a1 ? *(const uint32_t *)((const uint8_t *)a1 + 4) : 0xffffffffu;
    itlmtTrace(getController(), "awdl:companion action=%u (unsupported)", action);
    return kIOReturnUnsupported;
}

namespace {

// The registration needs a queue set; the datapath arrives in phase 5, so the actions consume nothing yet.
uint32_t awdlTxSubmissionAction(OSObject *, IOSkywalkTxSubmissionQueue *, IOSkywalkPacket *const *, uint32_t, void *) { return 0; }
uint32_t awdlTxCompletionAction(OSObject *, IOSkywalkTxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *) { return 0; }
uint32_t awdlRxCompletionAction(OSObject *, IOSkywalkRxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *) { return 0; }

template <typename T> T &field(void *base, size_t off) { return *(T *)((uint8_t *)base + off); }

const uint32_t kAwdlPoolPackets = 0x100;      // enough for a phase-2 registration; the real datapath sizes this later
const uint32_t kAwdlPoolBufferSize = 0x800;
const uint32_t kAwdlQueueCapacity = 0x100;

} // namespace

void itlmt7925AwdlInterface::freeAwdlRegistration()
{
    for (uint32_t i = 0; i < 3; i++) {
        if (awdlQueues[i]) {
            awdlQueues[i]->release();
            awdlQueues[i] = nullptr;
        }
    }
    if (awdlPool) {
        awdlPool->release();
        awdlPool = nullptr;
    }
}

IOReturn itlmt7925AwdlInterface::registerAwdlInterface(const uint8_t *mac)
{
    IOSkywalkPacketBufferPool::PoolOptions po;
    bzero(&po, sizeof(po));
    po.packets0 = po.packets1 = kAwdlPoolPackets;
    po.bufferSize = kAwdlPoolBufferSize;
    po.one = 1;
    po.zero = 0;
    po.flags = 1;
    awdlPool = IOSkywalkPacketBufferPool::withName("itlmt7925AwdlPool", this, 1, &po);
    if (!awdlPool) return kIOReturnNoMemory;

    awdlQueues[0] = IOSkywalkTxSubmissionQueue::withPool(awdlPool, kAwdlQueueCapacity, 0, this, awdlTxSubmissionAction, this, 0);
    awdlQueues[1] = IOSkywalkTxCompletionQueue::withPool(awdlPool, kAwdlQueueCapacity, 1, this, awdlTxCompletionAction, this, 0);
    awdlQueues[2] = IOSkywalkRxCompletionQueue::withPool(awdlPool, kAwdlQueueCapacity, 2, this, awdlRxCompletionAction, this, 0);
    if (!awdlQueues[0] || !awdlQueues[1] || !awdlQueues[2]) {
        freeAwdlRegistration();
        return kIOReturnNoMemory;
    }

    // RegistrationInfo (opaque 0x130 bytes): the fields AppleBCMWLANCore::createProxInterface sets before calling the
    // proximity interface's start (0xffffff800165dcbe): +0xc = 3, +0x14 = 2, +0x24 = 0x8000000080, +0x30 = the name pointer,
    // +0x38 = 0 (BSD unit: registerNetworkInterface sets the IOInterfaceUnit property only when this is >= 0; the BSD client
    // needs that property to build its name), +0x3c = 0x40 (headroom), +0x40 = 4|6 (flags), +0x108 = the MAC.
    uint8_t info[0x130];
    bzero(info, sizeof(info));
    initRegistrationInfo((IOSkywalkEthernetInterface::RegistrationInfo *)info, 1, 0x130);
    field<uint32_t>(info, 0xc) = 3;
    field<uint32_t>(info, 0x14) = 2;
    field<uint64_t>(info, 0x24) = 0x8000000080ULL;
    field<const char *>(info, 0x30) = "awdl";
    field<uint32_t>(info, 0x38) = 0;             // unit 0 -> awdl0
    field<uint16_t>(info, 0x3c) = 0x40;
    field<uint32_t>(info, 0x40) = 6;
    memcpy((uint8_t *)info + 0x108, mac, 6);

    IOReturn rr = registerEthernetInterface((IOSkywalkEthernetInterface::RegistrationInfo *)info, awdlQueues, 3,
                                            awdlPool, awdlPool, 0);
    if (rr != kIOReturnSuccess) freeAwdlRegistration();
    return rr;
}

// -----------------------------------------------------------------------------------------------------------------------
// Boot-arg
// -----------------------------------------------------------------------------------------------------------------------
bool itlmtAwdlEnabled()
{
    static int cached = -1;
    if (cached < 0) {
        uint32_t v = 0;
        cached = (PE_parse_boot_argn("itlmt_awdl", &v, sizeof(v)) && v) ? 1 : 0;
    }
    return cached == 1;
}

// -----------------------------------------------------------------------------------------------------------------------
// APPLE80211_IOC_VIRTUAL_IF_CREATE (0x5e), protocol slot 558.
// -----------------------------------------------------------------------------------------------------------------------
// Layout from IOKit/80211/apple80211_ioctl.h (apple80211_virt_if_create_data): u32 version; u8 mac[6]; u16 unk1; u32 role;
// u8 bsd_name[15]. The SDK header cannot be included in a kext (it wants __IO80211_TARGET), so the fields are read through
// this packed copy of it.
struct VirtIfCreateData {
    uint32_t version;
    uint8_t mac[6];
    uint16_t unk1;
    uint32_t role;
    uint8_t bsd_name[15];
} __attribute__((packed));

IOReturn itlmt7925WifiInterface::setVIRTUAL_IF_CREATE(apple80211_virt_if_create_data *d)
{
    itlmtCall(ctl, 'S', 558);
    VirtIfCreateData *data = (VirtIfCreateData *)d;
    if (!data) return kIOReturnBadArgument;
    if (!itlmtAwdlEnabled()) {
        itlmtTrace(ctl, "awdl:vif create refused (itlmt_awdl=0)");
        return kIOReturnUnsupported;
    }
    if (data->role != 6) {                       // only the AWDL (proximity) interface for now; 7 = APSTA, 8-10 = NAN
        itlmtTrace(ctl, "awdl:vif create role=%u unsupported", (unsigned)data->role);
        return kIOReturnUnsupported;
    }
    if (awdlVif) {                               // already created: answer with the existing BSD name
        const char *n = awdlVif->getBSDName();
        strlcpy((char *)data->bsd_name, n ? n : "", 15);
        return kIOReturnSuccess;
    }

    itlmt7925AwdlInterface *vif = (itlmt7925AwdlInterface *)OSMetaClass::allocClassWithName("itlmt7925AwdlInterface");
    if (!vif) {
        itlmtTrace(ctl, "awdl:vif alloc failed");
        return kIOReturnUnsupported;
    }

    // MAC: userland may hand one in; otherwise derive the AWDL MAC from the primary one (locally administered, different
    // last byte). Apple keeps a separate "awdl MAC" derived from the Wi-Fi MAC the same way. ether_addr stays incomplete in
    // a kext (the SDK header wants __IO80211_TARGET), so the address travels as bytes and is cast at the call sites.
    uint8_t mac[6];
    memcpy(mac, data->mac, 6);
    bool zero = true;
    for (uint32_t i = 0; i < 6; i++) if (mac[i]) zero = false;
    if (zero) {
        bzero(mac, 6);
        getHardwareAddress((ether_addr *)mac);
        mac[0] |= 0x02;
        mac[5] ^= 0x01;
    }

    if (!vif->init(ctl, (ether_addr *)mac, 6, "awdl")) {
        itlmtTrace(ctl, "awdl:vif init failed");
        vif->release();
        return kIOReturnError;
    }
    if (!vif->attach(ctl)) {
        itlmtTrace(ctl, "awdl:vif attach failed");
        vif->release();
        return kIOReturnError;
    }

    // Order (docs/ROADMAP-AWDL.md §9.5). AppleBCMWLANCore::createProxInterface (0xffffff800165dcbe) does withOptions ->
    // attach -> start(core, info) [which registers the ifnet and then registerService(kIOServiceSynchronous) +
    // setRunningState(false)], and the Family's own interfaces additionally bracket the whole setup with deferBSDAttach:
    // AppleBCMWLANSkywalkInterface::start calls deferBSDAttach(true) first, AppleBCMWLANCore::setupDriver calls
    // deferBSDAttach(false) once everything is up.
    //
    //   start(ctl)            IO80211VirtualInterface::start -> IO80211SkywalkInterface::start. That function is the only
    //                         place that stores the controller at ivars+0x30, which is exactly what getController()
    //                         (vtable slot 375) returns - and IO80211VirtualInterface::attachToBpf dereferences
    //                         getController()->[0x120] unconditionally. attachToBpf runs from the BSD client's start
    //                         (registerEthernetInterface -> registerNetworkInterface -> IOSkywalkNetworkBSDClient::
    //                         start -> nexus -> prepareBSDInterface), so without this call the first BSD attach panics
    //                         on a NULL controller (Kernel-2026-10-17-163303/165042: attachToBpf+0x37, CR2 0x120).
    //                         start() also runs IOService::start (IOSkywalkNetworkInterface::start, slot 188), so the
    //                         framework will not call start again (that would panic: "Calling start twice in a row").
    //   registerAwdlInterface the ifnet + BSD client; the client must NOT attach yet, hence the deferral below.
    //   deferBSDAttach(false) removeProperty(IODeferBSDAttach) + registerService(0): the BSD client re-probes only now,
    //                         with the controller in place. IOSkywalkNetworkBSDClient::start fails (defers) while the
    //                         property is true, so the deferral also closes the race with the config thread.
    vif->deferBSDAttach(true);
    if (!vif->start(ctl)) {
        itlmtTrace(ctl, "awdl:vif start failed");
        vif->release();
        return kIOReturnError;
    }
    itlmtTrace(ctl, "awdl:vif started");

    IOReturn rr = vif->registerAwdlInterface(mac);
    if (rr != kIOReturnSuccess) {
        itlmtTrace(ctl, "awdl:vif register rc=%x", rr);
        vif->release();
        return rr;
    }

    vif->registerService(kIOServiceAsynchronous);
    vif->setRunningState(false);
    vif->setNativeCore(core);
    ctl->setAwdlInterface(vif);
    awdlVif = vif;
    vif->deferBSDAttach(false);

    // The BSD client builds the BSD name during its (now asynchronous) re-probe, so getBSDName() may still be empty here;
    // the prefix is ours and the unit is the one registerAwdlInterface handed to the RegistrationInfo.
    const char *n = vif->getBSDName();
    char fallback[16];
    if (!n || !*n) {
        snprintf(fallback, sizeof(fallback), "awdl%u", 0);
        n = fallback;
    }
    strlcpy((char *)data->bsd_name, n, 15);
    itlmtTrace(ctl, "awdl:vif up bsd=%s", n);
    return kIOReturnSuccess;
}
