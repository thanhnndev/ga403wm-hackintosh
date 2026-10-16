// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// The IOSkywalk packet pool / queue factories the native interface calls (stage 2). The SDK's IOSkywalk headers are not used:
// they are older than 24H32 (docs/IO80211-ABI-2.md section 3). Every declaration below is a static factory whose mangled name is
// in the 24H32 method dumps (abi/native-wifi/24H32/round3/IOSkywalk*.methods.txt); `tools/check_native_symbols.py` compares the
// object's undefined symbols with those dumps. The classes are opaque: they are only held by pointer, retained and released,
// disabled (IOEventSource::disable is virtual slot 45 of IOSkywalkPacketQueue's vtable) and put on the work queue as event sources.
#pragma once
#include <IOKit/IOEventSource.h>
#include <IOKit/IOService.h>
#include <stdint.h>

class IOSkywalkPacketQueue;
class IOSkywalkPacket : public OSObject {
public:
    uint32_t getDataLength() const;
    uint32_t getBufferSize() const;
    uint32_t getPacketBufferCount() const;
    uint16_t getDataOffset() const;
    void *getDataVirtualAddress() const;
    IOReturn prepareWithQueue(IOSkywalkPacketQueue *, uint32_t direction, uint32_t options);
    IOReturn setDataOffsetAndLength(uint16_t offset, uint32_t length);
};

// The plain pool's type 1 factory creates IOSkywalkNetworkPacket (round14).
// These are nonvirtual wrappers around the kernel packet metadata API.
class IOSkywalkNetworkPacket : public IOSkywalkPacket {
public:
    IOReturn setHeadroom(uint8_t);
    IOReturn setLinkHeaderLength(uint8_t);
    IOReturn setIsLinkBroadcast(bool);
    IOReturn setIsLinkMulticast(bool);
    IOReturn setRxChecksumInfo(uint32_t, uint16_t);
};

class IOSkywalkPacketBufferPool : public OSObject {
public:
    // Six u32 copied 1:1 into the pool (ABI-2 section 2 "Pools and queues"); the rest of Apple's 0x30-byte stack block is zero.
    struct PoolOptions {
        uint32_t packets0;       // +0x00  (== +4 in Apple's driver; field name not determined)
        uint32_t packets1;       // +0x04
        uint32_t bufferSize;     // +0x08  0x800 (2 KiB) for the common pool
        uint32_t one;            // +0x0c  1
        uint32_t zero;           // +0x10  0
        uint32_t flags;          // +0x14  1 (bit 0 -> pool flag 0x20)
        uint8_t pad[0x30 - 6 * 4];
    };
    // __ZN25IOSkywalkPacketBufferPool8withNameEPKcP8OSObjectjPKNS_11PoolOptionsE; Apple passes packetType 1
    static IOSkywalkPacketBufferPool *withName(const char *name, OSObject *owner, uint32_t packetType, const PoolOptions *opts);
    IOReturn allocatePacket(uint32_t type, IOSkywalkPacket **packet, uint32_t options);
    void deallocatePacket(IOSkywalkPacket *packet);
};

// IOSkywalkPacketQueue derives from IOEventSource (its vtable carries IOEventSource's checkForWork, setWorkLoop, ...).
class IOSkywalkPacketQueue : public IOEventSource {};

// Callback types follow the mangled names exactly: owner, queue, packet array, count, refcon -> u32. The packet-array constness
// differs per class (Tx submission / Rx submission: `IOSkywalkPacket *const *`, completions: `IOSkywalkPacket **`).
class IOSkywalkTxSubmissionQueue;
typedef uint32_t (*IOSkywalkTxSubmissionAction)(OSObject *, IOSkywalkTxSubmissionQueue *, IOSkywalkPacket *const *, uint32_t, void *);
class IOSkywalkTxSubmissionQueue : public IOSkywalkPacketQueue {
public:
    IOReturn requestDequeue(void *context, uint32_t options);
    // __ZN26IOSkywalkTxSubmissionQueue8withPoolEP25IOSkywalkPacketBufferPooljjP8OSObjectPFjS3_PS_PKP15IOSkywalkPacketjPvES9_j
    static IOSkywalkTxSubmissionQueue *withPool(IOSkywalkPacketBufferPool *pool, uint32_t capacity, uint32_t queueId, OSObject *owner,
                                                IOSkywalkTxSubmissionAction action, void *refcon, uint32_t options);
};

class IOSkywalkRxSubmissionQueue;
typedef uint32_t (*IOSkywalkRxSubmissionAction)(OSObject *, IOSkywalkRxSubmissionQueue *, IOSkywalkPacket *const *, uint32_t, void *);
class IOSkywalkRxSubmissionQueue : public IOSkywalkPacketQueue {
public:
    // __ZN26IOSkywalkRxSubmissionQueue8withPoolEP25IOSkywalkPacketBufferPooljjjP8OSObjectPFjS3_PS_PKP15IOSkywalkPacketjPvES9_j
    // (pool, capacity, queueId, serviceClass, owner, action, refcon, options)
    static IOSkywalkRxSubmissionQueue *withPool(IOSkywalkPacketBufferPool *pool, uint32_t capacity, uint32_t queueId, uint32_t serviceClass,
                                                OSObject *owner, IOSkywalkRxSubmissionAction action, void *refcon, uint32_t options);
};

class IOSkywalkTxCompletionQueue;
typedef uint32_t (*IOSkywalkTxCompletionAction)(OSObject *, IOSkywalkTxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *);
class IOSkywalkTxCompletionQueue : public IOSkywalkPacketQueue {
public:
    IOReturn enqueuePackets(IOSkywalkPacket *const *packets, uint32_t count, uint32_t options);
    // __ZN26IOSkywalkTxCompletionQueue8withPoolEP25IOSkywalkPacketBufferPooljjP8OSObjectPFjS3_PS_PP15IOSkywalkPacketjPvES8_j
    static IOSkywalkTxCompletionQueue *withPool(IOSkywalkPacketBufferPool *pool, uint32_t capacity, uint32_t queueId, OSObject *owner,
                                                IOSkywalkTxCompletionAction action, void *refcon, uint32_t options);
};

class IOSkywalkRxCompletionQueue;
typedef uint32_t (*IOSkywalkRxCompletionAction)(OSObject *, IOSkywalkRxCompletionQueue *, IOSkywalkPacket **, uint32_t, void *);
class IOSkywalkRxCompletionQueue : public IOSkywalkPacketQueue {
public:
    IOReturn enqueuePackets(IOSkywalkPacket *const *packets, uint32_t count, uint32_t options);
    // __ZN26IOSkywalkRxCompletionQueue8withPoolEP25IOSkywalkPacketBufferPooljjP8OSObjectPFjS3_PS_PP15IOSkywalkPacketjPvES8_j
    static IOSkywalkRxCompletionQueue *withPool(IOSkywalkPacketBufferPool *pool, uint32_t capacity, uint32_t queueId, OSObject *owner,
                                                IOSkywalkRxCompletionAction action, void *refcon, uint32_t options);
};
