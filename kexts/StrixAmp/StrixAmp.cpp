// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// StrixAmp: read-only probe of the Cirrus Logic CS35L56 speaker amplifiers of the GA403WM (docs/AUDIO-ROG.md).
//
// The DSDT declares the amps as \_SB.I2CB.SPKR (_HID CSC3556, _SUB 10431024): I2C slave addresses 0x30, 0x31 (and 0x3A) at
// 1 MHz on I2CB, reset GPIO 24, speaker-ID GPIO 104, interrupt GPIO 18, "cirrus,dev-index" {0x30, 0x31}. VoodooI2C already
// owns I2CB and publishes a VoodooI2CDeviceNub named CSC3556 for the first address (0x30); this kext attaches to that nub
// and does exactly two single-register reads (DEVID and REVID, 32-bit big-endian register addresses and values as in the
// Linux cs35l56 I2C regmap). It never writes a register, does not touch the reset or boost state, and loads no firmware.
//
// Result is published as properties on this service (ioreg -c StrixAmp): "ProbeStatus" (kern_return), "DEVID", "REVID".
// A CS35L56 answers DEVID = 0x00035A56. A NAK / timeout means the amp is in reset or unpowered (nothing is wrong with
// the kext); that is the answer this probe exists to give.
//
// Credits (see NOTICE.md): register map and I2C framing from the Linux cs35l56 driver (Cirrus Logic, GPL-2.0); only
// interface facts (register numbers, access width) are used, no code is copied.
#include <IOKit/IOLib.h>
#include <IOKit/IOService.h>

// The slice of VoodooI2C's nub API this kext calls (VoodooI2C 2.9.1, VoodooI2CDeviceNub.hpp). Only a non-virtual method is
// used, so no vtable or layout knowledge is needed; the symbol is exported by com.alexandred.VoodooI2C.
class VoodooI2CDeviceNub : public IOService {
public:
    IOReturn writeReadI2C(UInt8 *write_buffer, UInt16 write_length, UInt8 *read_buffer, UInt16 read_length);
};

namespace {
constexpr UInt32 kRegDevId = 0x00000000;
constexpr UInt32 kRegRevId = 0x00000004;
constexpr UInt32 kDevIdCs35l56 = 0x00035A56;
constexpr int kTries = 5;
}

class StrixAmp : public IOService {
    OSDeclareDefaultStructors(StrixAmp)
public:
    bool start(IOService *provider) override;
private:
    IOReturn readReg(VoodooI2CDeviceNub *nub, UInt32 reg, UInt32 *value);
};

OSDefineMetaClassAndStructors(StrixAmp, IOService)

IOReturn StrixAmp::readReg(VoodooI2CDeviceNub *nub, UInt32 reg, UInt32 *value)
{
    UInt8 addr[4] = { (UInt8)(reg >> 24), (UInt8)(reg >> 16), (UInt8)(reg >> 8), (UInt8)reg };
    UInt8 data[4] = { 0, 0, 0, 0 };
    IOReturn rc = kIOReturnError;
    for (int i = 0; i < kTries; i++) {
        rc = nub->writeReadI2C(addr, sizeof(addr), data, sizeof(data));
        if (rc == kIOReturnSuccess) break;
        IOSleep(10);
    }
    if (rc == kIOReturnSuccess)
        *value = ((UInt32)data[0] << 24) | ((UInt32)data[1] << 16) | ((UInt32)data[2] << 8) | data[3];
    return rc;
}

bool StrixAmp::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    auto *nub = static_cast<VoodooI2CDeviceNub *>(provider);

    UInt32 devid = 0, revid = 0;
    IOReturn rcDev = readReg(nub, kRegDevId, &devid);
    IOReturn rcRev = (rcDev == kIOReturnSuccess) ? readReg(nub, kRegRevId, &revid) : rcDev;

    setProperty("ProbeStatus", (UInt64)(UInt32)rcDev, 32);
    setProperty("ProbeStatusRevId", (UInt64)(UInt32)rcRev, 32);
    if (rcDev == kIOReturnSuccess) {
        setProperty("DEVID", (UInt64)devid, 32);
        setProperty("DEVID_IsCS35L56", devid == kDevIdCs35l56);
    }
    if (rcRev == kIOReturnSuccess) setProperty("REVID", (UInt64)revid, 32);
    setProperty("ReadOnly", true);

    IOLog("StrixAmp: CSC3556 @0x30 DEVID rc=0x%x val=0x%08x REVID rc=0x%x val=0x%08x%s\n", rcDev, devid, rcRev, revid,
          (rcDev == kIOReturnSuccess && devid == kDevIdCs35l56) ? " (CS35L56)" : "");
    registerService();
    return true;
}
