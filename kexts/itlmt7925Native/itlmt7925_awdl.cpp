// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AWDL front end implementation (see itlmt7925_awdl.h). Phase 2: the virtual interface exists and is registered; no RF work
// yet (phases 3-5 of docs/ROADMAP-AWDL.md: channel slicing, action frames, data path).
#include "itlmt7925_awdl.h"
#include "itlmt7925_iface.h"

#include "../itlmt7925/io80211/IO80211VirtualInterface.h"
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
class itlmt7925AwdlInterface : public IO80211VirtualInterface {
    OSDeclareDefaultStructors(itlmt7925AwdlInterface)

public:
    // IOSkywalkNetworkInterface::getBSDNamePrefix (slot 319): the BSD name the Family builds is <prefix><unit>.
    const char *getBSDNamePrefix() override;
    // Slot 490 is ___cxa_pure_virtual in Apple's binary and in IO80211AWDLProtocol (no override anywhere in the Family - the
    // Broadcom subclass implements it). Nothing on this path calls it; implemented so the subclass is concrete.
    void _unnamedPure490() override;

    // Creates the pool and the (three) queues and registers the ifnet from a RegistrationInfo filled like
    // AppleBCMWLANCore::createProxInterface fills it. Keeps the objects for the interface's lifetime.
    IOReturn registerAwdlInterface(const uint8_t *mac);
    void freeAwdlRegistration();

private:
    IOSkywalkPacketBufferPool *awdlPool = nullptr;
    IOSkywalkPacketQueue *awdlQueues[3] = {};
};

#undef super
#define super IO80211VirtualInterface
OSDefineMetaClassAndStructors(itlmt7925AwdlInterface, IO80211VirtualInterface)

const char *itlmt7925AwdlInterface::getBSDNamePrefix() { return "awdl"; }
void itlmt7925AwdlInterface::_unnamedPure490() {}

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
    // +0x3c = 0x40 (headroom), +0x40 = 4|6 (flags), +0x108 = the MAC.
    uint8_t info[0x130];
    bzero(info, sizeof(info));
    initRegistrationInfo((IOSkywalkEthernetInterface::RegistrationInfo *)info, 1, 0x130);
    field<uint32_t>(info, 0xc) = 3;
    field<uint32_t>(info, 0x14) = 2;
    field<uint64_t>(info, 0x24) = 0x8000000080ULL;
    field<const char *>(info, 0x30) = "awdl";
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

    IOReturn rr = vif->registerAwdlInterface(mac);
    if (rr != kIOReturnSuccess) {
        itlmtTrace(ctl, "awdl:vif register rc=%x", rr);
        vif->release();
        return rr;
    }

    vif->registerService(kIOServiceAsynchronous);
    ctl->setAwdlInterface(vif);
    awdlVif = vif;

    const char *n = vif->getBSDName();
    strlcpy((char *)data->bsd_name, n ? n : "", 15);
    itlmtTrace(ctl, "awdl:vif up bsd=%s", n ? n : "?");
    return kIOReturnSuccess;
}
