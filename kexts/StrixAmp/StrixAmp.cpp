// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// StrixAmp: I2C access to the Cirrus Logic CS35L56 speaker amplifiers of the GA403WM (docs/AUDIO-ROG.md).
//
// The DSDT declares the amps as \_SB.I2CB.SPKR (_HID CSC3556, _SUB 10431024): I2C slave addresses 0x30, 0x31 (and 0x3A) at
// 1 MHz on I2CB, reset GPIO 24, speaker-ID GPIO 104, interrupt GPIO 18, "cirrus,dev-index" {0x30, 0x31}. VoodooI2C owns I2CB
// and publishes one VoodooI2CDeviceNub (for 0x30); this kext attaches to it, then talks to every declared address through
// the nub's provider, the controller driver (VoodooI2CControllerDriver::transferI2C), because a nub is bound to one address.
//
// The kernel part is deliberately mechanism only: an operation stream is executed against the bus and the register policy
// (bring-up, play/pause, volume, firmware download) lives in userland (tools/strixampctl.c, scripts/strixamp-fw.py), so
// the amp sequences can be iterated without a reboot. What the kernel enforces:
//   - only root / an administrator can open the user client;
//   - I2C addresses 0x30, 0x31 and 0x3A only; 0x3A (role unknown) is read-only;
//   - writes only to the register windows the HDA bring-up sequence needs (ASP/mixer routing, mailbox, IRQ mask, user
//     controls, DSP memory); boost / analog / global-enable registers need the boot-arg strixamp_unsafe=1;
//   - USER_VOLUME writes above 0 dB are refused (unless strixamp_unsafe=1).
//
// Credits (see NOTICE.md): register map and I2C framing from the Linux cs35l56 driver (Cirrus Logic, GPL-2.0); only
// interface facts (register numbers, access width) are used, no code is copied.
#include <IOKit/IOLib.h>
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOKitKeys.h>
#include <libkern/OSKextLib.h>
#include <pexpert/pexpert.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <libkern/c++/OSSymbol.h>
#include "StrixAmpProto.h"

// --- the slice of VoodooI2C's API this kext uses (VoodooI2C 2.9.1) --------------------------------------------------------
// Only non-virtual methods are called, so no vtable / layout knowledge is needed; the symbols are exported by
// com.alexandred.VoodooI2C.
typedef struct {
    UInt16 address;
    UInt8 *buffer;
    UInt16 flags;
    UInt16 length;
} VoodooI2CControllerBusMessage;
#define SA_I2C_M_RD 0x0001

class VoodooI2CControllerDriver : public IOService {
public:
    IOReturn transferI2C(VoodooI2CControllerBusMessage *messages, int number);
};

class VoodooI2CDeviceNub : public IOService {
public:
    IOReturn writeReadI2C(UInt8 *write_buffer, UInt16 write_length, UInt8 *read_buffer, UInt16 read_length);
};

namespace {
constexpr UInt32 kRegDevId = 0x00000000;
constexpr UInt32 kRegRevId = 0x00000004;
constexpr UInt32 kRegUserVolume = 0x0340002C;
constexpr UInt32 kDevIdCs35l56 = 0x00035A56;
constexpr int kTries = 5;
constexpr UInt16 kChunk = 256;            // bytes of payload per I2C transaction
constexpr UInt8 kAddrs[] = { 0x30, 0x31, 0x3A };

bool addrKnown(UInt8 a) { for (UInt8 k : kAddrs) if (k == a) return true; return false; }
bool addrWritable(UInt8 a) { return a == 0x30 || a == 0x31; }

// write windows [lo, hi] inclusive
struct Window { UInt32 lo, hi; };
constexpr Window kWriteWindows[] = {
    { 0x00004800, 0x00004C7C },   // ASP1 control / frame / data, ASP1TX source selects, SoundWire DP3 channel selects
    { 0x00010004, 0x00010008 },   // MIXER_NGATE_CH1/2_CFG
    { 0x00011000, 0x0001103C },   // DSP mailbox (raw + virtual 1..8)
    { 0x0000E000, 0x0000E0FF },   // IRQ1 status / mask
    { 0x03400000, 0x034000FF },   // firmware user controls: mute, volume, posture, protection status, ...
    { 0x02000000, 0x03FFFFFF },   // DSP memory / core registers (firmware download, HALO state)
};
}

