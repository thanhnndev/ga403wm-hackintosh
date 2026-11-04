// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// StrixSbxMap: Lilu plugin that lets the Safari/WebKit GPU process map the NVMTL Metal plugin binaries (Radeon 890M
// WebGL) although its sandbox profile only allows file-map-executable for sealed /System paths and cryptex grafts.
// Design and test plan: docs/890M-ROADMAP.md, "Safari WebGL: Sandbox mmap exception".
//
// MACF policies are AND-ed, so a second policy cannot allow what Sandbox denies. Instead this routes Sandbox's own
// hook_file_check_mmap (macOS 26, Sandbox 300.0):
//
//     int hook_file_check_mmap(cred, fileglob *fg, label *, int prot, int flags, uint64_t pos, int *maxprot)
//         if (!(prot & PROT_EXEC)) return 0;  vp = fg_get_vnode(fg);  ...  return cred_sb_evaluate(cred, 0x13, &ctx);
//
// The original always runs first. A non-zero (deny) result is turned into 0 only when ALL of these hold:
//   - enabled (boot-arg -strixsbxoff / sysctl debug.strixsbx.enable=0 turn it off),
//   - prot has PROT_EXEC (the hook only evaluates then anyway),
//   - the calling process name is on the process list (default: com.apple.WebKit.GPU),
//   - the vnode is a regular file whose path is on the pinned list, and
//   - the code signature blob registered on that vnode (dyld does F_ADDFILESIGS before mmap) covers the mapped offset
//     and its cdhash equals the cdhash pinned for that path.
// Anything else keeps Sandbox's answer (fail closed). The pinned (path, cdhash) list comes from the IOKit personality
// (written by scripts/macos-install-strixsbxmap.sh) and can be replaced at runtime by root through
// sysctl debug.strixsbx.files, so a plugin rebuild only needs `--refresh`, not a reboot.
//
// Before routing, the hook's prologue is checked (test cl,4 and a call to fg_get_vnode in the first 0x40 bytes); on
// any other Sandbox build the plugin does nothing.
#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_util.hpp>
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSString.h>
#include <sys/vnode.h>
#include <sys/proc.h>
#include <sys/mman.h>
#include <sys/errno.h>
#include <sys/sysctl.h>
#include <sys/kauth.h>
#include <string.h>

struct fileglob;
struct label;
struct cs_blob;

static const char *bootargOff[] { "-strixsbxoff" };
static const char *bootargDebug[] { "-strixsbxdbg" };
static const char *bootargBeta[] { "-strixsbxbeta" };

static const char *pathSandbox[] { "/System/Library/Extensions/Sandbox.kext/Contents/MacOS/Sandbox" };
static KernelPatcher::KextInfo kextSandbox { "com.apple.security.sandbox", pathSandbox, arrsize(pathSandbox), { true }, {},
	KernelPatcher::KextInfo::Unloaded };

static constexpr size_t MaxFiles = 16, MaxProcs = 8, PathLen = 256, ProcLen = 64, CdLen = 20, LogLimit = 64;

struct PinnedFile {
	char path[PathLen];
	uint8_t cdhash[CdLen];
};

static PinnedFile gFiles[MaxFiles];
static size_t gNumFiles;
static char gProcs[MaxProcs][ProcLen] { "com.apple.WebKit.GPU" };
static size_t gNumProcs = 1;
static IOLock *gLock;
static int gEnable = 1;
static bool gRouted;
static const char *gRouteError = "not attempted";
static volatile SInt32 gAllowed, gStale, gNoBlob, gUnlisted, gLogged;
static char gLast[PathLen + ProcLen + 64];
static char gIoBuf[MaxFiles * (2 * CdLen + 2 + PathLen) + 16];

using t_hook = int (*)(kauth_cred_t, fileglob *, label *, int, int, uint64_t, int *);
using t_fg_get_vnode = vnode_t (*)(fileglob *);
using t_blob_get = cs_blob *(*)(vnode_t, cpu_type_t, cpu_subtype_t, off_t);
using t_cdhash = const uint8_t *(*)(cs_blob *);

