// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Wire format between the StrixAmp kext (kexts/StrixAmp/StrixAmp.cpp) and the userland tool (tools/strixampctl.c).
//
// One IOConnectCallStructMethod(selector kSaSelExec) carries a stream of operation records in structureInput (<= 4096
// bytes, the inband limit) and returns one response record per executed operation in structureOutput (<= 4096 bytes).
// All integers are little endian (the host's order). Register addresses and register values on the chip are 32 bit
// big endian on the wire to the amp; the kernel does that conversion, callers use plain host integers.
//
// The stream stops at the first failing operation; that operation's response carries the error and nothing after it
// is executed. A response record is { int32 status, uint32 len } followed by len data bytes padded to 4.
#pragma once
#include <stdint.h>

#define STRIXAMP_PROTO_VERSION 1

enum {
    kSaSelExec = 0,   // execute an operation stream (structureIn -> structureOut)
    kSaSelCount
};

enum {
    kSaOpInfo   = 0,  // -> data: struct SaInfo
    kSaOpRead32 = 1,  // addr, reg -> 4 bytes value
    kSaOpWrite32 = 2, // addr, reg, a = value
    kSaOpRBlock = 3,  // addr, reg, len = byte count (multiple of 4) -> data
    kSaOpWBlock = 4,  // addr, reg, len = byte count (multiple of 4), payload follows the header
    kSaOpSleep  = 5,  // a = milliseconds (<= 2000)
    kSaOpPoll   = 6,  // addr, reg, a = mask, b = expected, len = timeout ms -> 4 bytes last value; status Timeout if unmet
    kSaOpUBits  = 7,  // addr, reg, a = mask, b = value (read-modify-write) -> 4 bytes new value
};

#pragma pack(push, 1)
struct SaOpHdr {
    uint8_t  op;
    uint8_t  addr;    // 7 bit I2C address
    uint16_t len;
    uint32_t reg;
    uint32_t a;
    uint32_t b;
};                    // 16 bytes

struct SaRespHdr {
    int32_t  status;  // kern_return style: 0 = ok
    uint32_t len;
};

struct SaInfo {
    uint32_t protoVersion;
    uint32_t flags;      // bit0: unsafe writes enabled (boot-arg strixamp_unsafe=1)
    uint32_t i2cAddrMask; // bit per allowed 7-bit address >> 0x30: bit0=0x30 ... bit10=0x3A
    uint32_t reserved;
};
#pragma pack(pop)

#define STRIXAMP_MAX_IO 4096