class StrixAmp : public IOService {
    OSDeclareDefaultStructors(StrixAmp)
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                           IOUserClient **handler) override;

    IOReturn exec(const UInt8 *in, UInt32 inLen, UInt8 *out, UInt32 *outLen);

    IOLock *lock = nullptr;
    bool unsafe = false;
    UInt32 spkInfo = 0;        // SaInfo.reserved: bit0 speaker-ID strap read, bit1 its level, bits 16..: raw pad register >> 16

private:
    VoodooI2CControllerDriver *ctrl = nullptr;

    IOReturn xfer(UInt8 addr, UInt32 reg, UInt8 *rd, UInt16 rdLen, const UInt8 *wr, UInt16 wrLen);
    IOReturn read32(UInt8 addr, UInt32 reg, UInt32 *v);
    IOReturn write32(UInt8 addr, UInt32 reg, UInt32 v);
    bool writeAllowed(UInt8 addr, UInt32 reg, UInt32 len, const UInt8 *be) const;   // be: payload, big endian words
    void publishProbe();
    void readSpeakerId();
    void traceOp(const SaOpHdr &h, IOReturn rc, UInt32 value);
    void bootSnapshot();
    bool tracing = false;
    UInt64 sequence = 0, transfers = 0, retries = 0, errors = 0;
    OSArray *traceTail = nullptr;
    OSArray *traceBringUp = nullptr;
};

OSDefineMetaClassAndStructors(StrixAmp, IOService)

// ---- bus ----------------------------------------------------------------------------------------------------------------

// One register transaction. Either a read (rd != null: write the 4 byte big-endian register, then read) or a write
// (wr != null: register + data in a single message). Retries because the amp NAKs while it wakes from hibernate.
IOReturn StrixAmp::xfer(UInt8 addr, UInt32 reg, UInt8 *rd, UInt16 rdLen, const UInt8 *wr, UInt16 wrLen)
{
    UInt8 hdr[4] = { (UInt8)(reg >> 24), (UInt8)(reg >> 16), (UInt8)(reg >> 8), (UInt8)reg };
    IOReturn rc = kIOReturnError;
    unsigned attempts = 0;
    if (wr) {
        if (wrLen > kChunk) return kIOReturnBadArgument;
        UInt8 buf[4 + kChunk];
        memcpy(buf, hdr, 4);
        memcpy(buf + 4, wr, wrLen);
        VoodooI2CControllerBusMessage m = { addr, buf, 0, (UInt16)(4 + wrLen) };
        for (int i = 0; i < kTries; i++) {
            attempts++;
            rc = ctrl->transferI2C(&m, 1);
            if (rc == kIOReturnSuccess) break;
            IOSleep(1);
        }
    } else {
        VoodooI2CControllerBusMessage m[2] = { { addr, hdr, 0, 4 }, { addr, rd, SA_I2C_M_RD, rdLen } };
        for (int i = 0; i < kTries; i++) {
            attempts++;
            rc = ctrl->transferI2C(m, 2);
            if (rc == kIOReturnSuccess) break;
            IOSleep(1);
        }
    }
    transfers++;
    retries += attempts > 0 ? attempts - 1 : 0;
    if (rc != kIOReturnSuccess) {
        errors++;
        IOLog("StrixAmp: TRACE I2C failed addr=%02x reg=%08x direction=%s bytes=%u attempts=%u rc=%08x\n",
              addr, reg, wr ? "write" : "read", wr ? wrLen : rdLen, attempts, rc);
    } else if (tracing && attempts > 1) {
        IOLog("StrixAmp: TRACE I2C retry addr=%02x reg=%08x attempts=%u\n", addr, reg, attempts);
    }
    return rc;
}

