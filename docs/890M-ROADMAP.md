# 890M port - roadmap audit (2026-10-18)

Final goal (owner): a full hardware port of the Radeon 890M on macOS Tahoe, **independent of NullMoth**, with WindowServer
composited on the iGPU (this is what removes the 500-900 % WindowServer CPU: it is CoreAnimation's software rasteriser
because no Metal device exists). Route B decision (2026-10-17, Step31): build our own stack from NullMoth v2.0.4 sources, then replace
the headless accelerator, then replace the NVIDIA userland.

## State 2026-11-04 (Step101c boot) - supersedes the milestone table below

| # | Milestone | Status |
|---|---|---|
| M1 | Own kernel driver up (NMXGPU) | done |
| M2 | Graphics jobs reliable | done for WindowServer (H2 interrupt-loss root cause fixed Step100); apps not re-tested since Step70 |
| M3 | WindowServer composites on the 890M | **done**: amdgpu DC drives the OLED, zero-copy page flips, 116 fps, WS ~2.35 ms CPU per frame (27 % at 116 fps, was 500-900 %) |
| M3b | Apps get a Metal device | **half**: non-sandboxed apps work (2026-11-04: Terminal with `NVMTL_ENABLE=1` UP on RADV STRIX1, fish output loop, desc-cache hit 1684/miss 143, no ring timeout; tools: 10 compute + 10 render + 200-frame loop + 15 parallel clean). Sandboxed apps (TextEdit etc.) get no device: the sandbox denies `file-read-data /dev/dri`, RADV enumerates 0 GPUs, the plugin refuses and the app draws on the CPU (looks fine, but no GPU). Allow list still `!WindowServer` only |
| M4 | Own userland (NVMTLDriver from the fork source, RADV) | partly: the NVMTL plugin is now built from fork source (desc-cache branch); RADV/libdrm still NullMoth binaries |
| M5 | No NullMoth kexts | not started (NVRM/NVAccel/NVRMFB/NVRMAGDC/NMXAccel loaded) |

Daily-use gate (OLED + apps on the 890M), in order:
1. App Metal: bounded app jobs are clean again after H2 (done 2026-11-04). Left: (a) sandboxed apps, see below;
   (b) reopen the allow list by rungs: done 2026-11-04 (Step103 rung 1, Step104 rung 2 + `*`; Chrome/Edge WebGL
   on the 890M). Open: Safari's WebKit GPU process may not map executables from /Library/GPUBundles (its sandbox
   maps only sealed /System paths and read-only cryptex grafts). Step105 (staged, reboot pending): StrixSbxMap,
   a kernel-side Sandbox mmap exception for the pinned plugin files; the three plugin-side fixes are live
   (Step105b, plugin fb86bf5, simulation PASS); see "Safari WebGL: Sandbox mmap exception" below. Also open: WindowServer CPU with many animated clients.
2. Sleep/wake and lid with NMXGPU: never tested (caffeinate always on).
3. Stability run: several clean boots and a full workday without a panic (last panic 2026-11-04 11:50, Step100c, fixed).
4. Video decode (VCN) for browsers/players: not started; without it video decodes on the CPU.
5. HiDPI extra scaled modes (Retina 1440x900 @ 120 Hz already works; only the other sizes are missing).

Hybrid with the RTX 5060 (NVRM 2.7.1 installed 2026-11-04 for the next boot; on 2.5.2 GSP-RM was up, `RmInitAdapter succeeded`): the kernel side boots today. Missing for
apps: a Metal device for the RTX (NullMoth NVIDIA path, same allow-list gate) and a device choice per app (low power =
890M, high power = RTX); HDMI on the RTX was the old hybrid desktop (NVRMFB/AGDC) and needs a re-test with the AMD OLED.

## Layers, who owns them today

| Layer | Component | State | NullMoth dependency |
|---|---|---|---|
| Boot display | StrixGOP, StrixAccel (0.1.21) | ours, works | none |
| Kernel GPU driver | NMXGPU (Linux amdgpu 6.14 on xkpi) | **ours** (built from NullMoth 2.0.4 sources, fork `ga403wm-nmx`), compute works, gfx flaky | source origin only (PolyForm, kept in the fork) |
| Kernel accelerator | NMXAccel (headless) | NullMoth 2.3.1 binary | **yes** |
| Kernel support | NVRM, NVAccel, NVRMFB, NVRMAGDC, NVRMEdpBL | NullMoth binaries, loaded | **yes** |
| Userland Metal driver | NVMTLDriver + NVIDIAShared (Metal on Vulkan) | NullMoth binary, allow-list gated | **yes** |
| Userland Vulkan | RADV, libdrm, libdrm_amdgpu (`/Library/GPUBundles/nvmtl`) | NullMoth binary + our 2 binary patches | **yes** |

