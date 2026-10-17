// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// The few CoreCapture / IO80211 factory functions the native Wi-Fi stub calls. Symbols and signatures come from Apple's own
// exports in the kernel collection (docs/IO80211-ABI-2.md "Extraction round 4" and "Native stub" for 24H32; re-checked against
// 25G241 with tools/check_native_symbols.py and tools/check_kext_links.py); the classes are
// opaque here and are used only through these static factories and OSObject's retain/release.
#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOWorkLoop.h>
#include <stdint.h>

// Option blocks: Apple allocates and zeroes them (IOMallocZeroData). Offsets are documented in ABI-2 section 1 and the stub
// writes only the ones listed there.
static const size_t kCCPipeOptionsSize = 0x350;
static const size_t kCCStreamOptionsSize = 0x358;
struct CCPipeOptions;
struct CCStreamOptions;

class CCPipe {
public:
    // __ZN6CCPipe21withOwnerNameCapacityEP9IOServicePKcS3_PK13CCPipeOptions; options+0 selects the class: 0 CCLogPipe, 1 CCDataPipe
    static CCPipe *withOwnerNameCapacity(IOService *owner, const char *ownerId, const char *name, const CCPipeOptions *opts);
};

// CCPipe::startPipe is virtual (slot +0x868 in both the CCLogPipe and CCDataPipe vtables of 25G241) and the class hierarchy
// is far too wide to declare in full, so the slot is called raw. AppleBCMWLANBusInterfacePCIe::createCrashTracerLogger ends
// with exactly this on the data pipe it created (`mov rdi, [ivars+0xf20]; mov rax, [rdi]; call [rax+0x868]`). startPipe runs
// the pipe's own start(provider) - on 25G241 CCDataPipe::start creates the notify timer (stored at pipe_ivars+0x90 -> +0x38,
// handler CCDataPipe::notifyTimeout), adds it to the provider's work loop, sets IOClass/name, publishes resource "CCPipe" and
// registers the service in the CoreCapture plane; CCLogPipe::start is the log equivalent. The factories only init, and an
// unstarted data pipe merely looks alive: CCDataPipe::enqueueBlob dereferences that timer without a null check, so the first
// fault report the family flushes through it panicked the kernel inside com.apple.driver.corecapture
// (2026-10-17 10:30 and 10:37, CCDataPipe::enqueueBlob+0x128 with RDI = 0; see docs/native-wifi-results/20261017-panic-corecapture/).
inline bool ccPipeStartPipe(void *pipe)
{
    if (!pipe) return false;
    void **vptr = *(void ***)pipe;
    return ((bool (*)(void *))vptr[0x868 / 8])(pipe);
}

class CCStream {
public:
    // __ZN8CCStream15withPipeAndNameEP6CCPipePKcPK15CCStreamOptions; options+0 selects the class: 0 CCLogStream, 1 CCDataStream
    static CCStream *withPipeAndName(CCPipe *pipe, const char *name, const CCStreamOptions *opts);
};

class CCDataStream;
class CCFaultReporter {
public:
    // __ZN15CCFaultReporter18withStreamWorkloopEP12CCDataStreamP10IOWorkLoop; both arguments must be non-null
    static CCFaultReporter *withStreamWorkloop(CCDataStream *stream, IOWorkLoop *wl);
};

class IO80211FaultReporter {
public:
    // __ZN20IO80211FaultReporter15allocWithParamsEP15CCFaultReporter; IO80211Controller::getFaultReporterFromDriver returns this
    static IO80211FaultReporter *allocWithParams(CCFaultReporter *reporter);
};