void StrixAmp::traceOp(const SaOpHdr &h, IOReturn rc, UInt32 value)
{
    if (!tracing) return;
    sequence++;
    char line[224];
    snprintf(line, sizeof(line), "seq=%llu op=%u addr=%02x reg=%08x a=%08x b=%08x len=%u value=%08x rc=%08x",
             sequence, h.op, h.addr, h.reg, h.a, h.b, h.len, value, rc);
    bool milestone = h.reg == 0x11020 || h.op == kSaOpWBlock || rc != kIOReturnSuccess;
    if (sequence <= 4096 || milestone) IOLog("StrixAmp: TRACE %s\n", line);
    setProperty("TraceLastOp", line);
    if (rc != kIOReturnSuccess) setProperty("TraceLastFailure", line);
    if (traceTail) {
        if (traceTail->getCount() == 128) traceTail->removeObject(0);
        OSString *s = OSString::withCString(line);
        if (s) { traceTail->setObject(s); s->release(); }
        if (sequence % 32 == 0 || milestone) {
            OSArray *snapshot = OSArray::withArray(traceTail);
            if (snapshot) { setProperty("TraceTail", snapshot); snapshot->release(); }
        }
    }
    bool retainInit = h.op == kSaOpWrite32 || h.op == kSaOpWBlock ||
                      h.op == kSaOpUBits || h.op == kSaOpPoll || rc != kIOReturnSuccess;
    if (traceBringUp && retainInit) {
        if (traceBringUp->getCount() < 1024) {
            OSString *s = OSString::withCString(line);
            if (s) { traceBringUp->setObject(s); s->release(); }
            if (traceBringUp->getCount() % 32 == 0 || milestone) {
                OSArray *snapshot = OSArray::withArray(traceBringUp);
                if (snapshot) { setProperty("TraceBringUp", snapshot); snapshot->release(); }
            }
        } else setProperty("TraceBringUpTruncated", true);
    }
    setProperty("TraceSequence", sequence, 64);
    setProperty("TraceI2CTransfers", transfers, 64);
    setProperty("TraceI2CRetries", retries, 64);
    setProperty("TraceI2CErrors", errors, 64);
}

void StrixAmp::bootSnapshot()
{
    static const UInt32 regs[] = {0x10, 0x2014, 0x2018, 0x201C, 0x2C04, 0x4800,
        0x4804, 0x4808, 0xE004, 0xE010, 0xE02C, 0x2800010, 0x28021E0,
        0x2804308, 0x3400024, 0x340002C, 0x34000D8, 0x3400150};
    for (UInt8 a : kAddrs) {
        if (!addrWritable(a)) continue;
        for (UInt32 reg : regs) {
            UInt32 value = 0;
            IOReturn rc = read32(a, reg, &value);
            char key[48];
            snprintf(key, sizeof(key), "Boot-Amp%02X-Reg%08X", a, reg);
            if (rc == kIOReturnSuccess) setProperty(key, (UInt64)value, 32);
            IOLog("StrixAmp: TRACE BOOT addr=%02x reg=%08x value=%08x rc=%08x\n", a, reg, value, rc);
        }
    }
}

IOReturn StrixAmp::read32(UInt8 addr, UInt32 reg, UInt32 *v)
{
    UInt8 d[4] = { 0, 0, 0, 0 };
    IOReturn rc = xfer(addr, reg, d, 4, nullptr, 0);
    if (rc == kIOReturnSuccess) *v = ((UInt32)d[0] << 24) | ((UInt32)d[1] << 16) | ((UInt32)d[2] << 8) | d[3];
    return rc;
}

