// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925 - Ethernet interface on top of the associated MT7925 link (the "network card" macOS sees).
// Created by itlmt7925::m3Link() after the 4-way handshake; frames to send arrive in outputPacket(), frames received from the AP are
// pushed in with rxPacket(). The 802.11 <-> Ethernet conversion is done in itlmt7925_m3.cpp.
// Output goes through an IOGatedOutputQueue: without a queue the stack calls outputPacket() from several threads at once (they
// shared txb), and a frame that found the TX pool full was dropped while reporting success (25 % of the frames under load).
// Now such a frame stalls the queue, and the driver restarts it with txKick() once the firmware returns buffers.
#include "itlmt7925.hpp"

#include <IOKit/IOWorkLoop.h>
#include <IOKit/network/IOEthernetController.h>
#include <IOKit/network/IOEthernetInterface.h>
#include <IOKit/network/IONetworkMedium.h>
#include <IOKit/network/IOOutputQueue.h>
#include <IOKit/network/IOGatedOutputQueue.h>
#include <sys/kpi_mbuf.h>
#include <string.h>

class itlmt7925Eth : public IOEthernetController {
    OSDeclareDefaultStructors(itlmt7925Eth)

public:
    bool setup(itlmt7925 *d, const uint8_t *m);
    void rxPacket(const uint8_t *e, uint32_t len);
    void setLink(bool up);
    void txKick();
    void flush();

    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    bool createWorkLoop() override;
    IOWorkLoop *getWorkLoop() const override;
    IOOutputQueue *createOutputQueue() override;
    IOReturn getHardwareAddress(IOEthernetAddress *addr) override;
    IOReturn enable(IONetworkInterface *netif) override;
    IOReturn disable(IONetworkInterface *netif) override;
    UInt32 outputPacket(mbuf_t m, void *param) override;
    IOReturn setPromiscuousMode(bool active) override;
    IOReturn setMulticastMode(bool active) override;
    IOReturn setMulticastList(IOEthernetAddress *addrs, UInt32 count) override;
    IOReturn getPacketFilters(const OSSymbol *group, UInt32 *filters) const override;

private:
    itlmt7925 *drv = nullptr;
    uint8_t addr[6] = {0};
    IOEthernetInterface *netif = nullptr;
    IOWorkLoop *wl = nullptr;
    IONetworkMedium *medium = nullptr;
    uint8_t txb[1600];                    // outputPacket() runs under the queue's command gate, one frame at a time
    static const UInt32 kTxQueueLen = 512;
    uint32_t rxQueued = 0;                // frames queued on netif since the last flush()
};

#define super IOEthernetController
OSDefineMetaClassAndStructors(itlmt7925Eth, IOEthernetController)

bool itlmt7925Eth::setup(itlmt7925 *d, const uint8_t *m)
{
    drv = d;
    memcpy(addr, m, 6);
    return true;
}

bool itlmt7925Eth::createWorkLoop()
{
    if (!wl) wl = IOWorkLoop::workLoop();
    return wl != nullptr;
}

IOWorkLoop *itlmt7925Eth::getWorkLoop() const
{
    return wl;
}

IOOutputQueue *itlmt7925Eth::createOutputQueue()
{
    if (!createWorkLoop()) return nullptr;
    return IOGatedOutputQueue::withTarget(this, wl, kTxQueueLen);
}

bool itlmt7925Eth::start(IOService *provider)
{
    if (!super::start(provider)) return false;

    UInt64 speed = drv ? drv->linkSpeedBps() : 54ULL * 1000000ULL;      // estimated PHY rate (54 Mb/s unless HT/VHT is in use)
    OSDictionary *media = OSDictionary::withCapacity(1);
    IONetworkMedium *med = IONetworkMedium::medium(kIOMediumEthernetAuto, speed);
    if (!media || !med) {
        if (med) med->release();
        if (media) media->release();
        return false;
    }
    IONetworkMedium::addMedium(media, med);
    bool ok = publishMediumDictionary(media) && setCurrentMedium(med) && setSelectedMedium(med);
    if (ok) setLinkStatus(kIONetworkLinkValid | kIONetworkLinkActive, med, speed);
    medium = med;                                                          // kept for setLink()
    medium->retain();
    med->release();
    media->release();
    if (!ok) return false;

    if (!attachInterface((IONetworkInterface **)&netif, true)) return false;
    if (IOOutputQueue *q = getOutputQueue()) q->start();
    registerService();
    return true;
}

void itlmt7925Eth::stop(IOService *provider)
{
    if (netif) { detachInterface(netif, true); netif = nullptr; }
    super::stop(provider);
}

