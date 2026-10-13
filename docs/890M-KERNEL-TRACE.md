# StrixProbe: SDK, XNU and PCI call-chain review

2026-10-13, macOS15.8.1/24H32, x86_64. This review precedes the next runtime
trial; it does not turn a source inspection or successful link into a hardware pass.

## Identities and evidence

- Loaded kernel: `xnu-11417.140.69.712.69~1/RELEASE_X86_64`.
- MacKernelSDK: `3f750085caa17ec3a7880f11c11bf4f48cd6a164`.
- [XNU11417.140.69](https://github.com/apple-oss-distributions/xnu/tree/43a90889846e00bfb5cf1d255cdc0a701a1e05a4):
  commit `43a90889846e00bfb5cf1d255cdc0a701a1e05a4`. This public base is **not**
  the exact loaded kernel's additional712.69 revision.
- [IOPCIFamily](https://github.com/apple-oss-distributions/IOPCIFamily/tree/4822b27a36e2de70e231ecf2bf3021384fab6ec2):
  commit `4822b27a36e2de70e231ecf2bf3021384fab6ec2`; reference implementation,
  not asserted byte-identical to the loaded family.
- Runtime0.1.1: `out/890m-trace/step02-20261013T083948.414944Z/`.
- Later same-session census: `out/890m-trace/step02-20261013T085000.546036Z/`.
- Final0.1.2 build: `out/890m-trace/step02-build-20261013T085331.994874Z/`.
  Compiler dependency manifest hashes263 source/header files. Compilation
  traverses these dependencies; this is not a claim of manually reading every
  file in the entire SDK. The review follows all probe operations below.

## Why the first two PCI snapshots failed

1. Probe starts as an IOResources diagnostic, independent of the GPU driver.
2. SDK `IOService::getMatchingServices()` documentation says published objects;
   XNU implementation actually requests `kIOServiceMatchedState` from
   `copyExistingServices()`.
3. `doInstallNotification()` distinguishes FirstPublish and FirstMatch states.
4. `doServiceMatch()` invokes FirstPublish notifications before probing client
   drivers; Matched and FirstMatch notifications occur afterwards.
5.0.1.1 callback proves physical configRead32(0)==0x150e1002, then calls a
   Matched-state census while the callback's own device is still in publication.
   Result: zero targets, despite a valid callback device.
6. Actual installed `/System/Library/Kernels/kernel` disassembly confirms
   `getMatchingServices()` passes0x4 to its internal helper. Saved at the final
   build trace's sibling earlier084959 trace, `kernel-getMatchingServices-disassembly.txt`.
7. `strix-probe-ctl --inspect` later finds one matched target from registry PCI
   properties. This uses IOServiceGetMatchingServices; XNU's user-space RPC also
   dispatches to the kernel getMatchingServices method. It is not physical config
   readback, but independently confirms that the device becomes enumerable later.

Fix: capture the callback's borrowed IOPCIDevice directly, merge with the existing
Matched census and skip the duplicate pointer. Also collect at FirstMatch so
resource publication can be assessed at both stages. No device retain persists
past a callback. Capture ServiceState, Acquisition and Generation for diagnosis.

## Lifetime, concurrency and refresh

- addMatchingNotification retains its matching dictionary; caller releases its
  original reference. It can invoke existing-device callbacks synchronously
  before returning. The lock and fields are initialized before registration.
- invokeNotifier drops the global notification lock before entering the handler.
  The probe serializes snapshots with its own IOLock; no waitQuiet or indefinite
  service wait occurs inside the notification callback.
- stop marks snapshots stopped, then removes each notifier outside the snapshot
  lock. XNU remove waits for in-flight handlers and releases the notifier.
  Holding the snapshot lock while removing would risk deadlock; we avoid that.
- free releases the snapshot lock after stop. No user client or target GPU open
  is created. Snapshot generation and in-progress markers expose publication state.
- The new setProperties endpoint accepts exactly `{Refresh: true}` and checks
  IOUserClient::clientHasPrivilege(current_task(), "root"). It refreshes only the
  census/console/VFCT. Unknown inputs and non-admin calls are rejected.
- XNU's IORegistryEntrySetCFProperties RPC deserializes input then dispatches to
  entry->setProperties; security checks remain active. Refresh during stopping
  returns NotReady. The userspace helper checks capability before sending anything.
- On loaded0.1.1 helper inspect works; refresh correctly refuses because there is
  no endpoint. No request sent. New endpoint authorization/refresh is **not runtime
  validated** until0.1.2 loads. Do not hot-unload or republish GPU devices to retry.

## PCI/BAR access audit

- SDK configRead32(offset) forwards to extendedConfigRead32, not an assumed
  UInt8 virtual overload. PCI source gates config access then delegates to the
  bridge; failure returns0xffffffff. No configWrite, BAR sizing, provider open,
  setPowerState, bus mastering or GPU initialization is requested.
- getDeviceMemoryWithRegister and getDeviceMemoryWithIndex contain a conditional
  setTunnelL1Enable call in the reference source. They cannot be described as
  unconditionally free of link-policy effects.0.1.2 avoids these getters.
-0.1.2 reads existing IODeviceMemory OSArray entries and descriptor tags, then
  requests a physical segment with kIOMemoryMapperNone. This avoids requesting a
  mapper translation. Record segment length alongside descriptor length; no map,
  prepare, DMA allocation or aperture read/write is performed.
- All six BAR config dwords are raw values. High halves of64-bit BARs are not
  separate apertures. OS descriptor tags identify actual resources.
- Previous GPU/VFCT fields are cleared before replacement so refresh cannot
  leave old data looking like a new successful acquisition.

## Console interpretation and current GOP evidence

IOPlatformExpert::getConsoleInfo calls PE_current_console, which copies
PE_state.video. pe_init copies boot video metadata and sets pixel format to
`PPPPPPPP`; this placeholder does **not** prove BGRA/RGBA channel order.
video_console.c documents bit0 as physical-address indication and clears the
two low bits with `& ~3UL`. A page-aligned guess was not the complete contract.
SDK PE_Video defines v_length0 as rowBytes*height. Offset, rotation, scale and
display type also matter;0.1.2 captures them and the explicit physical flag/base.

Observed: raw0x880000001 -> physical0x880000000, width2880, height1800,
stride11520, depth32, offset0, length0 -> raster20736000 bytes. Live registry
assigned-addresses places890M BAR0 at0x880000000, size0x10000000. The raster fits
inside BAR0. This establishes a consistent GOP/BAR candidate, **not** current
scanout ownership or permission to overwrite it. The current IOFramebuffer census
contains NVRMFramebuffer; there is no native890M framebuffer implementation yet.

## Verification and the next runtime gate

0.1.2 compiles with Wall/Wextra/Werror, links x86_64 KEXTBUNDLE, has _kmod_info,
and316 imports all occur among Boot KC defined external symbols. No forbidden
C++ destructor/exception imports. Symbol occurrence is not a runtime KPI/export
or vtable compatibility guarantee. Helper builds with warnings treated as errors.
Parser12 PASS/2 local fixture checks skipped; shell syntax and git diff checks pass.
VFCT21636 bytes and selected AtomBIOS21504 bytes still match Linux hashes.

Next load should gather FirstPublish and FirstMatch and support later refresh in
the same session. Require one physical target, correct config/BAR descriptors,
finite complete generation and valid VFCT. Test admin refresh and non-admin denial;
preserve each attempt. Framebuffer adoption, MMIO, indirect access and hardware
engine initialization remain gated on that evidence. Do not ask for repeated
reboots to compensate for a missing observation mechanism.

## Runtime follow-up:0.1.2 passed the census gate

FirstMatch capture has one physical target and matching BAR config/descriptors.
Non-admin refresh denied, three admin refreshes succeed; generations3/4/5/6
have identical PCI/VFCT hashes. Boot GOP is physical2880x1800 within BAR0;
current console later becomes virtual1920x1080. Owner confirms HDMI desktop and
OLED frozen on boot logo in Hybrid. This distinction prevents comparing a live
virtual console pointer to physical BARs or claiming native OLED display support.
Evidence and remaining framebuffer gate are recorded in the latest890M trace.