IOReturn StrixAmp::write32(UInt8 addr, UInt32 reg, UInt32 v)
{
    UInt8 d[4] = { (UInt8)(v >> 24), (UInt8)(v >> 16), (UInt8)(v >> 8), (UInt8)v };
    return xfer(addr, reg, nullptr, 0, d, 4);
}

bool StrixAmp::writeAllowed(UInt8 addr, UInt32 reg, UInt32 len, const UInt8 *be) const
{
    if (!addrKnown(addr)) return false;
    if (unsafe) return true;
    if (!addrWritable(addr)) return false;
    if (len == 0 || (reg & 3) || (len & 3)) return false;
    UInt32 last = reg + len - 4;
    if (last < reg) return false;
    bool ok = false;
    for (const Window &w : kWriteWindows)
        if (reg >= w.lo && last <= w.hi) { ok = true; break; }
    if (!ok) return false;
    // never raise the user volume above 0 dB: field is bits 15:6, signed, 0.25 dB steps. A block write that covers the
    // register (firmware download into YM) is checked on the word that lands there.
    if (reg <= kRegUserVolume && kRegUserVolume <= last) {
        if (!be) return false;
        const UInt8 *p = be + (kRegUserVolume - reg);
        UInt32 v = ((UInt32)p[0] << 24) | ((UInt32)p[1] << 16) | ((UInt32)p[2] << 8) | p[3];
        int vol = (int)((v >> 6) & 0x3FF);
        if (vol & 0x200) vol -= 0x400;
        if (vol > 0) return false;
    }
    return true;
}

// ---- operation stream ---------------------------------------------------------------------------------------------------

static inline UInt32 pad4(UInt32 n) { return (n + 3) & ~3u; }