So only the kernel driver is ours. Everything between the driver and WindowServer is still NullMoth.

## Milestones

| # | Milestone | Status |
|---|---|---|
| M1 | Own kernel driver brings up the 890M, DRM nodes, IB execution, compute | done (Step31-36) |
| M2 | **Graphics jobs reliable** (gfx ring, VM, fences) | in progress; strict pass/fail alternation, CP stalls fetching a new process's IB (Step38-41). Needed by ANY route: it is a bug in our kernel port, not in NullMoth code |
| M3 | A non-headless accelerator so WindowServer can obtain a Metal device and present | audited (Step42): NMX_ACCEL branch is hard-headless and no AMD IOFramebuffer/display pipe exists, needs (a) NMX scan-out framebuffer (b) arm like NVIDIA path (c) WindowServer allow; today blocked: WindowServer must stay off the allow list until M2 is solid, a hung job there means no display |
| M4 | Own userland: libdrm/RADV from source (route B step 4), then replace NVMTLDriver | not started; NVMTLDriver (Metal on Vulkan) is the largest piece and has no source here |
| M5 | Remove NVRM/NVAccel/NMXAccel (NullMoth binaries) | after M3/M4 |

## Honest assessment

* The direction is consistent with the route B decision, but only M1 is complete. M2 is not a side trace: nothing in M3-M5 can
  work while a graphics job hangs every second process. It is the right thing to be on, and it must be time-boxed.
* We have been inside M2 for many hours with a test -> read log -> reboot loop. The owner's "build full from the data we have,
  trace on Linux" is the correct correction: compare the identical Vulkan triangle on Linux (same 890M, same RADV) instead of
  guessing at the macOS port. Linux is the reference for the VM/MES/gfx-ring setup.
* "Drop NullMoth" is not near: five NullMoth kexts and the whole Metal userland are still in use. The only item with an actual
  path to independence is M4, and it is a project of its own (a Metal driver for macOS). It needs an explicit decision (below).

## Decisions needed

1. Interim policy: keep NVMTLDriver/RADV/NVRM as a **declared temporary dependency** until M3 works, then replace piece by piece
   (recommended). The alternative, writing the Metal driver first, delays any WindowServer relief by a very long time.
2. Time-box M2: if build 12's VM/page-directory data plus a Linux comparison do not explain the stall, stop adding diagnostics and
   instead mirror Linux's exact VMID/page-table/TLB flush sequence in the port.

## Backlog (2026-11-04, after Step100)

Done since this audit: DC display on the 890M (NMXGPU), page flips and zero copy (Step98-99), H2 interrupt-loss root
cause (Step100 irqfix), stale xkpi records (Step100 mmfix2), brightness slider via amdgpu DC (NMXBacklight, owner
verified), cave registry check (`scripts/nmx-caves/check.py`).

Open, in order:
1. **WindowServer CPU, NVMTL per-draw cost** (measured 2026-11-04 boot 2: desc-cache `long 0`, hit 92 %; WS 59..68 %
   at 111 fps, user 43 % / system 18 %, NVMTL ~30 % of the user samples). Next: recycle per-frame texture memory,
   memo the sampler-variant key per encoder, cheap trace flag. Details: `docs/890M-TRACE.md`, "Step100 boot 2".
   Step101 (plugin 3d0dc6a) implements all three; Step101 boot showed the per-frame churn is sampler states ->
   Step101b (f973e95) sampler-state cache: measured ~3.4 ms CPU per frame (from ~5.5-6.2). Step101c (fbb6ca4)
   identity views share the image view (view destroys ~200/s were the last epoch churn), installed, measure next boot.
2. **HiDPI scaled modes** (owner: "not now, keep it on the roadmap"). System Settings shows one resolution tile and no
   refresh menu because NMXGPUFB reports a single mode. Root cause and plan: `docs/890M-TRACE.md`, section
   "HiDPI scaled modes: root cause and plan". Pieces: more backing sizes reported from NMXBacklight's vtable copy,
   a per-mode VRAM buffer plus plane src rect = fb size in the flip cave (DC plane scaler), NMXAccel copy fallback
   for a surface size different from the home buffer. One reboot batch; fallback boot-arg `-nmxbloff`.
