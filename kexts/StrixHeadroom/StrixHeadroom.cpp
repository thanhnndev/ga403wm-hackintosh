// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// StrixHeadroom: Lilu plugin that removes the mutex contention in CoreDisplay::Display::CurrentHeadroom(), the reason
// WindowServer burns 1100-1400 % CPU when the OLED is driven through the display pipe (docs/890M-TRACE.md,
// "Step13 performance: CurrentHeadroom lock contention").
//
// CurrentHeadroom(qualifier 0) takes Display+0x20 (std::mutex) on every call that finds the result not cached and
// only caches it when EDRDisplay+0x11 ("headroom requested") is set; nothing ever sets that on this machine, so
// every CombineLUTs element of RunFullDisplayPipe locks again and ~24 dispatch_apply workers serialise on it.
// The guarded region only reads fields and (in the "requested" branch) stores the same value + flag, so dropping the
// lock/unlock calls is benign; the headroom math itself is unchanged.
//
// macOS 15.8 (24H32) CoreDisplay, x86_64h dyld cache. The byte patterns are exact: any other build simply does not
// match and stays unpatched (Lilu logs "patch not applied"). Offsets in the trace doc.
#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_user.hpp>

static const char *bootargOff[] { "-strixhroff" };
static const char *bootargDebug[] { "-strixhrdbg" };
static const char *bootargBeta[] { "-strixhrbeta" };

static const char *binaryCoreDisplay = "/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay";
static const char *procWindowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer";

// Display::CurrentHeadroom +0x142 .. : lea r15,[rbx+0x20]; mov rdi,r15; call lock; mov rax,[rbx+0x60]; test rax,rax;
// je; cmp byte [rax+0x11],0; je; mov rdi,r15; call unlock; jmp <recompute>
static const uint8_t findA[] = {
	0x4c, 0x8d, 0x7b, 0x20, 0x4c, 0x89, 0xff, 0xe8, 0x9e, 0x5b, 0x0b, 0x00, 0x48, 0x8b, 0x43, 0x60,
	0x48, 0x85, 0xc0, 0x74, 0x49, 0x80, 0x78, 0x11, 0x00, 0x74, 0x43, 0x4c, 0x89, 0xff, 0xe8, 0x8d,
	0x5b, 0x0b, 0x00, 0xe9, 0xaa, 0xfe, 0xff, 0xff };
static const uint8_t replA[] = {
	0x4c, 0x8d, 0x7b, 0x20, 0x4c, 0x89, 0xff, 0x0f, 0x1f, 0x44, 0x00, 0x00, 0x48, 0x8b, 0x43, 0x60,
	0x48, 0x85, 0xc0, 0x74, 0x49, 0x80, 0x78, 0x11, 0x00, 0x74, 0x43, 0x4c, 0x89, 0xff, 0x0f, 0x1f,
	0x44, 0x00, 0x00, 0xe9, 0xaa, 0xfe, 0xff, 0xff };

// default (not requested) result path: store xmm0; mov rdi,r15; call unlock; reload xmm0
static const uint8_t findB[] = {
	0xf3, 0x0f, 0x11, 0x45, 0xe4, 0x4c, 0x89, 0xff, 0xe8, 0xfe, 0x5a, 0x0b, 0x00, 0xf3, 0x0f, 0x10, 0x45, 0xe4 };
static const uint8_t replB[] = {
	0xf3, 0x0f, 0x11, 0x45, 0xe4, 0x4c, 0x89, 0xff, 0x0f, 0x1f, 0x44, 0x00, 0x00, 0xf3, 0x0f, 0x10, 0x45, 0xe4 };

static UserPatcher::BinaryModPatch patches[] {
	{ CPU_TYPE_X86_64, 0, findA, replA, sizeof(findA), 0, 1, UserPatcher::FileSegment::SegmentTextText, 1 },
	{ CPU_TYPE_X86_64, 0, findB, replB, sizeof(findB), 0, 1, UserPatcher::FileSegment::SegmentTextText, 1 },
};
static UserPatcher::BinaryModInfo binaryMod { binaryCoreDisplay, patches, arrsize(patches) };
static UserPatcher::ProcInfo procInfo { procWindowServer, sizeof("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer") - 1, 1 };

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal,
	bootargOff, arrsize(bootargOff),
	bootargDebug, arrsize(bootargDebug),
	bootargBeta, arrsize(bootargBeta),
	KernelVersion::Sequoia,
	KernelVersion::Sequoia,
	[]() {
		lilu.onProcLoadForce(&procInfo, 1, nullptr, nullptr, &binaryMod, 1);
	}
};