void itlmt7925Eth::free()
{
    if (medium) { medium->release(); medium = nullptr; }
    if (wl) { wl->release(); wl = nullptr; }
    super::free();
}

IOReturn itlmt7925Eth::getHardwareAddress(IOEthernetAddress *a)
{
    memcpy(a->bytes, addr, 6);
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::enable(IONetworkInterface *)
{
    if (IOOutputQueue *q = getOutputQueue()) q->start();
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::disable(IONetworkInterface *)
{
    if (IOOutputQueue *q = getOutputQueue()) { q->stop(); q->flush(); }
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::setPromiscuousMode(bool)
{
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::setMulticastMode(bool)
{
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::setMulticastList(IOEthernetAddress *, UInt32)
{
    return kIOReturnSuccess;
}

IOReturn itlmt7925Eth::getPacketFilters(const OSSymbol *group, UInt32 *filters) const
{
    if (group == gIONetworkFilterGroup) {
        *filters = kIOPacketFilterUnicast | kIOPacketFilterBroadcast | kIOPacketFilterMulticast | kIOPacketFilterPromiscuous;
        return kIOReturnSuccess;
    }
    return super::getPacketFilters(group, filters);
}

UInt32 itlmt7925Eth::outputPacket(mbuf_t m, void *)
{
    if (!m) return kIOReturnOutputDropped;
    size_t len = mbuf_pkthdr_len(m);
    int r = -1;
    if (len >= 14 && len <= sizeof(txb) && drv) {
        mbuf_copydata(m, 0, len, txb);
        r = drv->ethTx(txb, (uint32_t)len);
    }
    if (r > 0) return kIOReturnOutputStall;                               // TX pool full: the queue keeps m and retries after txKick()
    freePacket(m);
    return r == 0 ? kIOReturnOutputSuccess : kIOReturnOutputDropped;
}

void itlmt7925Eth::txKick()
{
    if (IOOutputQueue *q = getOutputQueue()) q->service(IOBasicOutputQueue::kServiceAsync);
}

// Link state for macOS: down while the driver is between networks, so DHCP and the routes follow the Wi-Fi link.
void itlmt7925Eth::setLink(bool up)
{
    if (!medium) return;
    UInt64 speed = drv ? drv->linkSpeedBps() : 54ULL * 1000000ULL;
    setLinkStatus(kIONetworkLinkValid | (up ? kIONetworkLinkActive : 0), up ? medium : nullptr, up ? speed : 0);
}

void itlmt7925Eth::rxPacket(const uint8_t *e, uint32_t len)
{
    if (!netif || len < 14) return;
    mbuf_t m = allocatePacket(len);
    if (!m) return;
    memcpy(mbuf_data(m), e, len);
    netif->inputPacket(m, len, IONetworkInterface::kInputOptionQueuePacket);
    if (++rxQueued >= 64) flush();
}

// One wake-up of the stack per batch instead of one per frame (the driver calls it after each pass over the rings).
void itlmt7925Eth::flush()
{
    if (!netif || !rxQueued) return;
    rxQueued = 0;
    netif->flushInputQueue();
}

// ---- driver side ----------------------------------------------------------------------------------------------------------------
bool itlmt7925::ethCreate()
{
    itlmt7925Eth *e = OSTypeAlloc(itlmt7925Eth);
    if (!e) return false;
    if (!e->init(nullptr) || !e->setup(this, mac)) { e->release(); return false; }
    if (!e->attach(this)) { e->release(); return false; }
    if (!e->start(this)) { e->detach(this); e->release(); return false; }
    eth = e;
    return true;
}

void itlmt7925::ethRx(const uint8_t *frame, uint32_t len)
{
    if (nativeMode && nativeLock) {
        IOLockLock(nativeLock);
        if (nativeSink.owner && nativeSink.receive) nativeSink.receive(nativeSink.owner, frame, len);
        IOLockUnlock(nativeLock);
        return;
    }
    if (eth) eth->rxPacket(frame, len);
}

void itlmt7925::ethLink(bool up)
{
    if (nativeMode && nativeLock) {
        IOLockLock(nativeLock);
        ItlNativeSink sink = nativeSink;
        if (sink.owner && sink.lifetime && sink.link) { sink.owner->retain(); sink.lifetime->retain(); }
        else sink.owner = nullptr;
        IOLockUnlock(nativeLock);
        // Family link updates can sleep on the native gate. Never hold bridge
        // lock while entering it: gated stop/unbind acquires that lock.
        if (sink.owner) {
            sink.link(sink.owner, up, up ? linkSpeedBps() : 0);
            sink.owner->release(); sink.lifetime->release();
        }
        return;
    }
    if (!eth) return;
    eth->setLink(up);
    eth->txKick();                                                         // a stalled queue drains (link down: drops) or resumes
}

void itlmt7925::ethFlush()
{
    if (eth) eth->flush();
}

void itlmt7925::ethTxKick()
{
    if (eth) eth->txKick();
}

IOReturn itlmt7925::callPlatformFunction(const OSSymbol *name, bool wait, void *p1, void *p2, void *p3, void *p4)
{
    if (!name) return kIOReturnBadArgument;
    if (name->isEqualTo(ITL_NATIVE_MAC)) {
        if (!p1) return kIOReturnBadArgument;
        memcpy(p1, mac, 6);
        return kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_TX)) {
        if (!nativeMode || !p1) return kIOReturnNotReady;
        ItlNativeTx *tx = (ItlNativeTx *)p1;
        if (!tx->bytes || tx->length < 14 || tx->length > 1600) return kIOReturnBadArgument;
        tx->result = ethTx(tx->bytes, tx->length); // hardware copies into its own staging buffer
        return kIOReturnSuccess;
    }
    // scan / join control: the interface's handlers run on the Family's queue; each of these only touches the mailbox / snapshots
    if (name->isEqualTo(ITL_NATIVE_SCAN)) {
        ItlNativeScan *s = (ItlNativeScan *)p1;
        if (!nativeMode || !s || s->version != 1) return kIOReturnBadArgument;
        return nativeScanReq(&s->started);
    }
    if (name->isEqualTo(ITL_NATIVE_NETS)) {
        ItlNativeNets *n = (ItlNativeNets *)p1;
        if (!nativeMode || !n || n->version != 1 || !n->aps || !n->max) return kIOReturnBadArgument;
        nativeNets(n);
        return kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_AWDL_SYNC)) {   // AWDL PSF frame: copied into the link thread's mailbox, never blocks here
        ItlNativeAwdlSync *a = (ItlNativeAwdlSync *)p1;
        if (!nativeMode || !a || a->version != 1) return kIOReturnBadArgument;
        if (!a->frame || a->len < 24 || a->len > 256) return kIOReturnBadArgument;
        return awdlSubmit(a->frame, a->len, a->channel, a->dwellMs) ? kIOReturnError : kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_AWDL_RX)) {     // AWDL action frame from the radio: popped from the RX ring, no chip access
        ItlNativeAwdlRx *r = (ItlNativeAwdlRx *)p1;
        if (!nativeMode || !r || r->version != 1 || !r->buf) return kIOReturnBadArgument;
        r->len = 0;
        if (!awdlRxFetch(r->buf, r->cap, &r->len)) return kIOReturnNoResources;   // queue empty
        return kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_STATUS)) {
        ItlNativeStatus *s = (ItlNativeStatus *)p1;
        if (!nativeMode || !s) return kIOReturnBadArgument;
        nativeStatus(s);
        return kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_JOIN)) {
        if (!nativeMode) return kIOReturnNotReady;
        return nativeJoin((const ItlNativeJoin *)p1);
    }
    if (name->isEqualTo(ITL_NATIVE_LEAVE)) {
        if (!nativeMode) return kIOReturnNotReady;
        IOReturn r = ucDisconnect();
        if (r == kIOReturnSuccess) njState = ITL_NATIVE_IDLE;
        return r;
    }
    if (name->isEqualTo(ITL_NATIVE_BIND)) {
        ItlNativeSink *sink = (ItlNativeSink *)p1;
        if (!nativeMode || !nativeLock) return kIOReturnNotReady;
        if (!sink || sink->version != 2 || !sink->lifetime || !sink->owner || !sink->receive || !sink->link)
            return kIOReturnBadArgument;
        IOLockLock(nativeLock);
        if (nativeSink.owner) { IOLockUnlock(nativeLock); return kIOReturnBusy; }
        nativeSink = *sink;
        nativeSink.link(nativeSink.owner, m3linkUp, m3linkUp ? linkSpeedBps() : 0);
        // RX callbacks remain under nativeLock. Link snapshots retain owner/controller and gated actions recheck bound.
        IOLockUnlock(nativeLock);
        IOLog("itlmt7925 native: sink bound\n");
        return kIOReturnSuccess;
    }
    if (name->isEqualTo(ITL_NATIVE_UNBIND)) {
        if (!nativeLock) return kIOReturnNotReady;
        IOLockLock(nativeLock);
        if (nativeSink.owner != p1) { IOLockUnlock(nativeLock); return kIOReturnNotAttached; }
        bzero(&nativeSink, sizeof(nativeSink));
        IOLockUnlock(nativeLock);
        IOLog("itlmt7925 native: sink unbound\n");
        return kIOReturnSuccess;
    }
    return IOService::callPlatformFunction(name, wait, p1, p2, p3, p4);
}
