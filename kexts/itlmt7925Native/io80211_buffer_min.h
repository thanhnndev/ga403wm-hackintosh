// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Minimal declarations of the IO80211Family classes the AWDL receive path needs (docs/ROADMAP-AWDL.md 10.23).
//
// The Family's AWDL peer manager takes the received action frame as an IO80211Buffer - a real C++ object. It calls virtual
// methods on it (getLength(), getBytesNoCopy(), getCursor()), so handing it a plain {data, len} pair makes it call through the
// frame bytes as if they were a vtable: a kernel panic in IO80211VirtualInterface::sendToBpfTap (Kernel-2026-10-22-124437).
//
// Only symbols are used here, never the layout of the objects themselves, so the declarations only have to produce the same
// mangled names as the ones IO80211Family exports: the class names, the member names and the parameter types have to be
// spelled the same way. Everything below is exported by com.apple.iokit.IO80211Family.
//
// Which pool: IO80211Buffer::allocBufferSingle() looks like the obvious entry point, but it is meant for the controller and
// hands the pool options a DMA segment (opts+8) that only Apple's driver has - with a zero there the static pool fails and
// its own error path crashes in IO80211StaticBufferPool::flushPool (Kernel-2026-10-22-131442). The dynamic pool allocates its
// slabs itself (IO80211BufferSlab::withOptions) and builds plain IO80211Buffers through IO80211Buffer::allocBuffer(), so it
// works from here and its buffers support the base writeBytes()/setLength().
#pragma once
#include <stdint.h>

class IO80211Buffer;
class IO80211DynamicBufferPool;

// IO80211BufferPoolOptions: the fields the Family reads out of it. The pool size/geometry comes from count and size; name is
// copied into the pool's debug name; byte 0x38 bit 0 forces the static pool (left zero, the static pool needs Apple's DMA
// segment).
struct IO80211BufferPoolOptions {
    unsigned long count;      // +0x00  how many buffers
    unsigned long size;       // +0x08  bytes per buffer
    unsigned long rsvd0;      // +0x10
    const char   *name;       // +0x18
    void         *rsvd1;      // +0x20
    unsigned int  rsvd2;      // +0x28
    unsigned int  rsvd3;      // +0x2c
    unsigned long rsvd4;      // +0x30
    unsigned int  rsvd5;      // +0x38  bit 0: force the static pool
    unsigned int  rsvd6;      // +0x3c
};

// IO80211Buffer: the Family's buffer. Only the members used here; the parameter types are spelled out (unsigned long /
// unsigned int) instead of uint64_t / uint32_t because the kernel's libc++ defines those as "unsigned long long" /
// "unsigned int" and the mangled name has to match the exported one.
class IO80211Buffer {
public:
    void writeBytes(unsigned long offset, const void *data, unsigned long len);
    void setLength(unsigned long len);
    void returnBuffer();
};

// IO80211DynamicBufferPool: a pool that allocates its slabs itself, so it needs nothing from the controller.
class IO80211DynamicBufferPool {
public:
    static IO80211DynamicBufferPool *withOptions(IO80211BufferPoolOptions *opts);
    IO80211Buffer *getBuffer();
    void returnBuffer(IO80211Buffer *buf);
    void free();
};
