// SPDX-License-Identifier: BSD-3-Clause-Clear
// Native DCN 3.5 DisplayPort AUX engine (software channel), driven through BAR5 MMIO.
//
// Register map: amdgpu dcn_3_5_0_offset.h / dcn_3_5_0_sh_mask.h (DP_AUX0..4), IP-discovery
// bases of this machine (DMU segment 2 = 0x34C0 dwords). Transaction sequence follows
// drivers/gpu/drm/amd/display/dc/dce/dce_aux.c (acquire, submit, status, read reply, release).
//
// The engine is only ever used for native DPCD reads/writes of at most 16 bytes. Nothing here
// programs timing, clocks, PHY or power; the firmware/GOP bring-up of the AUX block is reused.
#pragma once
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <libkern/OSByteOrder.h>

class DcnAux {
public:
    enum : int {
        kOk = 0, kNoMap = -1, kDead = -2, kDmcu = -3, kAcquire = -4, kTimeout = -5, kHpd = -6,
        kInvalid = -7, kNack = -8, kDefer = -9, kArg = -10, kBusy = -11
    };
    static constexpr unsigned kChannels = 5;

    // dword offsets from the DMU segment-2 base
    static constexpr uint32_t kSegment2 = 0x34C0;
    static constexpr uint32_t kAux0 = 0x1f50, kStride = 0x1c;
    static constexpr uint32_t kCtl = 0, kSwCtl = 1, kArb = 2, kIntCtl = 3, kSwStatus = 4, kSwData = 6;

    // AUX_CONTROL
    static constexpr uint32_t kCtlEn = 1u << 0, kCtlReset = 1u << 4, kCtlResetDone = 1u << 5;
    // AUX_ARB_CONTROL
    static constexpr uint32_t kArbStatusMask = 0xC, kArbStatusShift = 2;
    static constexpr uint32_t kArbSwUse = 1u << 16, kArbSwDone = 1u << 17;
    // AUX_SW_CONTROL
    static constexpr uint32_t kSwGo = 1u << 0, kSwDelayMask = 0xF0, kSwWrMask = 0x1F0000, kSwWrShift = 16;
    // AUX_INTERRUPT_CONTROL
    static constexpr uint32_t kIntDoneAck = 1u << 1;
    // AUX_SW_STATUS
    static constexpr uint32_t kStDone = 1u << 0, kStTimeoutState = 0x70, kStTimeout = 0x80,
                              kStHpdDiscon = 0x200, kStInvalidStop = 0x4000, kStNoDet = 0x100000,
                              kStInvalidH = 0x400000, kStInvalidL = 0x800000,
                              kStCountMask = 0x1F000000, kStCountShift = 24;
    // AUX_SW_DATA
    static constexpr uint32_t kDataRw = 1u << 0, kDataShift = 8, kDataMask = 0xFF00,
                              kDataIndexShift = 16, kDataIncDisable = 1u << 31;
    // DP native AUX request command nibble (already shifted into the high nibble)
    static constexpr uint32_t kActionWrite = 0x80, kActionRead = 0x90;
    static constexpr unsigned kMaxPayload = 16;

    bool attach(IOPCIDevice *pci) {
        if (map) return true;
        if (!pci || !(pci->configRead16(kIOPCIConfigCommand) & kIOPCICommandMemorySpace)) return false;
        map = pci->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress5, kIOMapInhibitCache);
        if (!map) return false;
        base = reinterpret_cast<volatile uint8_t *>(map->getVirtualAddress());
        length = map->getLength();
        constexpr uint32_t needDwords = kSegment2 + kAux0 + (kChannels - 1) * kStride + kSwData + 1;
        if (!base || length < size_t(needDwords) * 4) { detach(); return false; }
        lock = IOLockAlloc();
        if (!lock) { detach(); return false; }
        return true;
    }
    void detach() {
        if (lock) { IOLockFree(lock); lock = nullptr; }
        if (map) { map->release(); map = nullptr; }
        base = nullptr; length = 0;
    }
    bool ready() const { return map && base && lock; }

    uint32_t reg(unsigned ch, uint32_t which) {
        return rd(kSegment2 + kAux0 + ch * kStride + which);
    }

    // Native AUX read/write of 1..16 bytes with Linux' retry policy. Serialised.
    int read(unsigned ch, uint32_t addr, uint8_t *out, unsigned n, uint32_t *sw = nullptr) {
        return run(ch, false, addr, nullptr, out, n, sw);
    }
    int write(unsigned ch, uint32_t addr, const uint8_t *in, unsigned n, uint32_t *sw = nullptr) {
        return run(ch, true, addr, in, nullptr, n, sw);
    }
    // Leave the engine enabled after a probe of a disabled channel (default: put AUX_CONTROL back).
    bool keepEnabled = false;