IOReturn StrixAmp::exec(const UInt8 *in, UInt32 inLen, UInt8 *out, UInt32 *outLen)
{
    if (!ctrl) return kIOReturnNotAttached;
    UInt32 ip = 0, op = 0, cap = *outLen;
    IOLockLock(lock);
    while (ip + sizeof(SaOpHdr) <= inLen) {
        SaOpHdr h;
        memcpy(&h, in + ip, sizeof(h));
        ip += sizeof(h);
        UInt32 payload = 0;
        if (h.op == kSaOpWBlock) {
            payload = h.len;
            if ((payload & 3) || ip + payload > inLen) break;
        }
        // reserve response space: header + worst-case data
        UInt32 want = sizeof(SaRespHdr) + ((h.op == kSaOpRBlock) ? pad4(h.len) : (h.op == kSaOpInfo ? sizeof(SaInfo) : 4));
        if (op + want > cap) break;
        SaRespHdr *rh = (SaRespHdr *)(out + op);
        UInt8 *rd = out + op + sizeof(SaRespHdr);
        IOReturn rc = kIOReturnSuccess;
        UInt32 rlen = 0;

        if (h.op != kSaOpSleep && h.op != kSaOpInfo && !addrKnown(h.addr)) rc = kIOReturnBadArgument;
        else switch (h.op) {
        case kSaOpInfo: {
            SaInfo i = { STRIXAMP_PROTO_VERSION, (UInt32)(unsafe ? 1 : 0), 0, spkInfo };
            for (UInt8 a : kAddrs) i.i2cAddrMask |= 1u << (a - 0x30);
            memcpy(rd, &i, sizeof(i));
            rlen = sizeof(i);
            break;
        }
        case kSaOpRead32: {
            UInt32 v = 0;
            rc = read32(h.addr, h.reg, &v);
            if (rc == kIOReturnSuccess) { memcpy(rd, &v, 4); rlen = 4; }
            break;
        }
        case kSaOpWrite32:
        {
            UInt8 be[4] = { (UInt8)(h.a >> 24), (UInt8)(h.a >> 16), (UInt8)(h.a >> 8), (UInt8)h.a };
            if (!writeAllowed(h.addr, h.reg, 4, be)) { rc = kIOReturnNotPermitted; break; }
            rc = write32(h.addr, h.reg, h.a);
            break;
        }
            break;
        case kSaOpRBlock: {
            if (h.len == 0 || (h.len & 3) || h.reg & 3) { rc = kIOReturnBadArgument; break; }
            UInt32 done = 0;
            while (done < h.len && rc == kIOReturnSuccess) {
                UInt16 n = (UInt16)((h.len - done > kChunk) ? kChunk : (h.len - done));
                rc = xfer(h.addr, h.reg + done, rd + done, n, nullptr, 0);
                done += n;
            }
            if (rc == kIOReturnSuccess) rlen = h.len;
            break;
        }
        case kSaOpWBlock: {
            if (!writeAllowed(h.addr, h.reg, payload, in + ip)) { rc = kIOReturnNotPermitted; break; }
            UInt32 done = 0;
            while (done < payload && rc == kIOReturnSuccess) {
                UInt16 n = (UInt16)((payload - done > kChunk) ? kChunk : (payload - done));
                rc = xfer(h.addr, h.reg + done, nullptr, 0, in + ip + done, n);
                done += n;
            }
            break;
        }
        case kSaOpSleep:
            if (h.a > 2000) rc = kIOReturnBadArgument; else IOSleep(h.a);
            break;
        case kSaOpPoll: {
            UInt32 v = 0;
            UInt32 waited = 0;                      // microseconds slept between reads (read time itself is extra)
            if (h.len > 1000) { rc = kIOReturnBadArgument; break; }
            rc = kIOReturnTimeout;
            for (;;) {
                IOReturn r = read32(h.addr, h.reg, &v);
                if (r == kIOReturnSuccess && (v & h.a) == h.b) { rc = kIOReturnSuccess; break; }
                if (waited >= (UInt32)h.len * 1000) { if (r != kIOReturnSuccess) rc = r; break; }
                IODelay(500);
                waited += 500;
            }
            memcpy(rd, &v, 4);
            rlen = 4;
            break;
        }
        case kSaOpUBits: {
            UInt8 be[4];
            UInt32 v = 0;
            rc = read32(h.addr, h.reg, &v);
            if (rc != kIOReturnSuccess) break;
            v = (v & ~h.a) | (h.b & h.a);
            be[0] = (UInt8)(v >> 24); be[1] = (UInt8)(v >> 16); be[2] = (UInt8)(v >> 8); be[3] = (UInt8)v;
            if (!writeAllowed(h.addr, h.reg, 4, be)) { rc = kIOReturnNotPermitted; break; }
            rc = write32(h.addr, h.reg, v);
            memcpy(rd, &v, 4);
            rlen = 4;
            break;
        }
        default:
            rc = kIOReturnUnsupported;
        }

        UInt32 traceValue = 0;
        if (rlen >= 4) memcpy(&traceValue, rd, 4);
        traceOp(h, rc, traceValue);
        ip += payload;
        rh->status = (int32_t)rc;
        rh->len = rlen;
        op += sizeof(SaRespHdr) + pad4(rlen);
        if (rc != kIOReturnSuccess) break;
    }
    IOLockUnlock(lock);
    *outLen = op;
    return kIOReturnSuccess;
}