static mach_vm_address_t orgHook;
static t_fg_get_vnode fgGetVnode;
static t_blob_get blobGet;
static t_cdhash blobCdhash;

static int hexval(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static bool parseCdhash(const char *s, size_t n, uint8_t out[CdLen]) {
	if (n != 2 * CdLen) return false;
	for (size_t i = 0; i < CdLen; i++) {
		int hi = hexval(s[2 * i]), lo = hexval(s[2 * i + 1]);
		if (hi < 0 || lo < 0) return false;
		out[i] = static_cast<uint8_t>(hi << 4 | lo);
	}
	return true;
}

static void hexOut(const uint8_t *cd, char out[2 * CdLen + 1]) {
	static const char d[] = "0123456789abcdef";
	for (size_t i = 0; i < CdLen; i++) {
		out[2 * i] = d[cd[i] >> 4];
		out[2 * i + 1] = d[cd[i] & 15];
	}
	out[2 * CdLen] = 0;
}

static bool logOnce() {
	return OSIncrementAtomic(&gLogged) < static_cast<SInt32>(LogLimit);
}

// Called only after Sandbox denied an executable mapping.
static bool maybeAllow(fileglob *fg, uint64_t pos) {
	char proc[ProcLen];
	proc_selfname(proc, sizeof(proc));

	IOLockLock(gLock);
	bool procOk = false;
	for (size_t i = 0; i < gNumProcs && !procOk; i++)
		procOk = strncmp(proc, gProcs[i], ProcLen) == 0;
	IOLockUnlock(gLock);
	if (!procOk) return false;

	vnode_t vp = fgGetVnode(fg);
	if (!vp || vnode_vtype(vp) != VREG) return false;

	char path[PathLen];
	int len = sizeof(path);
	if (vn_getpath(vp, path, &len) != 0) return false;
	static const char dataPrefix[] = "/System/Volumes/Data/";
	const char *p = path;
	if (strncmp(p, dataPrefix, sizeof(dataPrefix) - 1) == 0) p += sizeof(dataPrefix) - 2;   // keep the leading '/'

	uint8_t want[CdLen];
	bool listed = false;
	IOLockLock(gLock);
	for (size_t i = 0; i < gNumFiles && !listed; i++) {
		if (strncmp(p, gFiles[i].path, PathLen) == 0) {
			memcpy(want, gFiles[i].cdhash, CdLen);
			listed = true;
		}
	}
	IOLockUnlock(gLock);
	if (!listed) {
		OSIncrementAtomic(&gUnlisted);
		if (strncmp(p, "/Library/GPUBundles/", 20) == 0 && logOnce())
			SYSLOG("sbxmap", "%s: %s is not pinned, Sandbox deny kept", proc, p);
		return false;
	}

	cs_blob *blob = blobGet(vp, -1, -1, static_cast<off_t>(pos));
	const uint8_t *cd = blob ? blobCdhash(blob) : nullptr;
	if (!cd) {
		OSIncrementAtomic(&gNoBlob);
		if (logOnce()) SYSLOG("sbxmap", "%s: %s has no code signature at offset 0x%llx, deny kept", proc, p, pos);
		return false;
	}
	if (memcmp(cd, want, CdLen) != 0) {
		OSIncrementAtomic(&gStale);
		if (logOnce()) {
			char have[2 * CdLen + 1];
			hexOut(cd, have);
			SYSLOG("sbxmap", "%s: %s cdhash %s is not the pinned one (run the installer with --refresh), deny kept",
			       proc, p, have);
		}
		return false;
	}

	OSIncrementAtomic(&gAllowed);
	IOLockLock(gLock);
	snprintf(gLast, sizeof(gLast), "%s %s", proc, p);
	IOLockUnlock(gLock);
	if (logOnce()) SYSLOG("sbxmap", "%s: allowed file-map-executable %s (pinned cdhash)", proc, p);
	return true;
}

static int wrapFileCheckMmap(kauth_cred_t cred, fileglob *fg, label *lab, int prot, int flags, uint64_t pos, int *maxprot) {
	int r = FunctionCast(wrapFileCheckMmap, orgHook)(cred, fg, lab, prot, flags, pos, maxprot);
	if (r == 0 || !(prot & PROT_EXEC) || !gEnable || !fg) return r;
	return maybeAllow(fg, pos) ? 0 : r;
}

// test cl,4 and call rel32 -> fg_get_vnode within the first 0x40 bytes of the hook (see the header comment).
static bool hookLooksRight(mach_vm_address_t hook) {
	auto b = reinterpret_cast<const uint8_t *>(hook);
	bool testProt = false, callsFg = false;
	for (size_t i = 0; i + 5 <= 0x40; i++) {
		if (b[i] == 0xf6 && b[i + 1] == 0xc1 && b[i + 2] == 0x04) testProt = true;
		if (b[i] == 0xe8) {
			int32_t rel;
			memcpy(&rel, b + i + 1, sizeof(rel));
			if (hook + i + 5 + static_cast<mach_vm_address_t>(static_cast<int64_t>(rel)) == reinterpret_cast<mach_vm_address_t>(fgGetVnode)) callsFg = true;
		}
	}
	return testProt && callsFg;
}

static void onPatcher(void *, KernelPatcher &patcher) {
	fgGetVnode = reinterpret_cast<t_fg_get_vnode>(patcher.solveSymbol(KernelPatcher::KernelID, "_fg_get_vnode"));
	blobGet = reinterpret_cast<t_blob_get>(patcher.solveSymbol(KernelPatcher::KernelID, "_ubc_cs_blob_get"));
	blobCdhash = reinterpret_cast<t_cdhash>(patcher.solveSymbol(KernelPatcher::KernelID, "_csblob_get_cdhash"));
	patcher.clearError();
	if (!fgGetVnode || !blobGet || !blobCdhash) {
		gRouteError = "kernel symbols missing";
		SYSLOG("sbxmap", "kernel symbols missing (fg_get_vnode %d ubc_cs_blob_get %d csblob_get_cdhash %d), inactive",
		       fgGetVnode != nullptr, blobGet != nullptr, blobCdhash != nullptr);
	}
}

static void onKext(void *, KernelPatcher &patcher, size_t index, mach_vm_address_t, size_t) {
	if (index != kextSandbox.loadIndex || gRouted) return;
	if (!fgGetVnode || !blobGet || !blobCdhash) return;
	mach_vm_address_t hook = patcher.solveSymbol(index, "_hook_file_check_mmap");
	if (!hook) {
		patcher.clearError();
		gRouteError = "_hook_file_check_mmap not found";
		SYSLOG("sbxmap", "%s, inactive", gRouteError);
		return;
	}
	if (!hookLooksRight(hook)) {
		gRouteError = "hook prologue differs (other Sandbox build)";
		SYSLOG("sbxmap", "%s, inactive", gRouteError);
		return;
	}
	KernelPatcher::RouteRequest req("_hook_file_check_mmap", wrapFileCheckMmap, orgHook);
	if (!patcher.routeMultiple(index, &req, 1)) {
		patcher.clearError();
		gRouteError = "route failed";
		SYSLOG("sbxmap", "%s, inactive", gRouteError);
		return;
	}
	gRouted = true;
	gRouteError = "none";
	SYSLOG("sbxmap", "routed Sandbox hook_file_check_mmap");
}

// "cdhash:/path;cdhash:/path" (replaces the whole list). Caller holds gLock.
static int parseFiles(const char *s) {
	PinnedFile tmp[MaxFiles];
	size_t n = 0;
	while (*s) {
		while (*s == ';' || *s == ' ' || *s == '\n') s++;
		if (!*s) break;
		const char *colon = strchr(s, ':');
		if (!colon || n == MaxFiles) return EINVAL;
		const char *end = colon;
		while (*end && *end != ';' && *end != '\n') end++;
		size_t plen = static_cast<size_t>(end - colon - 1);
		if (plen == 0 || plen >= PathLen || colon[1] != '/') return EINVAL;
		if (!parseCdhash(s, static_cast<size_t>(colon - s), tmp[n].cdhash)) return EINVAL;
		memcpy(tmp[n].path, colon + 1, plen);
		tmp[n].path[plen] = 0;
		n++;
		s = end;
	}
	memcpy(gFiles, tmp, sizeof(PinnedFile) * n);
	gNumFiles = n;
	return 0;
}

// "name,name". Caller holds gLock.
static int parseProcs(const char *s) {
	char tmp[MaxProcs][ProcLen];
	size_t n = 0;
	while (*s) {
		while (*s == ',' || *s == ' ' || *s == '\n') s++;
		if (!*s) break;
		const char *end = s;
		while (*end && *end != ',' && *end != '\n') end++;
		size_t len = static_cast<size_t>(end - s);
		if (n == MaxProcs || len >= ProcLen) return EINVAL;
		memcpy(tmp[n], s, len);
		tmp[n][len] = 0;
		n++;
		s = end;
	}
	memcpy(gProcs, tmp, sizeof(tmp[0]) * n);
	gNumProcs = n;
	return 0;
}

static void formatFiles(char *out, size_t cap) {
	size_t o = 0;
	out[0] = 0;
	for (size_t i = 0; i < gNumFiles && o < cap; i++) {
		char hex[2 * CdLen + 1];
		hexOut(gFiles[i].cdhash, hex);
		o += (size_t)snprintf(out + o, cap - o, "%s%s:%s", i ? ";" : "", hex, gFiles[i].path);
	}
}

static void formatProcs(char *out, size_t cap) {
	size_t o = 0;
	out[0] = 0;
	for (size_t i = 0; i < gNumProcs && o < cap; i++)
		o += (size_t)snprintf(out + o, cap - o, "%s%s", i ? "," : "", gProcs[i]);
}

static int filesSysctl SYSCTL_HANDLER_ARGS {
	IOLockLock(gLock);
	if (arg2 == 0) formatFiles(gIoBuf, sizeof(gIoBuf));
	else formatProcs(gIoBuf, sizeof(gIoBuf));
	int e = sysctl_handle_string(oidp, gIoBuf, sizeof(gIoBuf), req);
	if (!e && req->newptr) {
		gIoBuf[sizeof(gIoBuf) - 1] = 0;
		e = arg2 == 0 ? parseFiles(gIoBuf) : parseProcs(gIoBuf);
		if (!e) SYSLOG("sbxmap", "%s list replaced: %zu entries", arg2 == 0 ? "file" : "process", arg2 == 0 ? gNumFiles : gNumProcs);
	}
	IOLockUnlock(gLock);
	return e;
}

static int statusSysctl SYSCTL_HANDLER_ARGS {
	char s[PathLen + ProcLen + 256];
	IOLockLock(gLock);
	snprintf(s, sizeof(s), "enable=%d routed=%d route_error=\"%s\" files=%zu procs=%zu allowed=%d stale=%d noblob=%d unlisted=%d last=\"%s\"",
	         gEnable, gRouted, gRouteError, gNumFiles, gNumProcs, gAllowed, gStale, gNoBlob, gUnlisted, gLast);
	IOLockUnlock(gLock);
	return SYSCTL_OUT(req, s, strlen(s) + 1);
}

static int enableSysctl SYSCTL_HANDLER_ARGS {
	int v = gEnable;
	int e = sysctl_handle_int(oidp, &v, 0, req);
	if (e || !req->newptr) return e;
	gEnable = v ? 1 : 0;
	SYSLOG("sbxmap", "enable=%d", gEnable);
	return 0;
}

// Writes need root: none of these oids has CTLFLAG_ANYBODY.
SYSCTL_NODE(_debug, OID_AUTO, strixsbx, CTLFLAG_RW | CTLFLAG_LOCKED, 0, "StrixSbxMap");
SYSCTL_PROC(_debug_strixsbx, OID_AUTO, status, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, nullptr, 0, statusSysctl, "A", "state and counters");
SYSCTL_PROC(_debug_strixsbx, OID_AUTO, enable, CTLTYPE_INT | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, 0, enableSysctl, "I", "0 = keep every Sandbox deny");
SYSCTL_PROC(_debug_strixsbx, OID_AUTO, files, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, 0, filesSysctl, "A", "cdhash:/path;...");
SYSCTL_PROC(_debug_strixsbx, OID_AUTO, procs, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, nullptr, 1, filesSysctl, "A", "process names");

// IOKit side: reads the pinned list from the personality and publishes the sysctls.
class EXPORT StrixSbxMap : public IOService {
	OSDeclareDefaultStructors(StrixSbxMap)
public:
	bool start(IOService *provider) override;
};
OSDefineMetaClassAndStructors(StrixSbxMap, IOService)

bool StrixSbxMap::start(IOService *provider) {
	if (!ADDPR(startSuccess) || !gLock || !IOService::start(provider)) return false;

	IOLockLock(gLock);
	if (auto files = OSDynamicCast(OSArray, getProperty("AllowedFiles"))) {
		size_t n = 0;
		for (unsigned i = 0; i < files->getCount() && n < MaxFiles; i++) {
			auto d = OSDynamicCast(OSDictionary, files->getObject(i));
			auto path = d ? OSDynamicCast(OSString, d->getObject("Path")) : nullptr;
			auto cd = d ? OSDynamicCast(OSString, d->getObject("CDHash")) : nullptr;
			if (!path || !cd || path->getLength() >= PathLen || path->getCStringNoCopy()[0] != '/' ||
			    !parseCdhash(cd->getCStringNoCopy(), cd->getLength(), gFiles[n].cdhash)) {
				SYSLOG("sbxmap", "AllowedFiles[%u] malformed, skipped", i);
				continue;
			}
			strlcpy(gFiles[n].path, path->getCStringNoCopy(), PathLen);
			n++;
		}
		gNumFiles = n;
	}
	if (auto procs = OSDynamicCast(OSArray, getProperty("AllowedProcesses"))) {
		size_t n = 0;
		for (unsigned i = 0; i < procs->getCount() && n < MaxProcs; i++) {
			auto s = OSDynamicCast(OSString, procs->getObject(i));
			if (s && s->getLength() > 0 && s->getLength() < ProcLen) strlcpy(gProcs[n++], s->getCStringNoCopy(), ProcLen);
		}
		gNumProcs = n;
	}
	SYSLOG("sbxmap", "config: %zu pinned files, %zu processes, routed=%d", gNumFiles, gNumProcs, gRouted);
	IOLockUnlock(gLock);

	sysctl_register_oid(&sysctl__debug_strixsbx);
	sysctl_register_oid(&sysctl__debug_strixsbx_status);
	sysctl_register_oid(&sysctl__debug_strixsbx_enable);
	sysctl_register_oid(&sysctl__debug_strixsbx_files);
	sysctl_register_oid(&sysctl__debug_strixsbx_procs);
	registerService();
	return true;
}

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal,
	bootargOff, arrsize(bootargOff),
	bootargDebug, arrsize(bootargDebug),
	bootargBeta, arrsize(bootargBeta),
	KernelVersion::Tahoe,
	KernelVersion::Tahoe,
	[]() {
		gLock = IOLockAlloc();
		if (!gLock) return;
		lilu.onPatcherLoadForce(onPatcher);
		lilu.onKextLoadForce(&kextSandbox, 1, onKext);
	}
};