private:
    IOMemoryMap *map = nullptr;
    volatile uint8_t *base = nullptr;
    size_t length = 0;
    IOLock *lock = nullptr;

    uint32_t rd(uint32_t dword) { return OSReadLittleInt32(const_cast<uint8_t *>(base), dword * 4); }
    void wr(uint32_t dword, uint32_t v) { OSWriteLittleInt32(const_cast<uint8_t *>(base), dword * 4, v); }
    uint32_t addrOf(unsigned ch, uint32_t which) const { return kSegment2 + kAux0 + ch * kStride + which; }
    uint32_t r(unsigned ch, uint32_t which) { return rd(addrOf(ch, which)); }
    void w(unsigned ch, uint32_t which, uint32_t v) { wr(addrOf(ch, which), v); }

    bool wait(unsigned ch, uint32_t which, uint32_t mask, uint32_t want, unsigned usTotal) {
        for (unsigned t = 0; t <= usTotal; t += 10) {
            if ((r(ch, which) & mask) == want) return true;
            IODelay(10);
        }
        return false;
    }

    // dce_aux.c acquire_engine(); returns kOk when software owns the channel.
    int acquire(unsigned ch, uint32_t &origCtl) {
        uint32_t arb = r(ch, kArb);
        if (arb == 0xFFFFFFFFu) return kDead;
        if (((arb & kArbStatusMask) >> kArbStatusShift) == 2) return kDmcu;
        origCtl = r(ch, kCtl);
        if (!(origCtl & kCtlEn)) {
            uint32_t v = origCtl | kCtlEn | kCtlReset;
            w(ch, kCtl, v);
            if (!wait(ch, kCtl, kCtlResetDone, kCtlResetDone, 110)) return kAcquire;
            w(ch, kCtl, v & ~kCtlReset);
            wait(ch, kCtl, kCtlResetDone, 0, 110);
        }
        arb = r(ch, kArb);
        w(ch, kArb, arb | kArbSwUse);
        arb = r(ch, kArb);
        return ((arb & kArbStatusMask) >> kArbStatusShift) == 1 ? kOk : kAcquire;
    }
    void release(unsigned ch) {
        uint32_t arb = r(ch, kArb);
        w(ch, kArb, (arb | kArbSwDone) & ~kArbSwUse);
    }

    // One request/reply on an acquired channel. kOk with *reply = AUX reply code (0 ACK, 1 NACK, 2 DEFER).
    int once(unsigned ch, bool isWrite, uint32_t addr, const uint8_t *in, uint8_t *out, unsigned n,
             uint8_t *reply, uint32_t *swOut) {
        w(ch, kIntCtl, r(ch, kIntCtl) | kIntDoneAck);
        if (!wait(ch, kSwStatus, kStDone, 0, 2200)) return kTimeout;

        uint32_t wrBytes = 4 + (isWrite ? n : 0);
        uint32_t sc = r(ch, kSwCtl) & ~(kSwDelayMask | kSwWrMask);
        w(ch, kSwCtl, sc | (wrBytes << kSwWrShift));

        uint32_t action = isWrite ? kActionWrite : kActionRead;
        auto data = [&](uint32_t value, bool incDisable) {
            w(ch, kSwData, (value << kDataShift) | (incDisable ? kDataIncDisable : 0));
        };
        data(action | ((addr & 0xF0000) >> 16), true);
        data((addr & 0xFF00) >> 8, false);
        data(addr & 0xFF, false);
        data(n - 1, false);
        if (isWrite) for (unsigned i = 0; i < n; ++i) data(in[i], false);

        w(ch, kSwCtl, r(ch, kSwCtl) | kSwGo);
        if (!wait(ch, kSwStatus, kStDone, kStDone, 6000)) { w(ch, kSwCtl, r(ch, kSwCtl) & ~kSwGo); return kTimeout; }

        uint32_t st = r(ch, kSwStatus);
        if (swOut) *swOut = st;
        if (st == 0xFFFFFFFFu) return kDead;
        if (st & kStHpdDiscon) return kHpd;
        if (st & (kStTimeoutState | kStTimeout)) return kTimeout;
        if (st & (kStInvalidStop | kStNoDet | kStInvalidH | kStInvalidL)) return kInvalid;
        unsigned replied = (st & kStCountMask) >> kStCountShift;
        if (!replied) return kInvalid;

        // reply: INDEX 0, autoincrement disable, read mode (three sequential writes as dce_aux.c does)
        w(ch, kSwData, 0);
        w(ch, kSwData, kDataIncDisable);
        w(ch, kSwData, kDataIncDisable | kDataRw);
        uint32_t first = (r(ch, kSwData) & kDataMask) >> kDataShift;
        *reply = uint8_t(first >> 4);
        if (*reply) return kOk;
        unsigned payload = replied - 1;
        if (payload > kMaxPayload) return kInvalid;
        for (unsigned i = 0; i < payload; ++i) {
            uint8_t b = uint8_t((r(ch, kSwData) & kDataMask) >> kDataShift);
            if (out && i < n) out[i] = b;
        }
        if (!isWrite && payload < n) return kInvalid;
        return kOk;
    }

    int run(unsigned ch, bool isWrite, uint32_t addr, const uint8_t *in, uint8_t *out, unsigned n, uint32_t *sw) {
        if (!ready()) return kNoMap;
        if (ch >= kChannels || !n || n > kMaxPayload || addr > 0xFFFFF) return kArg;
        IOLockLock(lock);
        int rc = kAcquire;
        uint32_t origCtl = 0;
        unsigned invalid = 0, timeouts = 0, defers = 0;
        for (unsigned attempt = 0; attempt < 7; ++attempt) {
            rc = acquire(ch, origCtl);
            if (rc != kOk) { if (rc != kDead) release(ch); break; }
            uint8_t reply = 0;
            rc = once(ch, isWrite, addr, in, out, n, &reply, sw);
            release(ch);
            if (rc == kOk) {
                if (reply == 0) break;                    // ACK
                if (reply == 1) { rc = kNack; break; }    // NACK
                rc = kDefer;
                if (++defers >= 7) break;
                IOSleep(1);
                continue;
            }
            if (rc == kInvalid) { if (++invalid >= 2) break; IODelay(400); continue; }
            if (rc == kTimeout) { if (++timeouts >= 3) break; continue; }
            break;                                        // HPD, dead, other: no retry
        }
        if (ch < kChannels && !keepEnabled && !(origCtl & kCtlEn) && ready() && rc != kDead)
            w(ch, kCtl, origCtl);
        IOLockUnlock(lock);
        return rc;
    }
};