// ---- speaker-ID strap ---------------------------------------------------------------------------------------------------
// The DSDT lists GPIO 104 as the speaker-ID input (selects the spkid0 / spkid1 tuning). The pin lives in the AMD FCH GPIO
// bank (ACPI device AMDI0030, registry name "GPIO", IODeviceMemory[0] = 0xFED81500, 0x400 bytes, one 32 bit register per
// pin, input level in bit 16). It is read-only here; the pad is left as firmware configured it.
void StrixAmp::readSpeakerId()
{
    constexpr UInt32 kPins[] = { 104, 24, 18 };      // speaker ID, amp reset, amp interrupt
    OSDictionary *m = IOService::nameMatching("GPIO");
    IOService *g = m ? IOService::copyMatchingService(m) : nullptr;
    if (m) m->release();
    if (!g) { IOLog("StrixAmp: GPIO bank not found, speaker ID unknown\n"); return; }
    IOMemoryMap *map = g->mapDeviceMemoryWithIndex(0);
    if (map && map->getLength() >= 0x400) {
        volatile UInt32 *regs = (volatile UInt32 *)map->getVirtualAddress();
        for (UInt32 pin : kPins) {
            UInt32 r = regs[pin];
            char key[32];
            OSNumber *n = OSNumber::withNumber((UInt64)r, 32);
            snprintf(key, sizeof(key), "Gpio%u-Pad", pin);
            if (n) { setProperty(key, n); n->release(); }
            if (pin == 104) {
                spkInfo = 1u | (((r >> 16) & 1) << 1);
                setProperty("SpeakerId", (UInt64)((r >> 16) & 1), 32);
            }
            IOLog("StrixAmp: GPIO%u pad 0x%08x level %u\n", pin, r, (r >> 16) & 1);
        }
    } else {
        IOLog("StrixAmp: GPIO bank map failed\n");
    }
    if (map) map->release();
    g->release();
}

// ---- service ------------------------------------------------------------------------------------------------------------

void StrixAmp::publishProbe()
{
    OSNumber *n;
    for (UInt8 a : kAddrs) {
        char key[24];
        UInt32 devid = 0, revid = 0;
        IOReturn rd = read32(a, kRegDevId, &devid);
        IOReturn rr = (rd == kIOReturnSuccess) ? read32(a, kRegRevId, &revid) : rd;
        snprintf(key, sizeof(key), "Amp%02X-Status", a);
        if ((n = OSNumber::withNumber((UInt64)(UInt32)rd, 32))) { setProperty(key, n); n->release(); }
        if (rd == kIOReturnSuccess) {
            snprintf(key, sizeof(key), "Amp%02X-DEVID", a);
            if ((n = OSNumber::withNumber((UInt64)devid, 32))) { setProperty(key, n); n->release(); }
            snprintf(key, sizeof(key), "Amp%02X-IsCS35L56", a);
            setProperty(key, devid == kDevIdCs35l56);
        }
        if (rr == kIOReturnSuccess) {
            snprintf(key, sizeof(key), "Amp%02X-REVID", a);
            if ((n = OSNumber::withNumber((UInt64)revid, 32))) { setProperty(key, n); n->release(); }
        }
        IOLog("StrixAmp: 0x%02X DEVID rc=0x%x val=0x%08x REVID rc=0x%x val=0x%08x%s\n", a, rd, devid, rr, revid,
              (rd == kIOReturnSuccess && devid == kDevIdCs35l56) ? " (CS35L56)" : "");
    }
}

bool StrixAmp::start(IOService *provider)
{
    IOLog("StrixAmp: TRACE START build=0.2.0 provider=%s class=%s\n", provider->getName(), provider->getMetaClass()->getClassName());
    if (!IOService::start(provider)) return false;
    // the nub's provider is the controller driver that owns the bus
    IOService *p = provider->getProvider();
    if (!p || !p->metaCast("VoodooI2CControllerDriver")) {
        IOLog("StrixAmp: nub provider is %s, not VoodooI2CControllerDriver\n", p ? p->getMetaClass()->getClassName() : "(null)");
        return false;
    }
    ctrl = static_cast<VoodooI2CControllerDriver *>(p);
    ctrl->retain();
    lock = IOLockAlloc();
    if (!lock) return false;

    UInt32 bootArg = 0;
    unsafe = PE_parse_boot_argn("strixamp_unsafe", &bootArg, sizeof(bootArg)) && bootArg == 1;
    bootArg = 0;
    tracing = PE_parse_boot_argn("strixamp_trace", &bootArg, sizeof(bootArg)) && bootArg == 1;
    if (tracing) {
        traceTail = OSArray::withCapacity(128);
        traceBringUp = OSArray::withCapacity(128);
    }
    setProperty("TraceEnabled", tracing);
    setProperty("TraceBuild", "0.2.0");
    IOLog("StrixAmp: TRACE controller=%s trace=%u unsafe=%u\n", ctrl->getName(), tracing, unsafe);

    publishProbe();
    readSpeakerId();
    if (tracing) bootSnapshot();
    setProperty("ProtocolVersion", (UInt64)STRIXAMP_PROTO_VERSION, 32);
    setProperty("UnsafeWrites", unsafe);
    setProperty("ReadOnly", false);
    registerService();
    IOLog("StrixAmp: TRACE REGISTERED speakerIdInfo=%08x\n", spkInfo);
    return true;
}