3. xkpi mm lifetime as a source build: fork branch `mm-lifetime` 163d117 (the binary steps would have to move into
   source first; until then Step97b's mm_dtor `ret` leak and the mmfix2 cave stay).
4. Remaining prints on the IRQ path (`___drm_err`, VM-fault messages) can block like H2 did during a console stall;
   consider dropping `-v` from boot-args.

## Sandboxed apps: /dev/dri is blocked (found 2026-11-04; fix Step102 installed, reboot pending)

`Sandbox: TextEdit(17713) deny(1) file-read-data /dev/dri`. Every App Store / sandboxed app (and browser GPU
processes) hits this, so opening the DRM render node can never be the app path. NullMoth's NVIDIA userland already
solves the same problem (nvk-macos.patch ~11720): it opens an IOKit user client on the accelerator (sandboxed apps
may open IOAccelerator user clients), opens `/dev/null` read-only as a handle fd (allowed in every sandbox), binds the
fd to the connection (`SEL_BINDFD`) and sends every ioctl through `IOConnectCallMethod(SEL_ESC)`.
Plan for the 890M, same shape:
1. NMXGPU/NMXAccel: a user client whose escape selector runs the amdgpu DRM ioctls (GEM create/mmap/VA, CS submit,
   syncobj, query info) for the bound file context, so the per-process DRM file stays in the kernel.
2. libdrm (RADV): when `open("/dev/dri/renderD128")` fails with EPERM, fall back to the IOKit path; `drmIoctl` on that
   fd goes through `IOConnectCallMethod`. mmap of BOs: map through the user client (`IOConnectMapMemory64`).
3. Test: TextEdit / Preview / Safari GPU process get "vk: UP" with no sandbox violation; then the allow list rungs.
Built and installed as Step102 (docs/890M-TRACE.md): the user client lives in NMXAccel (no NMXGPU change, no new
cave) and the userland side is in the NVMTL plugin (libc import rebinding in RADV/libdrm, sandboxed processes only),
so libdrm/RADV binaries stay as they are.

## Safari WebGL: Sandbox mmap exception (Step105, 2026-11-04; kext staged, reboot pending)

Problem: `Sandbox: com.apple.WebKit.GPU deny(1) file-map-executable /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver`,
then `CFBundle: Error loading … NVMTLDriver`: Metal gets no 890M device in the WebKit GPU process, WebGL context is
lost at once (WKWebView harness: renderer null). Both GPU process profiles (system WebKit
`/System/Library/Frameworks/WebKit.framework/…/com.apple.WebKit.GPUProcess.sb` used by WKWebView apps, and Safari's
cryptex `StagedFrameworks/Safari/…`) are `(deny default)` and allow file-map-executable only under sealed /System
paths and cryptex grafts. Ruled out in Step104: WebGL in WebContent (same deny), binaries in the cryptex dirs (EROFS).
MACF policies are AND-ed, so no second policy can allow it: the change has to be inside Sandbox's own check.

### Kernel side: StrixSbxMap (kexts/StrixSbxMap, BSD, this repo)

Sandbox 300.0 (macOS 26.7.1 25G241) keeps its symbols in the boot KC. The hook is small:

    hook_file_check_mmap(cred, fileglob *fg, label *, int prot, int flags, uint64_t pos, int *maxprot)
        if (!(prot & PROT_EXEC)) return 0          ; test cl,4
        vp = fg_get_vnode(fg); if (!vp || vnode_isdyldsharedcache(vp)) return 0
        return cred_sb_evaluate(cred, 0x13 /* file-map-executable */, &ctx{vp})

StrixSbxMap is a Lilu plugin (injected by OpenCore, like StrixHeadroom) that routes `_hook_file_check_mmap` with
`routeMultiple` (Lilu processes Sandbox even though it loads before Lilu). The wrapper always calls the original;
only a non-zero (deny) answer for a PROT_EXEC map is looked at, and it becomes 0 only when all of these hold:

| Check | How |
|---|---|
| exception enabled | boot-arg `-strixsbxoff` (Lilu) / `sysctl debug.strixsbx.enable=0` turn it off |
| process | `proc_selfname` on the list, default `com.apple.WebKit.GPU` only (WebContent and everything else unchanged) |
| file | `fg_get_vnode` -> regular file, `vn_getpath` (Data-volume prefix folded) equal to a pinned path |
| identity | `ubc_cs_blob_get(vp, -1, -1, pos)`: the code signature blob dyld registered (F_ADDFILESIGS) that covers the mapped offset; `csblob_get_cdhash` must equal the cdhash pinned for that path |

Identity is the cdhash, not the vnode pointer: a vnode pointer is reused after the file is replaced, the cdhash is the
content. The path check keeps a byte-identical copy elsewhere from passing. Everything else, including a missing
blob or a stale cdhash after a plugin rebuild, keeps Sandbox's deny (fail closed) and is counted/logged
(`sbxmap: … cdhash … is not the pinned one (run the installer with --refresh)`).
Before routing, the hook prologue is checked (`test cl,4` and a `call` to `fg_get_vnode` within 0x40 bytes); any
other Sandbox build leaves the plugin inactive (`route_error` in the status sysctl). Kernel symbols used:
`_fg_get_vnode`, `_ubc_cs_blob_get` (checked: cputype -1 -> offset match), `_csblob_get_cdhash` (blob+0x58).
Cost: one extra call per exec mmap; the path/cdhash work only runs after a deny.

Pinned files (8): NVMTLDriver, libnvmtl_translate.dylib, air-runtime/libLLVM.dylib, air-runtime/libzstd.1.dylib
(loaded by libLLVM when a shader is translated, found by the simulator below), nvmtl/libvulkan.1.4.362.dylib,
libvulkan_radeon.dylib, libdrm.2.dylib, libdrm_amdgpu.1.dylib. All are ad-hoc signed (CDHash present).
The list lives in the kext personality (`AllowedFiles`, written by the installer from `codesign -dvvv`) and can be
replaced by root at runtime (`sysctl debug.strixsbx.files="cdhash:/path;…"`), so a plugin rebuild needs
`--refresh`, not a reboot. sysctls: `debug.strixsbx.{status,enable,files,procs}`, writes need root.

What it allows: the WebKit GPU process may map exactly the code that is already loaded in every other Metal app.
It cannot map anything else, and nothing changes for other processes or other operations.

Install / undo (scripts/macos-install-strixsbxmap.sh, user shell, ESP mounted user-owned; admin prompt only for the
live sysctl writes):

    scripts/macos-install-strixsbxmap.sh            # preflight on the KC, build, pin, ESP kext + Kernel/Add (25.x)
    scripts/macos-install-strixsbxmap.sh --refresh  # after a plugin/RADV rebuild: new pins on the ESP + live
    scripts/macos-install-strixsbxmap.sh --status
    scripts/macos-install-strixsbxmap.sh --undo     # live enable=0 now, Kernel/Add entry + ESP kext removed

Recovery if a boot goes wrong: boot-arg `-strixsbxoff`, or from Linux remove the `StrixSbxMap.kext` Kernel/Add entry
(config backup `config.plist.strixsbxmap-20261104-151851` on the ESP).

### Plugin side: three more sandbox walls (fixed live in Step105b, plugin fb86bf5)

The mmap exception alone is not enough. `tools/890m/sbx-sim.m` applies the WebKit GPU profile in-process (like the
GPU process does, after dyld and libdispatch are up) plus exactly the 8 pinned file-map-executable rules, then
creates the Metal device and runs one bounded render job (MSL source -> Apple compiler -> in-process AIR->SPIR-V ->
RADV). Result 2026-11-04: with only the pins, the plugin loads but the device does not come up; adding three
rules gives `vk: UP` and a correct pixel (PASS). Each of the three was removed again on its own: each alone brings
`device: none` back.

| Wall (deny in the GPU profile) | Effect | Fix in the plugin (fork desc-cache fb86bf5, installed live) |
|---|---|---|
| `sysctl-read hw.pagesize_compat` (not on the profile's sysctl list) | `getpagesize()` fails: drm-xnu rebinding finds "0 imports in the driver and 0 libdrm images", `_sysconf not rebound`, RADV enumerates 0 GPUs | take the page size from `vm_page_size` (mach global, no syscall) in the rebinder; answer `getpagesize`/`sysconf(_SC_PAGESIZE)` for RADV/libdrm the same way |
| `file-read-data /dev/null` | the NMDR handle fd cannot be opened: `amdgpu_query_info(ACCEL_WORKING) failed (-9)` | fall back to a node the profile can read (`/dev/random` is allowed read-only), or a handle that needs no path |
| `system-fcntl F_DUPFD_CLOEXEC` (list: F_ADDFILESIGS_RETURN F_CHECK_LV F_GETFL F_GETPATH F_GETPROTECTIONCLASS F_GETSIGSINFO F_NOCACHE F_SETFD F_SETFL F_SETLKW F_SETNOSIGPIPE) | RADV's `os_dupfd_cloexec` on the render fd fails | handle F_DUPFD_CLOEXEC on drm-xnu fds in the shim (new handle bound to the same NMDR connection, or dup + F_SETFD) |

Safari's cryptex profile has the same three restrictions (checked). Not needed: `air-opt` (shader translation ran
in-process; the profile denies process-exec/fork, so a metallib path that spawns air-opt would fail; watch for
`air-opt spawn failed` in the GPU process). Non-fatal leftovers: spvcache stores fail (read-only cache dir), a few
syscall-unix denies from the cache trimmer, `sysctl-read debug.nmxaccel_headless`.
Alternative kept in reserve: route `hook_file_check_fcntl` and the sysctl/open checks the same way in StrixSbxMap.
Rejected for now: it widens the kernel exception beyond files, needs a reboot per try, and the plugin can avoid all
three calls.

### Test plan

Before the reboot (now, and after every plugin fix):

    scripts/macos-webgl-safari-test.sh sim            # system WebKit profile + the pins staged on the ESP
    scripts/macos-webgl-safari-test.sh sim --safari   # Safari's cryptex profile

Before the plugin fix: `SIM FAIL` with the three walls above. With plugin fb86bf5 (installed live, pins refreshed
with `scripts/macos-install-strixsbxmap.sh --refresh`): `SIM PASS` for both profiles, 2026-11-04 15:34. The simulator turns the
IOKit message filter off (it needs WebKit's entitlement); the NMDR selectors 0/1/2 are on its allowed list.

After the batched reboot:
1. `scripts/macos-install-strixsbxmap.sh --status`: `routed=1 route_error="none" files=8 procs=1`, live pins match.
   Kernel log `sbxmap: routed Sandbox hook_file_check_mmap`, `config: 8 pinned files`.
2. `scripts/macos-webgl-safari-test.sh live --ab`: build/webgl-probe (WKWebView, `UseGPUProcessForWebGLEnabled` on,
   `MaskWebGLStringsEnabled` off, one clear + one triangle + readPixels, 25 s cap) prints `unmasked_renderer`
   with `AMD Radeon 890M … (RADV STRIX1)`, pixel 0,255,0 -> `LIVE PASS`; `allowed` counter rises; no
   file-map-executable deny for com.apple.WebKit.GPU. A/B: enable=0 -> the deny and the lost context come back;
   enable=1 -> PASS again (same boot).
3. Safari itself: new window, a WebGL page; `sysctl debug.strixsbx.status` `last="com.apple.WebKit.GPU /Library/GPUBundles/…"`,
   GPU process log has no `Error loading …NVMTLDriver`. (Safari masks the renderer string, the counters are the proof.)
4. Regression: Chrome/Edge WebGL still on the 890M, TextEdit/Notes `vk: UP`, WindowServer unaffected (not on the
   process list), no stale/noblob counts, no panic. Undo path tried once: `--undo` -> enable=0 live.

## Hybrid and automatic GPU choice (owner requirement, 2026-11-04)

Goal: the machine picks the GPU by itself, like a real MacBook Pro with two GPUs, and switching just works:
- The 890M always owns the OLED, the display path, brightness and WindowServer (never moves to the RTX).
- Low-power / default apps get the 890M. Apps that ask for high power (Metal `MTLCreateSystemDefaultDevice` on a
  high-performance request, `NSSupportsAutomaticGraphicsSwitching` = false, games, Blender, LLM runtimes) get the
  RTX 5060 through the NullMoth NVIDIA Metal device; its frames are copied to the 890M for display.
- Both devices show in `MTLCopyAllDevices` (890M `lowPower`=YES, RTX `lowPower`=NO, `removable`=NO), so apps that
  choose for themselves (Blender, Final Cut style) can do it.
- An override per app (allow-list style file or a small menu-bar setting): force 890M / force RTX / auto.
- The RTX powers down when no app uses it (runtime D3, NVRM already parks it) and wakes on the first high-power app.
- HDMI (wired to the RTX) works as a second display while the OLED stays on the 890M.
Order: after M3b (apps on the 890M, sandbox fix) - the RTX Metal device needs the same sandbox-safe path and the
plugin has to run both devices in one process.

