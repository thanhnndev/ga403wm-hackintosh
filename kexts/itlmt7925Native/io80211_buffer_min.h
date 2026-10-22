// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Minimal declarations of the two IO80211Family classes the AWDL receive path needs (docs/ROADMAP-AWDL.md 10.23, 10.24).
//
// The Family's AWDL peer manager takes the received action frame as an IO80211Buffer - a real C++ object. It calls virtual
// methods on it (getLength(), getBytesNoCopy(), getCursor()), so handing it a plain {data, len} pair makes it call through the
// frame bytes as if they were a vtable: a kernel panic in IO80211VirtualInterface::sendToBpfTap (Kernel-2026-10-22-124437).
//
// Only the symbols are used here, never the layout, so the declarations only have to produce the same mangled names as the
// ones in IO80211Family: the class names, the member names and the parameter types have to be spelled exactly the same way.
// All three members below are exported by com.apple.iokit.IO80211Family.
#pragma once
#include <stdint.h>

class IO80211BufferPool;

// IO80211Buffer: the Family's buffer. allocBufferSingle() is the Family's own entry point: it creates a one-buffer pool of
// the requested size, allocates the buffer from it and hands the pool back so that it can be released later.
class IO80211Buffer {
public:
    // The parameter types are spelled out (unsigned long / unsigned int) instead of uint64_t / uint32_t: the kernel's libc++
    // defines those as "unsigned long long" / "unsigned int", and the mangled name has to be the one IO80211Family exports
    // (the length is an "unsigned long" there).
    //
    // The argument ORDER is (allocator type, size), not (size, flags). In IO80211Family 25G241 (0xffffff800233b71e)
    // allocBufferSingle builds an IO80211BufferPoolOptions on the stack with the second argument at options+0x08 and the
    // first at options+0x28, and IO80211StaticBufferPool::initWithOptions (0xffffff80021889ee) treats options+0x08 as the
    // buffer size: it rounds it to 8, derives the slab element size and count from it, and rejects 0 before it links the
    // pool's lists. The first argument is the allocator type the slab hands to kalloc (Apple's own callers pass 0 for the
    // LQM ring buffer and 0x10003 for the IOUC event pipes).
    //
    // Both halves of that were wrong here: the driver passed (2048, 0), so the pool was asked for buffers of size 0. The
    // Family's error path in IO80211StaticBufferPool::withOptions then calls free() on the half-built pool, free() calls
    // flushPool(), and flushPool() walks the list anchor that initWithOptions never initialised (the kalloc_type IVars are
    // zeroed) - a page fault at CR2=0x8 (Kernel-2026-10-22-131442).
    static IO80211Buffer *allocBufferSingle(unsigned int allocType, unsigned long size, IO80211BufferPool **pool, const char *name);
    void writeBytes(unsigned long offset, const void *data, unsigned long len);
    void setLength(unsigned long len);
    void returnBuffer();
};

// IO80211BufferPool: the pool allocBufferSingle() hands back.
class IO80211BufferPool {
public:
    void free();
};