void StrixAmp::stop(IOService *provider)
{
    IOLog("StrixAmp: TRACE STOP transfers=%llu retries=%llu errors=%llu\n", transfers, retries, errors);
    IOService::stop(provider);
}

void StrixAmp::free()
{
    if (ctrl) { ctrl->release(); ctrl = nullptr; }
    if (lock) { IOLockFree(lock); lock = nullptr; }
    if (traceTail) { traceTail->release(); traceTail = nullptr; }
    if (traceBringUp) { traceBringUp->release(); traceBringUp = nullptr; }
    IOService::free();
}

// ---- user client --------------------------------------------------------------------------------------------------------

class StrixAmpUC : public IOUserClient {
    OSDeclareDefaultStructors(StrixAmpUC)
public:
    bool initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args, IOExternalMethodDispatch *dispatch,
                            OSObject *target, void *reference) override;
private:
    StrixAmp *drv = nullptr;
    bool allowed = false;
};
OSDefineMetaClassAndStructors(StrixAmpUC, IOUserClient)

IOReturn StrixAmp::newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                                 IOUserClient **handler)
{
    StrixAmpUC *uc = OSTypeAlloc(StrixAmpUC);
    if (!uc) return kIOReturnNoMemory;
    if (!uc->initWithTask(owningTask, securityID, type, properties) || !uc->attach(this) || !uc->start(this)) {
        uc->release();
        return kIOReturnError;
    }
    *handler = uc;
    return kIOReturnSuccess;
}

bool StrixAmpUC::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties)
{
    if (!IOUserClient::initWithTask(owningTask, securityToken, type, properties)) return false;
    // register access moves speaker current: root / an administrator only
    allowed = clientHasPrivilege(owningTask, kIOClientPrivilegeAdministrator) == kIOReturnSuccess;
    return true;
}

bool StrixAmpUC::start(IOService *provider)
{
    drv = OSDynamicCast(StrixAmp, provider);
    return drv && IOUserClient::start(provider);
}

IOReturn StrixAmpUC::clientClose()
{
    terminate();
    return kIOReturnSuccess;
}

IOReturn StrixAmpUC::externalMethod(uint32_t selector, IOExternalMethodArguments *a, IOExternalMethodDispatch *, OSObject *,
                                    void *)
{
    if (!drv || !a) return kIOReturnNotAttached;
    if (!allowed) return kIOReturnNotPrivileged;
    if (selector != kSaSelExec) return kIOReturnUnsupported;
    if (!a->structureInput || !a->structureOutput || a->structureInputSize > STRIXAMP_MAX_IO ||
        a->structureOutputSize == 0)
        return kIOReturnBadArgument;
    UInt32 outLen = a->structureOutputSize;
    if (outLen > STRIXAMP_MAX_IO) outLen = STRIXAMP_MAX_IO;
    IOReturn rc = drv->exec((const UInt8 *)a->structureInput, a->structureInputSize, (UInt8 *)a->structureOutput, &outLen);
    a->structureOutputSize = outLen;
    return rc;
}
