// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Minimal declarations of the two IO80211Family classes the AWDL receive path needs (docs/ROADMAP-AWDL.md 10.23).
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
    static IO80211Buffer *allocBufferSingle(unsigned int size, unsigned long flags, IO80211BufferPool **pool, const char *name);
    void writeBytes(unsigned long offset, const void *data, unsigned long len);
    void setLength(unsigned long len);
    void returnBuffer();
};

// IO80211BufferPool: the pool allocBufferSingle() hands back.
class IO80211BufferPool {
public:
    void free();
};
