# Frame path: Linux reference flow vs this port (2026-11-18)

Goal: find why the machine is not smooth under multitasking (video + work + Docker) by following one frame through
the Linux flow of the code we build (amdgpu + amdgpu_dm from `gpu/drm-kmod`, FreeBSD "Reduce diff with Linux 6.14",
c16de0f9fa) and through our port, stage by stage. Dropped-frame counts are not used to rank anything here.

Sources read (all ours unless noted):
- NMXGPU: `nmx-build-xkpi/src/gpu-port/xkpi` @ 4f6825b (live out-29): `xnu/nmx_fb.cpp` (IOFramebuffer),
  `override/src/nmx_fb_bridge.c` (DRM client + flip API), `xnu/nmx_pci.cpp` (interrupts), `bsdcompat/src/nmx_task.c`
  (callouts, taskqueues), `xnu/nmx_mm.cpp`, `patches/*`.
- **NMXAccel is not closed**: its source is `kexts/NVRM/accel/nvrm-accel.cpp` built with `NMX_ACCEL`, same repo
  (`nvidia-macos-driver-ws`), live build = branch `nmxaccel-family-gate` c1db436, which is an ancestor of
  `nmx-source-port` 4f6825b. NMXAGDC is `kexts/NMXAGDC/nmx-agdc.cpp`. Reverse engineering is only needed for Apple's
  side (section 5).
- Metal plugin: `plugin/NVMTLEventSync.m`, `plugin/NVMTLObjects.m` @ 899c64f (`ci/amd-plugin-890m`).
- Linux reference: `gpu/drm-kmod/drivers/gpu/drm/amd/display/amdgpu_dm/{amdgpu_dm.c,amdgpu_dm_crtc.c,amdgpu_dm_plane.c}`,
  `drm_atomic_helper.c`, `amd/amdgpu/{amdgpu_fence.c,amdgpu_vcn.h}`; LinuxKPI `freebsd-src/sys/compat/linuxkpi`.
- Live read-only counters, boot of 2026-11-18 ~08:54 (23 min uptime, owner working):

  | counter | value | meaning |
  |---|---|---|
  | `debug.nmxaccel_flip` | 1 | zero-copy flips of WindowServer's IOSurface (mode 1) |
  | `nmxaccel_flip_submitted` = `_latched` | 36802 | ~27 presents/s average (content driven) |
  | `nmxaccel_flip_wait_us` / submitted | **5.85 ms** | submit -> NMXAccel sees the latch (async) |
  | `nmxaccel_fence_waited` / `_frames` | **32491 / 36802 (88 %)** | frames whose GPU work was not done when the pipe got them |
  | `nmxaccel_fence_wait_us` / waited | **1.47 ms** | serial wait on the display-pipe thread |
  | `nmxaccel_flip_imports`, `_import_fail`, `_drop`, `_fallback`, `_timeouts` | 11, 0, 0, 0, 0 | no import churn, no CPU copy, no drop in the pipe |
  | `nmx_userrec_made` | 2.61 M (~1 900 pages/s) | userptr page records made and freed |
  | `nmx_userwire_parks` / `_unparks` | 1828 / 644 | Step142 park churn |

## 1. Linux reference flow

### 1.1 A composited frame (compositor renders, then flips)

| # | stage | Linux functions |
|---|---|---|
| L1 | client renders into a shared buffer | Mesa RADV `vkQueueSubmit` -> `DRM_IOCTL_AMDGPU_CS` -> `amdgpu_cs_ioctl` -> `amdgpu_cs_parser_bos` (BO list, userptr re-validated through `amdgpu_ttm_tt_get_user_pages` + `mmu_interval_read_retry`) -> `amdgpu_cs_sync_rings` (`amdgpu_sync_resv`: waits in the **scheduler** for fences already on every BO's `dma_resv`) -> `drm_sched_job_arm`/`push` -> `amdgpu_cs_post_dependencies` (out syncobj) -> **job fence added to each written BO's `dma_resv`** (`amdgpu_bo_fence`/`dma_resv_add_fence`, usage WRITE) |
| L2 | buffer shared with the compositor | dma-buf: `drm_gem_prime_handle_to_fd` / `amdgpu_gem_prime_import`. One BO, one `dma_resv`, in every process. Implicit sync across processes = that resv. No pinning; TTM may evict (`ttm_bo_evict`, `amdgpu_bo_move`) and the shrinker (`ttm_pool_shrinker_scan`) frees pool pages under pressure; userptr pages are kept valid by `mmu_interval_notifier` (`amdgpu_hmm_invalidate_gfx`) |
| L3 | compositor composites | its own CS (L1) reading the client BOs: the scheduler waits for the clients' write fences (`drm_sched` dependency), **no CPU wait anywhere** |
| L4 | compositor presents | `DRM_IOCTL_MODE_ATOMIC` with `DRM_MODE_PAGE_FLIP_EVENT` + `NONBLOCK` (or legacy `page_flip`) -> `drm_atomic_helper_commit` -> `amdgpu_dm_plane_helper_prepare_fb` (pin, GART, **`drm_gem_plane_helper_prepare_fb` copies the BO's WRITE fence into `plane_state->fence`**) -> `drm_atomic_helper_setup_commit` (flip_done completion) -> returns; `-EBUSY` if a flip is still pending |
| L5 | commit worker | `commit_work` on `system_unbound_wq` -> `commit_tail` -> **`drm_atomic_helper_wait_for_fences`** (the render fence, in the kernel) -> `amdgpu_dm_atomic_commit_tail` -> `amdgpu_dm_commit_planes`: `dma_resv_wait_timeout(WRITE)` again, waits until out of the vblank before the target (`target_vblank = last_flip_vblank + 1`, `usleep_range(1000,1100)` loop), `drm_crtc_vblank_get` + `prepare_flip_isr` (event armed), `flush_workqueue(vblank_control_workqueue)` when PSR/idle opts are on, `dc_update_planes_and_stream` (fast update: surface address only) -> `drm_atomic_helper_commit_hw_done` |
| L6 | flip latched | DCN latches HUBP address at vblank start -> **pageflip IRQ** -> `amdgpu_irq_handler` (hard IRQ) -> `amdgpu_ih_process` -> `dm_pflip_high_irq`: timestamp from the vblank counter, `drm_crtc_send_vblank_event` (completes `commit->flip_done`, sends the event with the flip's vblank sequence and timestamp to the compositor's fd), `drm_crtc_vblank_put` |
| L7 | vblank | `dm_crtc_high_irq` (hard IRQ) -> `amdgpu_dm_crtc_handle_vblank` -> `drm_crtc_handle_vblank` (count + timestamp, vblank events, `drm_vblank_put` timer). The compositor's frame clock is the **flip-done timestamp** (mutter/kwin schedule the next frame from it); vblank IRQs stay on while a client holds `drm_crtc_vblank_get` |
| L8 | vblank off + idle | last `drm_crtc_vblank_put` -> on DCN 3.5 APU without PSR: `disable_immediate` (else `offdelay` = 2 frames, `amdgpu_dm.c:8643`) -> `amdgpu_dm_crtc_set_vblank(false)` -> `vblank_control_worker`: `active_vblank_irq_count == 0` -> `amdgpu_dm_psr_enable` / Replay / **`dc_allow_idle_optimizations(true)` (IPS)**. Next vblank_get reverses it before the flip (L5 flush) |
| L9 | GPU fences | EOP interrupt -> `amdgpu_fence_process` -> `dma_fence_signal` in hard-IRQ context; the 0.5 s `fallback_timer` is only a safety net |

### 1.2 A video frame

| # | stage | Linux |
|---|---|---|
| V1 | decode | VA-API/Vulkan video -> `amdgpu_cs_ioctl` on `vcn_unified_0` -> `amdgpu_vcn_ring_begin_use` (`cancel_delayed_work_sync(idle_work)`, ungate VCN, DPM up) -> decode into an NV12 BO, fence on its resv |
| V2 | hand-off | dma-buf of the NV12 BO to the browser's GPU process / compositor; implicit sync via the resv |
| V3 | display | compositor samples NV12 (L3) or puts it on an overlay plane (DCN supports NV12 overlays; mutter direct-scanout only fullscreen); then L4-L7 |
| V4 | VCN idle | `amdgpu_vcn_ring_end_use` -> `schedule_delayed_work(idle_work, VCN_IDLE_TIMEOUT = 1 s)` -> `amdgpu_vcn_idle_work_handler` gates VCN when no fences are pending |

## 2. This port's flow (same two frames)

### 2.1 Composited frame (WindowServer, flip mode 1)

| # | what happens here | where |
|---|---|---|
| P1 | client (Chrome/Electron/app) renders with the plugin (Metal on RADV). Its IOSurface is imported as a **userptr BO private to that process** (pages wired by `IOMemoryDescriptor::prepare`, no MMU notifier: pinned at BO creation, Step92; parked after 60 s idle, Step142) | plugin `NVMTLObjects.m`, `patches/amdgpu-userptr-*.patch`, `xnu/nmx_mm.cpp:nmx_xnu_user_wire` |
| P2 | hand-off to WindowServer: CoreAnimation passes the IOSurface ID. WindowServer imports **another userptr BO of the same pages, with its own `dma_resv`**. Ordering between the client's GPU write and WindowServer's read is user space: the client's completion pump, IOSurface seeds, `nvmtl_surface_pending_write`; surfaces that are not host-backed take CPU copies (`nvmtlSurfaceIn` / `nvmtlSurfaceOut`) | `NVMTLEventSync.m:45-87`, `NVMTLObjects.m:1213-1265` |
| P3 | WindowServer composites (CoreDisplay -> Metal -> plugin). At commit `nvmtl_nmx_fence_mark` does `IOSurfaceSetValue("NMXFencePending", n)` for every surface written; `commitAndWaitUntilSubmitted` returns once submitted (Step95) | `NVMTLEventSync.m:115-128, 571-583` |
| P4 | completion: a **serial dispatch queue `nvmtl.execution` created without a QoS attribute** waits in `drmSyncobjWait` (`nvmtl_gsub_finish`), then `nvmtlFinishExecution` -> `nvmtl_nmx_fence_done_all` -> `IOSurfaceSetValue("NMXFenceDone", n)` (a Mach IPC into IOSurface per written surface) | `NVMTLEventSync.m:288-315, 618-662` |
| P5 | WindowServer submits the display-pipe transaction; IOAcceleratorFamily2 runs `NVDisplayPipe::performTransaction` on the pipe's work-loop thread (`NMXDisplayPipe`) | `nvrm-accel.cpp:1760` |
| P6 | `nmxFenceWait`: **polls `IOSurface::copyValue("NMXFenceDone")` every 100 µs** (`IODelay(100)`) up to 100 ms, on the pipe thread; 88 % of frames wait, 1.47 ms average | `nvrm-accel.cpp:1266-1304` |
| P7 | `nmxFlipPresent`: if the previous flip is still busy, **poll every 200 µs up to 20 ms on the pipe thread**, then drop; `nmxFlipStatus` call; `nmxFlipImportSurface` (cached, 4 slots); `nmxFlipSubmit` -> `IOFramebuffer::callPlatformFunction("nmxFlipSubmit")` | `nvrm-accel.cpp:1631-1757` |
| P8 | NMXGPU `flip_submit`: `drm_atomic_state_alloc`, `drm_atomic_set_fb_for_plane`, **`drm_atomic_nonblocking_commit`** in the caller's thread. **`plane_state->fence` is NULL**: the import BO (`ttm_bo_type_sg`, made from the IOSurface pages) has an empty resv, so `wait_for_fences` waits for nothing (correct only because P6 already waited) | `nmx_fb_bridge.c:631-700, 739-890` |
| P9 | commit worker = LinuxKPI `system_unbound_wq` -> taskqueue `linuxkpi_short_wq` (kernel threads) -> same L5 code (vblank wait loop, `prepare_flip_isr`, DC fast update) | LinuxKPI `linux_work.c:731-746` |
| P10 | flip latched -> pageflip IRQ -> **`IOInterruptEventSource` -> IOWorkLoop thread** -> `amdgpu_irq_handler` -> `nmx_ih_guarded` -> `dm_pflip_high_irq` -> `drm_crtc_send_vblank_event` (no fd; completes `commit->flip_done`) | `nmx_pci.cpp:95-184`, `patches/amdgpu-irqwatch-irq.patch` |
| P11 | completion to WindowServer: a `thread_call` (`nmxFlipPoll`) **polls `nmxFlipStatus` every 200 µs** until `flip_done.done`, then `IOAccelDisplayPipe::signalTransactionInterrupt`; `isTransactionComplete` reports busy until then. Average submit -> seen 5.85 ms | `nvrm-accel.cpp:1418-1446, 1169-1180` |
| P12 | VBL for IOFramebuffer clients: **a free-running `thread_call` timer at the mode's nominal period** (`vblFire`, `fFrameNs`), never aligned to the CRTC; `setInterruptState` is a no-op; nothing calls `drm_crtc_vblank_get` for it | `nmx_fb.cpp:278-287, 366-372, 525-532` |
| P13 | vblank IRQ on/off and IPS: same L8 code, but the only vblank refs are the flips' own (`prepare_flip_isr`) | as L8 |
| P14 | GPU fences: EOP IRQ -> IOWorkLoop thread -> `amdgpu_fence_process` -> `dma_fence_signal` -> syncobj -> wakes the user-space waiter of P4 | `nmx_pci.cpp`, `amdgpu_fence.c` |
| P15 | Linux timers (fence fallback timers, `delayed_work` incl. VCN idle, vblank off delay, hrtimers, TTM/sched timeouts): **all on one `nmx softclock` kernel thread**, run one at a time; a callout with a lock takes it on that thread | `bsdcompat/src/nmx_task.c:28-133` |

### 2.2 Video frame (Chrome, VideoToolbox through our VCN decoder)

| # | here |
|---|---|
| PV1 | VideoToolbox -> plugin VT decoder -> RADV video -> `amdgpu_cs_ioctl` on VCN (same V1/V4 kernel code; idle timer on the softclock thread, P15) |
| PV2 | output: an IOSurface (system memory) imported as userptr by the decoding process; Chrome's GPU process imports it again (own userptr BO) and samples it into its CA layer surface (P1/P2 ordering in user space) |
| PV3 | WindowServer composites that layer (P3-P11). No overlay plane: only DCN's primary plane is used, so every video frame costs a full-screen composite + flip, even when the video is the only thing changing |

## 3. Divergences, ranked by expected effect on smoothness under multitasking

Effect columns: pacing (P), latency (L), memory (M), power (W).

| rank | step | Linux | here | divergence | effect | evidence / confidence | fix in our source | risk |
|---|---|---|---|---|---|---|---|---|
| **1** | GPU done -> flip allowed (L4/L5 vs P4/P6/P8) | render fence on the BO's `dma_resv` -> `plane_state->fence` -> waited by the kernel commit worker; signalled from the IRQ | GPU done is seen by a **user-space thread at default QoS** in WindowServer (`nvmtl.execution`, no QoS attribute), which then does one IOSurface IPC per surface; the pipe thread **polls that property every 100 µs** | the "frame is ready" signal crosses user space and depends on a normal-priority thread being scheduled while the owner's apps, Docker vCPU threads and Claude compete for the cores | P, L (directly added to every frame that waited: 88 % of frames); W (100 µs poll wakeups) | source (high); counters: 88 % frames wait, 1.47 ms mean (high); share of that caused by scheduling under load: **unknown -> instrumentation (4)**; `ps -M` on WindowServer: 5 threads at 79R (fixed priority), 3 at 31T (default timeshare, where a no-QoS dispatch queue runs) and 1 at 37T; which one is `nvmtl.execution` needs `spindump` (root) (medium) | NMXGPU: record the last write fence per IOSurface in the CS path (we already map surface id <-> user range: `nmx_xnu_surface_hint`, `amdgpu-nmx-surface-hint.patch`), and in `flip_submit` do `drm_atomic_set_fence_for_plane(ps, fence)` so `drm_atomic_helper_wait_for_fences` waits in the commit worker as on Linux. NMXAccel: skip `nmxFenceWait` when NMXGPU reports `NMX_FLIP_CAP_FENCE`; submit immediately. Plugin: keep the property only as a fallback. Short-term, lower-risk step: create `nvmtl.execution` with `dispatch_queue_attr_make_with_qos_class(..., QOS_CLASS_USER_INTERACTIVE, 0)` in WindowServer | medium (fence lookup by surface must match the BO actually written; wrong fence = tearing, missing fence = today's behaviour) |
| **2** | vblank delivery to Apple's side (L6/L7 vs P12) | the real CRTC vblank / flip-done IRQ drives the compositor's clock | `NMXAMDFB` keeps **one** `'vbl '` slot fed by a free-running 120 Hz `thread_call`; `setInterruptState` and `unregisterInterrupt` are no-ops. `IOFramebuffer::open` registers `handleVBL` and `IOAccelDisplayPipe::displayModeDidChange` registers `signalVBLInterrupt` in the same slot: the last one wins (this boot: two registrations, 08:54:46 and 08:55:44 when WindowServer started) | the pipe's vblank (its timestamp at pipe+0x268, its answers to user-space "notify me at the next vblank" requests, its per-vblank `isTransactionComplete` check) or IOFramebuffer's vblank shmem runs on a timer whose phase vs. the scan-out is arbitrary and drifts; the other consumer gets nothing; callbacks fire at 120 Hz even when nobody enabled them | P (frame scheduling against an imaginary vblank; can explain run-to-run spread on one build), W (120 Hz wakeups at idle) | Apple side: section 5 (high). Our side: source + this boot's log (high). Which registration won this boot: not proven (the trace line carries no callback address) | `nmx_fb.cpp`: a list of `'vbl '` registrations with per-ref enable state (`setInterruptState`) and a real `unregisterInterrupt`; deliver them from `dm_crtc_high_irq` (hook in `amdgpu_dm_crtc_handle_vblank` -> `nmx_fb_vblank()`), with `drm_crtc_vblank_get` held while any ref is enabled and dropped when none is (vblank off and IPS allowed when idle, as on Linux); the timer stays only as a fallback when the CRTC is off | low-medium (callbacks run on the IH work-loop thread; `signalVBLInterrupt` only stamps and kicks event sources, safe) |
| **3** | flip completion (L6 vs P11) | `dm_pflip_high_irq` completes the event in the IRQ | the IRQ already completes `flip_done`, but NMXAccel learns it by **polling every 200 µs on a thread call** (up to 50 ms) | +0-200 µs and a thread-call wake per frame; 5 000 wakeups/s while a flip is pending | L, W, **P** | source (high); 5.85 ms mean submit->seen. Section 5: Apple's completion carries the presentation time at **tx+0x170**; AMD writes it at its flip-done IRQ, Intel from hardware; if 0 the family writes the completion time, so WindowServer is told our poll's time, not the scan-out time (high for the family, medium that CoreDisplay paces from it) | NMXAccel: write the latching vblank's time into tx+0x170 before `signalTransactionInterrupt` (NMXGPU `nmxFlipStatus` already returns `vblankNs`; better: the pageflip IRQ time from the trace hook). NMXGPU: add `nmxFlipNotify` (callback + refcon registered by NMXAccel) called from `flip_refresh` path in the pflip handler (hook after `drm_crtc_send_vblank_event` for our CRTC); NMXAccel calls `signalTransactionInterrupt` from a thread call kicked by it | low |
| **4** | serial present thread (L4 vs P6/P7) | non-blocking commit returns at once (`-EBUSY` if pending); fence wait on the commit worker | `performTransaction` waits for the fence (to 100 ms) and for the previous flip (to 20 ms) inline on the one pipe thread | one late frame delays the next transaction behind it; WindowServer's transaction queue backs up | P, L | source (high), drops 0 so far (the queue absorbs it) | follows from 1 and 3: with the fence in the commit and the latch notified, `performTransaction` never sleeps | low |
| **5** | client -> compositor sync (L2/L3 vs P1/P2) | one BO and one resv shared by all processes; the compositor's GPU job waits in the scheduler | each process has its own userptr BO of the same pages; ordering lives in user space (completion pumps, seeds); non-host-backed surfaces take CPU copies (`nvmtlSurfaceIn/Out`) | clients may wait for GPU completion on the CPU before CoreAnimation commits; CPU copies scale with resolution | P, L, W (CPU) in the apps the owner names (Electron strokes, Maps) | source (medium); how often surface-in/out copy under load: not counted -> instrumentation | NMXGPU: one GEM object per IOSurface ID shared by all importing processes (lookup through the surface hint, `drm_gem_object` refcount), so the CS adds and waits fences on one resv (`amdgpu_sync_resv`) as on Linux | high (cross-process object lifetime, WindowServer stability) |
| **6** | vblank refs and IPS (L7/L8 vs P13) | compositors hold vblank on while animating, so IPS/PSR stay off during motion | only the flips hold refs; at ~27 presents/s the CRTC's vblank IRQ can go off between presents (`disable_immediate` on DCN 3.5 APU without PSR) and `dc_allow_idle_optimizations(true)`; the next flip flushes `vblank_control_workqueue` to exit idle first | IPS entry/exit per content frame adds exit latency to the flip and churns DMUB | L, W | code path (high); whether IPS actually enters on this boot: **unknown** (`ips_support`, DMUB IPS counters only printed at suspend, `amdgpu-dm-ips-trace.patch`) | same as fix 2 (vblank ref while WindowServer wants VBL); export the DMUB IPS entry/exit counters as a sysctl (instrumentation) | low |
| **7** | interrupt context (L6/L9 vs P10/P14) | IH ring processed in hard IRQ | IH processed on an IOWorkLoop thread (kernel priority) | fence signal, pflip and vblank wait for a thread wake; one thread for all vectors' work on ring 0 | L | source (high); size: small at kernel priority, **not measured** | measure first (IRQ -> handler latency in the ring); an `IOFilterInterruptEventSource` whose filter only timestamps is cheap and safe | low (timestamp only) |
| **8** | timers (L9/V4 vs P15) | per-CPU timer softirqs, hrtimers in hard IRQ | one softclock thread runs every callout in order; a callout that sleeps on its lock delays all the others | jitter in vblank-off timers, fence fallback, VCN idle gating, sched timeouts | P (indirect), W | source (high); impact unknown | per-callout lateness counter (deadline vs run start) in `softclock_thread`; if late, a small pool of softclock threads or `thread_call` per callout class | low |
| **9** | memory policy (L2 vs Steps 141-142) | TTM pool shrinker + eviction under pressure, MMU notifiers | 2 MB chunk pool and IOSurface park/unpark on timers (5 s / 60 s / 10 min); xnu never fires `vm_lowmem` | re-wire of a parked surface on first use after 60 s idle (tab switch, Mission Control) costs a burst; pool timers wake periodically | M, occasional L | Step142 probes clean (handoff 5.2); 1828 parks / 644 unparks in 23 min | keep; replace timers by xnu memory pressure later (out of scope for stutter) | - |
| **10** (first for gaps > 100 ms, see 3.1) | memory work on the submit thread (L2 vs Step92/142, Step141 pool) | compositor surfaces are TTM BOs (GTT/VRAM) moved only by the shrinker when idle; userptr pages are faulted by `amdgpu_ttm_tt_get_user_pages` in `amdgpu_cs_parser_bos` **before** `drm_exec_until_all_locked` | every IOSurface is a userptr BO of pageable user memory; Step142 unwires it after 60 s idle, the compressor/swap may take the pages, and the next CS re-wires it in `amdgpu_ttm_tt_populate` -> `nmx_upin_restore` -> `IOMemoryDescriptor::prepare()` **inside `ttm_bo_validate`, holding the process's VM PD lock and the BO reservations**, on the submitting thread (WindowServer or Chrome's GPU process). New imports wire with `prepare()` on the same thread (`nmx_xnu_user_wire`, `surf_wire`). When the chunk pool is empty, `single_alloc` makes a 2 MB wired chunk (`IOBufferMemoryDescriptor` + `prepare()`) inline on the allocating thread | a swap-in or a wait for 512 free pages lands directly in a frame: hundreds of ms to seconds under pressure, nothing else in the path can make gaps that long | **P** (the 402 ms / 4.1 s gaps), L | video-suite (correlation, high): every drop second under memory pressure had swap-ins, chunk fills 2/6 drop seconds vs 2/245 clean; park/unpark **counts** do not discriminate, which is expected: one slow re-wire costs a second, many fast ones cost nothing; only latency tells -> stall ring (section 7, `468a78d`). Source (high): `amdgpu_cs.c` lines 906-910 (`if (0)` around the pre-lock fetch, Step92), `amdgpu-userptr-park.patch` populate hunk, `nmx_page.c` `single_alloc`/`chunk_new` | (a) `amdgpu_cs_parser_bos`: re-enable the pre-lock userptr loop for **parked** entries only and call `nmx_upin_restore` there, so the slow part runs before any lock (as Linux does) and the populate finds the pages wired; (b) `amdgpu_ttm_tt_nmx_touch` / surface-hint lookup: when a parked BO is looked up for a new CS, kick the re-wire on a thread call ahead of the submit (WindowServer composites the same surfaces frame after frame, so the first frame pays at most once); (c) never park a BO that was flip-imported or used by WindowServer in the last N frames (keep the pages of on-screen surfaces wired; park only background ones); (d) `single_alloc`: when the pool is empty, allocate just the one page (or a 64 KB run) inline and leave the 2 MB chunk to `fill_worker`; (e) the pressure itself: see 3.1 (RyzenHV wires 12.3 GB of guest RAM) | medium (a, c: ordering with Step142's park state machine and the BO list mutex); low (b, d) |
| **11** | Chrome H.264 decode (V1/V2 vs PV1) | VA-API on VCN for H.264/HEVC/VP9/AV1 | `VCNDec` (`tools/890m/vcndec/Info.plist`) registers only `vp09` and `av01`; Chrome asks VideoToolbox for a **hardware** H.264 decoder, gets none, and uses FFmpeg on the CPU | each H.264 stream adds one to two cores of user-priority decode plus CPU copies into IOSurfaces; this is part of the 731 % CPU in drop seconds and it competes with every user-space hop in rows 1 and 5 | P (video), W | main (H.264 falls back to FFmpeg, high); `Info.plist` and `vcndec.c` line 152 (`codec not handled` for anything but vp09/av01) (high); Step106: VCN H.264 decode bit-exact with the test RADV build (high) | `VCNDec`: add `avc1` (and `hvc1`) decoder entries in `Info.plist`; in `vcndec.c` map them to `AV_CODEC_ID_H264` / `AV_CODEC_ID_HEVC` and pass the `avcC`/`hvcC` atom from the format description as extradata (VideoToolbox hands length-prefixed NAL units, which libavcodec takes with that extradata); check with `vt_test` and Chrome `chrome://media-internals` -> `VideoToolboxVideoDecoder`. Owner: video-suite session | low-medium (VT's H.264 format-description edge cases: interlaced, 4:2:2 profiles must be refused cleanly) |
| **12** (correctness; each one is a 3 s gfx stall) | GPU write through an invalid PTE in the VideoToolbox decoder (V2 vs PV2) | every BO a job touches is in its BO list (or VM-always-valid); the CS re-validates it, rewrites its PTEs with a TLB flush (`amdgpu_vm_bo_update`: `moved` -> `flush_tlb`), and the job waits for that update; a userptr invalidation (MMU notifier) first waits for the BO's fences | 23 gfx faults this boot (11:27-12:44): TCP write, `PERMISSION_FAULTS 0x5` + `MAPPING_ERROR 0` = the PTE exists but has V = 0, in VTDecoderXPCService pasids (32816/18/19/22/38), each followed by a 3 s "ring gfx timeout, soft recovered" and VCNDec "copy fence" -12911 | Linux writes V = 0 exactly for a BO placed in SYSTEM (`amdgpu_ttm_tt_pte_flags`) or a freed mapping; Step142 parks idle IOSurface userptr BOs to SYSTEM, and that process has 251 522 parked pages; the listed-BO path re-validates them as Linux does, so the open question is which BO the job wrote and why it was not re-validated | P (3 s), memory safety | fault decode and Linux source (high); park as the source: **medium (~50 %)**, freed mapping (VCNDec/RADV import churn) ~30 %, TTM eviction under GTT pressure ~20 %; see 10 | decide first: fault-time VA -> BO lookup (10.3), A/B `debug.nmx_userptr_park_ms=0`; then the fix in 10.4 | the lookup is read-only in the IH path (trylock) |
| **13** (memory; feeds rows 9-10 and the CS -ENOMEM) | how GPU memory that is idle goes back to the OS (V4 vs Step142) | GTT BOs are TTM pages: on the LRU, swapped to shmem when idle under pressure (`ttm_bo_swapout`, shrinker); userptr pages are not pinned (HMM) | every native BO is a wired TTM page for its whole life (`nmx_pages_live` 4.15 GB at 16:10). In **WindowServer**, Step142 park never fires: 439k surface pages wired, 0 parked, because every "surface upload" submit is not marked exact and carries the whole surface list, so each import is touched every frame. `setPurgeableState:` on buffers is recorded and nothing else happens | M (several GB wired minutes after boot), then P via row 10 | section 11; counters read 2026-11-18 16:08-16:12; the plugin cause is read in the source, confidence high; the WS split between imports and own BOs is approximate | plugin: mark internal submits exact (11.4 a); honour Volatile/Empty on buffers and heaps (11.4 b). NMXGPU: swap out idle native TT BOs to pageable memory (11.3) | a too-narrow exact list = a GPU page fault (row 12 class); swap-out = latency on the first use after idle |

Not a divergence any more (killed with today's counters): flip-import churn (11 imports in 23 min, 0 failures), CPU
copy to the panel (fallback 0, K6/beam counters 0), pipe drops (0), flip timeouts (0).

### 3.1 Under CPU contention and memory pressure (video-suite evidence, 2026-11-18)

Main's correlation: seconds with dropped frames had ~731 % total CPU vs ~277 % clean; under memory pressure every drop
second had swap-ins (worst frame gap avg 402 ms, up to 4.1 s); IOSurface parks/unparks did not discriminate; chunk fills
were over-represented. What that means for the ranking:

**Gap size separates the causes.** Rows 1-4 cost 0.1-10 ms per frame (a 100 µs poll, a 200 µs poll, a 31T thread
waiting for a core while 24 logical CPUs are 30 % busy). They explain jitter and a dropped frame here and there, not a
400 ms or 4 s hole. A hole that long needs a thread that **blocks**: a page-in from swap, decompressing from the
compressor, or waiting for free pages to wire. Row 10 lists every place where our frame path does that synchronously.
So: for gaps > 100 ms row 10 comes first; rows 1-3 stay first for ms-level pacing.

**Where each frame-path thread runs (priority) vs Linux:**

| work | here | priority | Linux |
|---|---|---|---|
| IH ring (fence signal, pflip, vblank) | `IOInterruptEventSource` on an `IOWorkLoop` thread (`xnu/nmx_pci.cpp`) | kernel thread, 81 | hard IRQ |
| `nmxFlipPoll`, VBL timer `vblFire`, pool `fill_worker`/`release_worker` | `thread_call_allocate` (default group) | thread-call high group, above all user threads | hrtimer / kworker |
| LinuxKPI callouts (fence fallback, vblank-off, VCN idle, `delayed_work` timers) | one `nmx softclock` thread (`nmx_task.c`, `kernel_thread_start`) | 81 | per-CPU timer softirq |
| LinuxKPI workqueues (DM commit worker, `vblank_control_workqueue`, drm sched) | taskqueue threads (`kernel_thread_start`) | 81 | kworkers at nice 0 (normal!) |
| display pipe `performTransaction`, fence poll | NMXAccel on the pipe's work-loop thread | kernel | (in the commit worker) |
| GPU-done -> `NMXFenceDone` | plugin `nvmtl.execution`, no QoS | **31T** | (in the kernel) |
| app/Chrome GPU-process submit, CPU surface copies, H.264 FFmpeg decode | user threads | 31-47 | same (user space) |

Every kernel-side stage already outranks every user thread (WindowServer's own render threads are 79R), and the Linux
equivalents of the commit worker and drm scheduler are plain nice-0 kworkers. So **CPU contention cannot starve the
kernel side of our path**; it reaches the path only through the user-space hops: row 1 (`nvmtl.execution` at 31T) and
the clients themselves (Chrome's GPU process and its software H.264 decode, row 11). The fix for row 1 removes the one
hop that Linux does not have; row 11 removes most of the extra CPU load.

Two cautions on the 731 % figure:
- Swap-ins and compressor work **cost CPU**: decompressing pages, the swapper, `kernel_task` page-out. High CPU and
  swap-ins in the same seconds may be one event, not two causes. The stall ring (pid + duration) and a `vm_stat 1` next
  to the capture separate them.
- The Docker VM is not a normal user process: `RyzenHV` runs guest code from the host kernel. If a vCPU entry does not
  exit promptly on host interrupts or does not check for preemption between entries, it can hold a core against
  priority-81/95 kernel threads too, and then the "kernel side outranks user space" argument above does not hold for
  that core. Question for the RyzenHV owner (no change here): are physical interrupts intercepted (SVM `INTR`/`NMI`)
  and does the run loop return to the scheduler on `ast_pending`/preemption? The trace answers it indirectly: a late
  frame whose `notify` or `worker` (kernel-only stages) is long while no memory stall overlaps it.

**Memory pressure has a source we own.** RyzenHV wires the Docker VM's RAM (12.3 GB wired, the largest consumer under
daily load, see memory note `ryzenhv-wires-guest`). Linux KVM keeps guest RAM as ordinary anonymous memory that the
host can reclaim (and free-page reporting/balloon returns it). With 12 GB unpageable, every other process, including
WindowServer's heap and the IOSurfaces Step142 has parked, is squeezed into the rest, and row 10's synchronous
re-wires start to hit swap. The frame-path fixes (row 10 a-d) keep the swap-in off the frame; making guest RAM pageable
(or capped/ballooned) removes most of the pressure. That is RyzenHV's scope; listed here because it decides how often
row 10 fires.

### 3.2 First trace run (out-30, 2026-11-18 10:48, 340 s) and the CS -ENOMEM crash

**Capture** (`tools/890m/frame-path-capture.sh 300`, joined over all snapshots with
`tools/890m/frame-path-aggregate.py`): uptime 8 min, Claude + Chrome + Edge helpers + the owner's apps, **Docker not
started**, RTX gated, Balanced. 44 MB free, 7.6 GB wired at start; no swap file yet. 4106 flips (about 12/s, mostly a
quiet desktop).

| stage | p50 | p90 | p99 | max (ms) |
|---|---|---|---|---|
| gpu (commit -> GPU end) | 1.64 | 4.60 | 10.47 | 11.89 |
| wake (GPU end -> plugin saw it) | 0.60 | 1.66 | 1.99 | 3.17 |
| handoff (plugin -> pipe saw it) | 0.10 | 2.54 | 5.79 | 10.59 |
| pipe | 0.01 | 0.02 | 0.03 | 0.08 |
| worker (submit -> armed) | 0.14 | 0.23 | 0.36 | 8.34 |
| scanout (armed -> pageflip IRQ) | 5.32 | 8.11 | 10.67 | 15.29 |
| notify | 0.15 | 0.24 | 0.27 | 13.44 |
| **total (commit -> pageflip)** | **9.27** | 12.29 | 18.06 | 20.69 |

Reading: under this load **no frame took more than 3 refresh periods**. 246 frames (6 %) took more than 2 periods;
the largest stage in them was scanout 150 (the frame arrived just after a vblank and waited for the next one), gpu 84,
worker 11 (a flip submitted while the previous one was still pending waits one vblank in the commit worker; this is
Linux's own `amdgpu_dm_commit_planes` behaviour). Row 1 is visible but small: `handoff` > 4 ms in 138 frames (3.4 %),
up to 10.6 ms. Row 2 is confirmed: the IOFramebuffer VBL timer fired at phases spread over 10 of 16 bins of the real
frame, and in 60 % of its fires the vblank IRQ had been off for > 2 frames. Memory stalls: 625 stalls >= 1 ms in the
window (wire 308, fill 299, restore 18); 12 late frames overlapped one, and those stalls were in other processes
(Claude Helper 1744, Chrome helpers 4341/5826) or the fill thread, not on WindowServer's own submit. Wire max 23 ms,
restore max 9.8 ms, fill (background) max 54.8 ms. No WindowServer-blocking stall in this run: row 10 needs the run
**with Docker up** (pressure) to be judged; that run is still to do.

### 3.3 out-33 run (2026-11-18 15:58, 316 s) against 3.2

**Capture:** `~/ga403-logs/frame-path-out33-1558`.
- Conditions: uptime 4-9 min, the owner's normal use, Docker not running, no gfx fault on this boot.
- Build: out-33 = `2b25e54`, rows 1-3 on.
- 3592 frames were joined; **3524 (98 %) took the kernel fence** (waited = 2).

| stage | out-30 p50 / p90 / p99 / max | out-33 p50 / p90 / p99 / max |
|---|---|---|
| gpu | 1.64 / 4.60 / 10.47 / 11.89 | 0.04 / 1.49 / 2.33 / 2.56 |
| wake (plugin) | 0.60 / 1.66 / 1.99 / 3.17 | 0.24 / 0.32 / 0.40 / 0.40 (only the 68 non-kfence frames) |
| handoff (plugin -> pipe) | 0.10 / 2.54 / 5.79 / 10.59 | 0.10 / 0.13 / 0.15 / 0.15 (68 frames); **> 4 ms: 138 -> 0** |
| pipe | 0.01 / 0.02 / 0.03 / 0.08 | 0.01 / 0.03 / 0.04 / 0.08 |
| worker (submit -> armed, now includes the render wait) | 0.14 / 0.23 / 0.36 / 8.34 | 0.24 / 2.58 / 5.84 / 12.12 |
| scanout (armed -> pageflip) | 5.32 / 8.11 / 10.67 / 15.29 | 5.46 / 8.12 / 8.46 / 12.74 |
| notify (pageflip -> NMXAccel saw it) | 0.15 / 0.24 / 0.27 / 13.44 | **0.00 / 0.00 / 0.00 / 0.00** |
| **total (commit -> pageflip)** | 9.27 / 12.29 / 18.06 / 20.69 | **6.05** / 12.74 / **14.60** / 26.67 |

- **Late frames:** more than 2 periods or a missed vblank: 246 (6 %) -> **46 (1.3 %)**; more than 3 periods: 0 -> 1.
- **Blame in the late frames:** scanout 42, worker 4.

**Rows 1-3 are confirmed fixed on this run.**
- **Row 1:** the GPU wait moved from user space into the commit worker, where Linux has it. That is why `worker` grew
  (p99 5.84 ms is WindowServer's render job), and the handoff stage is gone for 98 % of frames.
- **Row 3:** notify is 0.
- **Row 2:** the IOFramebuffer VBL timer fired 9 times in 316 s (was about 120/s, with its phase spread over 10 of 16
  bins), and `vbl_held` was 1 at the end of the run.

**Largest remaining stage: scanout (p50 5.5 ms).**
- This is the wait from "armed" to the next vblank. Linux's flip has the same wait, so it is not a divergence. At 120 Hz
  it averages half a period, and it is what makes up most late frames: a frame that is ready just after a vblank waits
  one full period.
- Two things outside our pipe come after it.
  - **WindowServer arrives late:** commit (`NMXFencePendingT`) -> `performTransaction` entry has p50 0.25, p90 3.69,
    p99 6.29 and max 21.6 ms. The single very late frame (26.7 ms) spent 19 ms here, before any stage of ours.
  - **Memory stalls in WindowServer itself (row 10):** 51 surface-wire stalls of at least 1 ms in pid 210 (p50 3.0,
    p90 5.4, max 6.5 ms); 6 late frames overlapped a stall.
- Memory got tight without Docker. vm_stat free went from 233k to 4k pages, and compression started in the last
  minute. Row 10 still needs the Docker run.

### 3.4 Under Docker load (2026-11-18 16:11, 312 s) against 3.3

**Capture:** `~/ga403-logs/frame-path-out33-docker-1611`.
- Load: Docker with 8 vCPUs (guest wired lazily, 3.0 GB by the end), plus the video suite's codec matrix in Chrome, Safari and QuickTime.
- Memory at the end: free 5k pages, wired 17.8 GB, compressor 6.6 GB.
- GTT used went from 6.7 GB to 10.1 GB. WindowServer held 5.17 GB and Safari's GPU process 1.83 GB.
- 9243 frames were joined (2.6x the 3.3 run); 9178 took the kernel fence.

| stage (ms) | 3.3 p50 / p90 / p99 / max | Docker p50 / p90 / p99 / max |
|---|---|---|
| gpu | 0.04 / 1.49 / 2.33 / 2.56 | 0.09 / 1.00 / 2.69 / 4.03 |
| wake (non-kfence frames) | 0.24 / 0.32 / 0.40 / 0.40 | 0.28 / 0.55 / 1.19 / 1.19 |
| handoff (non-kfence frames) | 0.10 / 0.13 / 0.15 / 0.15 | 0.09 / 0.14 / 0.20 / 0.20 |
| pipe | 0.01 / 0.03 / 0.04 / 0.08 | 0.02 / 0.03 / 0.04 / 0.08 |
| worker | 0.24 / 2.58 / 5.84 / 12.12 | 0.28 / 1.52 / 4.86 / 18.06 |
| scanout | 5.46 / 8.12 / 8.46 / 12.74 | 4.96 / 6.61 / 8.24 / 14.01 |
| notify | 0 | 0 |
| **total** | 6.05 / 12.74 / 14.60 / 26.67 | **5.73 / 9.33 / 14.31 / 24.96** |

**Late frames:** 76 of 9243 (0.8 %), none later than 3 periods. Blame: scanout 69, worker 7. Worker above 4 ms: 139.

**Row 10 under pressure: memory stalls on the submit path.** Deltas over the run, counted in every process:

| kind | n | total ms | ≥ 1 ms | ≥ 10 ms | max |
|---|---|---|---|---|---|
| surf (surface wire) | 1676 | 2130 | 273 | **59** | 93.7 ms |
| wire (user wire) | 993 | 1258 | 201 | 22 | 39.6 ms |
| fill (pool page fill) | 1268 | 1704 | 449 | 15 | 16.8 ms |
| restore (Step142 unpark) | 479 | 147 | 11 | 6 | 14.5 ms |

- The 3.3 run had one stall of 10 ms or more. This run had **102**.
- They fall on the **clients'** submits: Claude Helper (surf ×127), Safari's WebKit GPU process (wire ×99, surf ×52), Docker Desktop Helper (surf ×34), VTDecoder (wire ×31) and the pool fill (×336). WindowServer has only 21.
- Only 7 late composited frames overlapped a stall. The worst were wire 9.2 ms, and restore 14.5 / 13.2 ms on frame 32161.
- So under pressure, row 10 costs the **apps' frame production** (video players, browser GPU processes), not WindowServer's composition. This WindowServer-side trace cannot see those as late. A dropped video frame shows up in the player's own counters.
- `nmx_page_alloc_waits` stayed 0: the pool never ran dry. The time goes into wiring user and surface pages while the VM is compressing.
- What reduces it: rows 9-10 and row 13. Fewer wired pages mean less compressor churn, and parked imports are re-wired only when used.

**Pages held by the port grow.** `debug.nmx_pages_live` (wired pages the port's TTM pool hands out for GTT/system BOs)
went from 619 194 (2.4 GB) at 10:48 to 1 111 779 (4.3 GB) at ~11:00, while userptr wirings stayed ~0.6 GB. All of it
is wired. Linux's TTM pool pages are also unswappable, but its shrinker gives back idle BOs (`ttm_global_swapout`); our
xnu port never sees a shrinker call. Watch it across the Docker run; if it keeps climbing with no matching BO count,
it is a leak, otherwise it is the missing shrinker.

**CS -ENOMEM (previous boot, 10:35:15).** `amdgpu_cs_ioctl` printed "Not enough memory for command submission!" in
WindowServer (pid 207); the plugin logged upload/buffer-create FAILED, marked the Vulkan backend down and exited;
WindowServer relaunched and hit a userspace watchdog. Where it can come from (all inside `amdgpu_cs_parser_bos`,
the only caller that prints this text):

| source | how it returns -ENOMEM here | Linux at the same spot |
|---|---|---|
| `ttm_tt_populate` -> `ttm_pool_alloc` -> `alloc_pages(GFP_USER)` -> our `linux_alloc_pages` -> `vm_page_alloc_noobj` -> `single_alloc` | the pool is empty and one 2 MB `IOBufferMemoryDescriptor` cannot be made: **NULL at once**. `linux_alloc_pages` drops `M_WAITOK` | an order-0 `GFP_USER` allocation enters direct reclaim and retries; it does not fail for small orders (OOM killer first). FreeBSD's own `linux_alloc_pages` loops on `vm_wait` |
| `ttm_bo_validate` -> `ttm_bo_alloc_resource` -> GTT manager full (`-ENOSPC`, 16 GB: half of RAM) -> `ttm_bo.c:875` turns it into -ENOMEM | every process's userptr BO of the same IOSurface counts (row 5), and VRAM is only 512 MB, so everything else is GTT too | same rule, but eviction to SYSTEM frees GTT space first; fewer duplicate BOs |
| Step142 `nmx_upin_restore` | malloc of the phys array (`M_WAITOK`, practically never fails) or `pin_attach`; a failed re-wire returns -EFAULT, not -ENOMEM | (no park on Linux) |
| `ttm_tt_populate` page limit | `ttm_pages_limit` = half of RAM; `ttm_global_swapout` then has nothing to swap on xnu | shmem swap-out of idle BOs |

Which one fired is not in the log: `nmx_cs_report_name` (the per-stage CS log) had spent its whole 48-line budget at
08:55:48 on `userptr_ro_retry -> 0` info lines. Also, RADV already retried that submit for 1 s with 1 ms sleeps
(`radv_amdgpu_cs.c`, -ENOMEM loop) before returning `VK_ERROR_OUT_OF_HOST_MEMORY`, so the shortage lasted more than a
second: real pressure (or a full GTT), not a blip. Why it is fatal here: the plugin treats any `vkQueueSubmit` error as
a lost device (`nvmtl_vk.c`, `g_state = -1`), although Vulkan defines an out-of-memory submit as "not submitted, device
intact".

Fixes, pushed to `fork`, compile-checked, not built or installed:
- `fix/cs-enomem` (nvidia-macos-driver-ws, ff060ea, on top of the trace branch 8d1a8c2): `linux_alloc_pages` passes
  `VM_ALLOC_WAITOK` for `M_WAITOK` without `__GFP_NORETRY`; `single_alloc` falls back to a one-page run when no
  chunk can be made, and a caller that may sleep backs off 1..64 ms and retries for up to 2 s (counters
  `debug.nmx_page_single_runs`, `_alloc_waits`, `_alloc_fails`). `nmx_cs_report_name`: info lines (r 0) and -ENOMEM
  get budgets of their own, so the next failure names its stage. Risk: low-medium (a populate may now sleep up to 2 s
  holding the BO reservation, as Linux's reclaim does; better than an exit).
- `fix/cs-enomem-plugin` (97725ba, off `integ/out30-plugin` 17b4cdf): an out-of-memory `vkQueueSubmit` is retried
  with 1..64 ms back-off for up to 2 s before the backend is given up; `NVMTL_CS_OOM_RETRY=0` turns it off. No new
  compile errors (the same 21 header errors as the base in this checkout).
- Not done, needs the stage name first: if it is the GTT limit, the real fix is row 5 (one BO per IOSurface) plus
  counting GTT usage in a sysctl; if it is the page pool, the shrinker above.

**`idle_allowed 0` and all-zero IPS counters (power).** `disable_ips 6` is `DMUB_IPS_RCG_IN_ACTIVE_IPS2_IN_OFF`, the
same DCN 3.5 default Linux picks (`dm_get_default_ips_mode`). DC allows idle only when no CRTC holds a vblank IRQ
(`amdgpu_dm_crtc_vblank_control_worker`: `active_vblank_irq_count == 0`) and the eDP has PSR or Replay
(`dcn35_apply_idle_power_optimizations`; this panel reports "PSR support 1, DC PSR ver 0" = PSR1). Main's read at
6 min had `idle_allowed 0`; my read at 10:52 had `idle_allowed 1`, so DC does reach the allowed state when the
desktop is still. But the DMUB counters (rcg/ips1/ips2 entry/exit) stayed 0 in both. Either the firmware never
entered RCG/IPS1 (it enters only while the panel is in PSR self-refresh with nothing pending) or this firmware does
not fill those counters. For power: if IPS never enters, the display engine, its DMUB and the related clock domains
stay powered for as long as the screen is on, even on a static screen; on DCN 3.5 that is the main display-idle
saving (expect hundreds of mW at a static desktop; not measured here). A possible counter leak to keep in mind:
`amdgpu_dm_crtc_set_vblank` returns before queueing the vblank-control work if `amdgpu_irq_get/put` fails, which
would leave `active_vblank_irq_count` above 0 for good. To separate the cases: on Linux (one boot, same panel)
`cat /sys/kernel/debug/dri/*/amdgpu_dm_ips_status` and `.../eDP-1/psr_state` on a static desktop (counters move
there = our port does not reach IPS); on macOS, add `psr_settings.psr_allow_active`, `psr_feature_enabled` and
`dm->active_vblank_irq_count` to `debug.nmx_frametrace` (flags only, no DMUB query, so reading it cannot wake IPS).

## 4. Questioning the handoff's assumptions

- (a) "software VBL instead of the CRTC's vblank/pageflip interrupts": half right. Flips are latched by DCN at the
  real vblank and the real pageflip IRQ completes `flip_done` (`hw_mismatch` 0). What is fake is (i) the IOFramebuffer
  VBL timer and (ii) how NMXAccel learns the latch (200 µs poll). Rows 2 and 3.
- (b) PSR/IPS: still unknown; the code path that toggles IPS per present exists (row 6). PSR caps of the OLED are not
  known on this machine from any saved Linux log (see 6).
- (c) wire/park: real but not the stutter lead; the larger structural issue is that each process has its own pinned
  copy of the surface's BO, so sync moved to user space (row 5).
- (d) "~5 ms WindowServer per frame with a synchronous commit": the synchronous commit is gone since Step95; the wait
  moved to NMXAccel's pipe thread (row 1, 88 % of frames, 1.47 ms) and its source is a user-space thread.
- (e) `vm_lowmem`: true, memory-only (row 9).
- The Linux dump (`docs/890M-LINUX-DUMP.md`) was taken with the MUX in Ultimate (`gpu_mux_mode=0`, eDP on the RTX):
  the 890M had **no CRTC lit** ("Cannot find any crtc or sizes", eDP-2 disconnected). It holds no reference value for
  the panel on the 890M (no vblank, PSR, IPS or flip data).
- "YouTube dropped frames" measures Chrome's frame production; the pipe itself reported 0 drops. Rank by stage
  timestamps instead (section 7).

## 5. Closed side (REA): what Apple's display pipe and framebuffer expect

NMXAccel and NMXAGDC are our source, so reverse engineering covered only Apple's side, statically, in
`/System/Library/KernelCollections/SystemKernelExtensions.kc` (IOAcceleratorFamily2, IOGraphicsFamily, AMDRadeonX6000,
AppleParavirtGPU, AppleIntel*Framebuffer; `tools/kc_disasm.py`). Full notes with disassembly excerpts:
`side-session-notes/.../frame-path-apple-re.md` (sibling notes folder). System-KC addresses.

| finding | function (address) | confidence |
|---|---|---|
| The pipe gets the hardware vblank from the framebuffer: `displayModeDidChange` calls `fb->registerForInterruptType('vbl ', IOAccelDisplayPipe::signalVBLInterrupt, this, 0, &pipe+0xd8)`, then `setInterruptState(ref, 0)` | `IOAccelDisplayPipe::displayModeDidChange` (0x14baf6e2) | high |
| `enable/disableVBLInterrupt` are refcounted `fb->setInterruptState(ref, 1/0)`; callers: the user-client "notify at next vblank" request and `enableTransactionInterrupt` | 0x14bb25c0 / 0x14bb25fe, `request_notify_gated` (0x14bb2de0) | high |
| `signalVBLInterrupt` = the per-vblank entry: stamps uptime at pipe+0x268, calls `signalTransactionInterrupt` if "complete on vblank" (+0x281) is set, wakes `vbl_interrupt_gated`, which answers waiting user clients with {vbl time, vbl time + frame length} and turns the vblank off again | 0x14baf886, 0x14bb1cb4 | high |
| Base `enableTransactionInterrupt` = `enableVBLInterrupt` + set +0x281: by default completion is checked on every vblank | 0x14bb2634 | high |
| Completion to user space: 11 qwords from tx+0x158; **tx+0x170 = presentation time**; the family writes `mach_absolute_time()` there at completion only if the driver left it 0 | `completeTransaction` (0x14bb2326), `sendNotification` (0x14bb2478) | high (mechanics), medium (meaning of +0x178..+0x190) |
| `beginTransaction`, `signalTransactionComplete` are empty; `submitTransaction` returns unsupported unless overridden | 0x14bb2674, 0x14bb267a, 0x14bb218c | high |
| AMD X6000: registers framebuffer interrupts `'txni'` (flip done -> `processTransactionInterrupt`, which sets tx+0x170 if 0, then `signalTransactionInterrupt`) and `'fstr'` (frame start, VRR); falls back to vblank polling | `AMDRadeonX6000_AMDAccelDisplayPipe` (0xbdd0d2d, 0xbdd0df4, 0xbdd0ece) | high |
| Paravirt: its host IRQ calls `signalVBLInterrupt` directly | `AppleParavirtDisplayPipe::signalDisplay` (0x148a3834) | high |
| Intel: base vblank path; writes tx+0x170..0x190 from hardware timestamps | `AppleIntelFramebuffer::reportTimestamps` (0x141f353e) | high |
| IOFramebuffer: `open` registers `'vbl '` -> `handleVBL` (vblank time/delta/count in StdFBShmem, wait-for-vblank sleepers); the base class only implements `'mccs'`, so `'vbl '` is the subclass's job; consumers found: gamma/CLUT timing, `getVBLTime`; no WindowServer frame-pacing use found | 0x14cfd976 / 0x14cfe15d, 0x14cf870a, 0x14d04960 | high / medium |

Not established: the meaning of tx+0x178..0x190; which user-client selector is the vblank-notify one and whether
CoreDisplay/IOPresentment use it (no extracted CoreDisplay/IOPresentment on disk; `ipsw` not installed; downloading
needs main's OK); which registration owns NMXAMDFB's slot on a given boot.

Consequences for us: rows 2 and 3. The stock family already polls completion on each real vblank once the pipe gets
real vblanks, so NMXAccel's own 200 µs poll becomes unnecessary; AMD's own driver is the model (flip-done interrupt ->
tx+0x170 -> `signalTransactionInterrupt`).

## 6. Linux-side evidence on this machine and what one Linux boot would add

Saved: only `docs/890M-LINUX-DUMP.md` (Ultimate MUX, panel not on the 890M). Worth one Linux boot **in Standard/Eco
MUX (`gpu_mux_mode=1`, panel on the 890M)**, optional:

```bash
sudo cat /sys/kernel/debug/dri/0/eDP-1/psr_capability /sys/kernel/debug/dri/0/eDP-1/psr_state
```
```bash
sudo cat /sys/kernel/debug/dri/0/amdgpu_dm_ips_status
```
```bash
sudo cat /sys/kernel/debug/dri/0/eDP-1/replay_capability /sys/kernel/debug/dri/0/eDP-1/replay_state 2>/dev/null
```
```bash
sudo trace-cmd record -e drm:drm_vblank_event -e drm:drm_vblank_event_queued -e drm:drm_vblank_event_delivered -e amdgpu_dm:amdgpu_dm_atomic_commit_tail_begin -e amdgpu_dm:amdgpu_dm_atomic_commit_tail_finish -e amdgpu:amdgpu_cs_ioctl -e dma_fence:dma_fence_signaled -- sleep 20
```
(run during 1080p60 playback in mpv with `--vo=gpu-next --hwdec=vaapi`, then `trace-cmd report > flips.txt`: flip
cadence, vblank-to-flip margin, whether vblank IRQs stay on between frames)
```bash
sudo turbostat --quiet --show PkgWatt,CorWatt,GFXWatt,Busy%,Bzy_MHz --interval 5 --num_iterations 12
```
(same playback; package power reference for the same video)
```bash
cat /sys/kernel/debug/dri/0/amdgpu_pm_info | grep -i -A3 vcn
```
(VCN power state between frames). The names of the debugfs files differ between kernels; `ls /sys/kernel/debug/dri/0/`
first.

## 7. Instrumentation (ranks rows 1-4 and 6 with one run)

Branches, pushed to `fork` only, compile-checked, **not built into a kext by me, not installed**:

| branch | commit | files |
|---|---|---|
| `frame-path/kernel-trace` (repo `nvidia-macos-driver-ws`, off `nmx-source-port` 4f6825b) | 64c11a5, 468a78d | `gpu-port/xkpi/patches/amdgpu-dm-frametrace.patch` (+ `series`), `override/src/nmx_fb_bridge.c`, `xnu/nmx_fb.cpp`, `xnu/nmx_kext.cpp`, `kexts/NVRM/accel/nvrm-accel.cpp`; 468a78d adds `bsdcompat/src/nmx_page.c`, `xnu/nmx_mm.cpp` |
| `frame-path/plugin-trace` (off `ci/amd-plugin-890m` 899c64f) | aa72666 | `plugin/NVMTLEventSync.m` |
| this repo, `claude/hungry-mclean-f82082` | | `tools/890m/frame-path-report.py`, `tools/890m/frame-path-capture.sh` |

What each piece records (all `mach_absolute_time` ns, which on x86 equals the plugin's `CLOCK_UPTIME_RAW` ns):
- **Plugin** (WindowServer only, where the fence marks already exist): `NMXFencePendingT` with `NMXFencePending` at
  commit, `NMXFenceDoneT` (completion thread saw the syncobj) and `NMXFenceGpuEndT` (GPU end from the calibrated
  timestamps the plugin already collects) with `NMXFenceDone`. Same number of IOSurface calls as before
  (`IOSurfaceSetValues` with a dictionary instead of `IOSurfaceSetValue`). Optional A/B: the file
  `/Library/GPUBundles/nvmtl-exec-qos-ui` (absent = today's behaviour) creates `nvmtl.execution` at
  `QOS_CLASS_USER_INTERACTIVE`.
- **NMXAccel** `debug.nmxaccel_frametrace` (RD, any user): last 512 transactions: entry, the three plugin stamps read from
  the surface, fence seen, flip submit, latch seen by the poll, `signalTransactionInterrupt`, flip seq.
  `debug.nmxaccel_ft=0` stops the three extra property reads.
- **NMXGPU** `debug.nmx_frametrace` (RD): last 512 flips: `flip_submit` entry, commit returned, `prepare_flip_isr`
  (armed, with the vblank count and `dc->idle_optimizations_allowed`), `dm_pflip_high_irq` (with the vblank count),
  status seen; counts of vblank and pageflip IRQs on the panel CRTC; a 16-bin histogram of where in the real frame the
  IOFramebuffer VBL timer fires (and how often the vblank IRQ was off then); DMUB IPS rcg/ips1/ips2 entry/exit counters.
  The amdgpu hooks only take a timestamp and `drm_crtc_vblank_count`.
- **NMXGPU memory stalls** (468a78d, row 10), in the same sysctl: per kind (`restore` = Step142 re-wire in TTM populate,
  `inline` = 2 MB chunk made on the allocating thread, `fill` = chunk made by the fill thread call, `wire` = new
  userptr/surface wire at import) count, total, max and a histogram (<0.1, <1, <10, <100, <1000, >=1000 ms), plus the
  last 128 stalls >= 1 ms with start time, duration, pages and pid. The report lists, for every late WindowServer frame,
  the stalls that overlap it; a stall with Chrome's pid that overlaps nothing delayed Chrome's own frame (client side).
  Run `vm_stat 1 > vmstat.txt` beside the capture (no root) to see swap-ins per second.

Checks done: the patch series replays on the vendor HEAD with `--fuzz=0` and yields exactly the patched
`amdgpu_dm.c`; `amdgpu_dm.c`, `nmx_fb_bridge.c`, `nmx_fb.cpp`, `nmx_kext.cpp` compile with the tree's own scripts
(`cc.sh`, `cclk.sh`, `ccxx.sh`; `nmx_page.c` with `ccsrc.sh`); new undefined symbols are only internal ones (`nmx_ft_*`, `nmx_dm_ips_counts`,
`drm_crtc_vblank_count`, `nmx_ft_stall`) plus `mach_absolute_time`/`IOMalloc`/`IOFree`/`current_proc`/`proc_pid`,
all already imported by the installed out-29 (`nm -u` = 581), so the 581 rule
should hold (main's `nm -u` check decides). NMXAccel builds with `OGKM=~/ogkm615 NM_TAHOE=1
build/nmxaccel_build.sh kexts/NVRM <out>`; its undefined symbols are identical to the installed NMXAccel (883 = 883,
empty diff). The plugin passes `clang -fsyntax-only` with the tree's flags. Not run on the machine.

How main builds it:
1. NMXGPU: in `~/develop/projects/nmx-build-xkpi/src` (branch `nmx-source-port` @ 4f6825b) `git merge --ff-only
   frame-path/kernel-trace` (or cherry-pick 64c11a5 and 468a78d), then `~/develop/projects/nmx-build-xkpi/build.sh out-30` in the
   background; usual checks (581 undefined, 0 weak, `NMXOwnsDisplay`).
2. NMXAccel from the same commit: `OGKM=~/ogkm615 NM_TAHOE=1 build/nmxaccel_build.sh kexts/NVRM <out>` (or the CI
   workflow `build-nmxaccel.yml`).
3. Plugin from `frame-path/plugin-trace` with the usual `build_plugin.sh` flow.
All three are needed for the full join; NMXGPU alone already gives the scanout side (armed -> pageflip -> seen, VBL
timer phase, IPS).

How to run (no root): after the boot, with the owner's normal load (video playing, Docker up, Claude, the apps that
stutter), `tools/890m/frame-path-capture.sh 300`; the owner notes the clock time of any visible stutter. Then read
`report.txt` (per-stage p50/p90/p99/max, late frames and the stage that took the most time in each, IPS-path flips).
A second run with `touch /Library/GPUBundles/nvmtl-exec-qos-ui` (root; main gives the owner the command) and a
WindowServer restart (log out/in) is the A/B for row 1.

## 8. The short answer

**Three most likely root causes of stutter under multitasking** (updated 2026-11-18 with video-suite's evidence):

1. **Memory work done synchronously on the submitting thread** (row 10, the long gaps). Every IOSurface is pageable user
   memory wired as a userptr BO; Step142 unwires idle ones, and the next CS re-wires them with `prepare()` inside
   `ttm_bo_validate` while holding the VM and BO locks. New imports wire the same way, and an empty pool makes a 2 MB
   wired chunk inline. Under pressure each of these can wait for swap-in or free pages: 400 ms to 4 s holes, which is
   what video-suite saw (every drop second under pressure had swap-ins). Linux faults userptr pages before taking any
   lock, and its compositor surfaces are not user memory at all. The pressure itself comes mostly from RyzenHV wiring
   12.3 GB of guest RAM (section 3.1).
2. **"GPU work done" travels through user space at default priority** (row 1, ms-level jitter that grows with CPU
   load). The plugin's `nvmtl.execution` queue (31T) waits the syncobj and writes an IOSurface property that the
   display pipe polls every 100 µs; 88 % of frames wait on it. Every kernel-side stage of our path already outranks all
   user threads, so this hop, plus Chrome's software H.264 decode (row 11) adding cores of load, is where CPU contention
   reaches the frame path. Linux waits on the same fence in the kernel commit worker.
3. **WindowServer's vblank and "frame shown" time are not the hardware's** (rows 2 and 3, pacing). One `'vbl '` slot fed
   by a free-running timer whose phase vs. scan-out is arbitrary, and presentation timestamps (tx+0x170) left 0 so the
   family stamps the poll's time. Frames are scheduled against an imaginary vblank.

**The single experiment that separates them:** one boot with the trace build (section 7: kernel-trace 64c11a5 +
468a78d, plugin-trace aa72666), under the owner's normal load (video, Docker, Claude, the apps that stutter):
`tools/890m/frame-path-capture.sh 300` with `vm_stat 1` beside it. For each late frame the report names the stage that
took the time and any memory stall that overlaps it:
- a `restore`/`inline`/`wire` stall overlapping the late frame (or a long stall with Chrome's pid just before a run of
  late frames) -> cause 1;
- no stall, `wake`/`handoff` large -> cause 2 (confirm with the `nvmtl-exec-qos-ui` A/B in the same boot);
- no stall, small `gpu`/`wake`, `scanout` with `missed` > 0 and a VBL-timer phase spread -> cause 3;
- no stall, long kernel-only stages (`worker`, `notify`) while Docker is busy -> the RyzenHV question in 3.1.

## 9. out-31: structural fixes for rows 1-3 (2026-11-18, compile-checked only)

Branches on `fork` (one out-31 build): kernel + NMXAccel `fix/out31` (on top of `fix/cs-enomem` ff060ea, which sits on the
trace `8d1a8c2`); plugin `fix/out31-plugin` (on `fix/cs-enomem-plugin` 97725ba, on `integ/out30-plugin`). Commits:
`6430f73` rows 1+3 (shared flip ABI v2), `720f6c9` + `4caa56d` row 2, `e555852` trace flags + GTT, plugin `a46e451`.
Every change has its new behaviour on by default and a runtime switch back to the old path; boot-args
`nmxkfence=0` / `nmxflipirq=0` / `nmxvblirq=0` (grep-audited against every kext under /Library/Extensions and
/System/Library/Extensions and our sources: no other user; kexts OpenCore injects from the ESP were not checked).
Compile checks: NMXGPU bridge, nmx_fb, nmx_kext, nmx_mm, nmx_page and the patched `amdgpu_cs.c`, `amdgpu_ttm.c`,
`amdgpu_dm.c` with the xkpi scripts; NMXAccel built and linked with `build/nmxaccel_build.sh` (ogkm615, NM_TAHOE=1);
both new vendor patches apply (`patch --dry-run`) on the out-30 tree; the plugin adds no syntax error (22 before, 22 after).

### 9.1 Row 1: the render fence travels in the kernel

| | |
|---|---|
| Linux | `amdgpu_cs_submit` adds the job fence to the BOs' `dma_resv`; the KMS client's commit takes the plane fence (`drm_gem_plane_helper_prepare_fb` / `drm_atomic_set_fence_for_plane`) and `commit_tail` -> `drm_atomic_helper_wait_for_fences` waits before the flip is programmed |
| here | `amdgpu-nmx-surface-fence.patch`: after `p->fence` exists, every userptr BO of the job that was wired from an IOSurface (`UserWire.sid` via `surf_wire`) records the fence under that IOSurface ID (`nmx_surf_fence_set`, 64 entries, LRU, record time). `flip_submit` v2 with `NMX_FLIP_SUBMIT_FENCE_ONLY` sets `plane_state->fence` (this drm-kmod has no `drm_atomic_set_fence_for_plane`; its `prepare_fb` keeps a fence already set) and the helper commit's `commit_tail` waits, on the commit worker, not on the pipe thread. NMXAccel no longer sleeps in `nmxFenceWait` for those frames |
| ordering gap found | NVMTL marks a command buffer "scheduled" **before** its CS ioctl and a later part may write the surface, so at the transaction the kernel can still hold the previous frame's job. Linux never has this (the compositor's `vkQueueSubmit` returned before it asks for the flip). So: the plugin writes `NMXFenceSubmitted = n` after the last surface-writing part passed `vkQueueSubmit` (RADV on amdgpu: native timelines, immediate submit, the CS ioctl is inside); NMXAccel uses the kernel fence only when `NMXFenceSubmitted >= NMXFencePending`, and passes `NMXFencePendingT` as `fenceAfterNs` so NMXGPU refuses a fence recorded before the frame's commit. Otherwise, or when refused, the old `NMXFenceDone` wait. Alternative (bigger plugin change, no IOSurface properties at all): give `waitUntilScheduled` its Metal meaning in WindowServer (scheduled = every surface-writing part passed the CS ioctl); asked main |
| xnu risks | (1) the recorded fence is the surface's **last** job, read or write: a later read job only delays the flip, never shows an unfinished frame. (2) a surface wired through the plain path (no sid) has no fence: counted (`nmx_flip_nofence`, `nmxaccel_kfence_refused`), old wait. (3) a GPU hang now blocks the commit worker in `dma_fence_wait` instead of the pipe thread (Linux identical; `amdgpu_fence_driver_force_completion` on reset signals it); the 50 ms latch cap in NMXAccel still trips flips off. (4) CPU paths (K6 copy, copy home, VRAM chain mode 2) always wait the old way first. (5) 64 entries: WindowServer's surfaces are few; an aged-out entry = old wait |
| verify | `debug.nmx_flip_fenced` and `debug.nmxaccel_kfence_flips` grow with flips; `nmxaccel_kfence_not_submitted` / `_refused` small; `debug.nmxaccel_frametrace` waited = 2 on those frames; aggregate: `wake`/`handoff` disappear for them, the GPU wait shows in `worker` (sub0 -> armed); total p99 and "handoff > 4 ms" (138 in the first run) must drop; no torn or stale frames on screen; A/B with `sysctl debug.nmxaccel_flip_kfence=0` |

### 9.2 Row 3: flip completion from the pageflip IRQ, real presentation time

| | |
|---|---|
| Linux | `dm_pflip_high_irq` sends the DRM event with the flip's vblank time; the compositor wakes on it |
| here | `amdgpu-dm-nmx-flipdone.patch`: after the event went out, `nmx_fb_flip_done` calls NMXAccel's registered callback (`nmxFlipNotify`, ABI v2), which only `thread_call_enter`s the completion. `nmxFlipPoll` in notify mode looks once (no 200 us spin, no CPU burn), re-arms 2 ms if the latch is not visible yet (VRR front porch sends the event from the next vblank), 50 ms cap unchanged; the first check is a 4 ms safety net the IRQ moves up. Status v2 returns `latchNs` (pageflip IRQ `mach_absolute_time`); NMXAccel writes it to `tx+0x170` before `signalTransactionInterrupt`, where `completeTransaction` would stamp its own (later) completion time: only if `tx+0x158 != 0`, `tx+0x170 == 0`, `pipe+0x248 == tx`, `version_major == 25` |
| xnu risks | the callback runs on NMXGPU's IH thread: it must never block (it doesn't); a notify and the fallback can both run: one `claimed` CAS completes, `busy` is cleared after `result` as before; NMXAccel must not unload while registered (it never does); `tx` layout read on 25G332 only, gated to Darwin 25 and to the pipe's current transaction; `debug.nmxaccel_flip_ts=0` turns it off |
| verify | `debug.nmx_flip_notified` ~= flips, `debug.nmxaccel_flip_notified` same, `nmxaccel_flip_rearm` small; aggregate `notify` (pflip -> latch seen) p50 well under 1 ms (was the 200 us poll plus thread-call wake); `nmxaccel_flip_ts_set` grows; WindowServer CPU time in the pipe thread drops (spindump of WindowServer, root, main runs it); A/B `debug.nmxaccel_flip_notify=0` |

### 9.3 Row 2: IOFramebuffer VBL from the CRTC vblank

| | |
|---|---|
| Linux | a vblank consumer holds `drm_crtc_vblank_get` while it wants vblanks; `drm_crtc_handle_vblank` runs from `dm_crtc_high_irq`; `drm_crtc_vblank_put` lets the IRQ go and idle optimisations return (`amdgpu_dm_crtc_vblank_control_worker`, `active_vblank_irq_count`) |
| here | NMXAMDFB keeps up to 4 `'vbl '` registrations and honours `setInterruptState` / `unregisterInterrupt` (were no-ops, so IOFramebuffer's `deferredVBLDisable` did nothing and the 120 Hz timer ran forever). While any registration is on, a thread call takes the DRM vblank reference (`nmx_fb_vbl_ref`); `dm_crtc_high_irq` -> `nmx_ft_vblank` -> sink -> thread call runs the procs. The timer delivers only as fallback (no reference: CRTC off, retried ~1/s; or no CRTC vblank for > 2 frames), otherwise checks every 100 ms, and stops when nothing is on |
| xnu risks | IOFramebuffer's VBL handler now runs from a thread call kicked by the IH thread instead of the timer thread call (same context type); if a client never turns its registration off, the vblank IRQ stays on (Linux same; no worse than the timer); a 5th registration gets `kIOReturnNoResources` (seen: 2); DPMS off with the reference held: vblank IRQ stops, the watchdog switches to the timer, `drm_crtc_vblank_on` re-enables the IRQ because the reference is still held |
| verify | `debug.nmx_vbl_delivered` ~ refresh rate while the pipe has VBL on, 0 when idle; trace head: `vbl_timer fires` stops growing (only the 10 Hz watchdog) and the phase histogram is no longer spread; `psr ... active_vblank_irq_count` 1 while on, 0 when idle, and `ips` counters / `idle_allowed` should now move when the screen is static; NMXAMDFB log "vblank ref held/dropped"; A/B `debug.nmx_vbl_irq=0` |

### 9.4 Trace review notes, flags, GTT accounting

- Review notes (in `8d1a8c2`): `ft_submit_end` before `spin_unlock(&flip.lock)`; `nmx_ft_armed` ignores commits that are
  not the bridge's (`crtc->state->commit != r->commit`); wire vs surf counted apart (no double count); `debug.nmx_ft=0`
  and `debug.nmxaccel_ft=0` turn every hook off.
- New trace lines: `psr feature_enabled allow_active version replay active_vblank_irq_count` (the inputs of
  `dcn35_apply_idle_power_optimizations`) and `out31 ...` (switches + counters). The report and aggregate tools print
  both; `frame-path-capture.sh` also saves `debug.nmx_gtt` per snapshot.
- `debug.nmx_gtt`: GTT and VRAM managers' used/size, then per open DRM file pid, process, resident system/GTT/VRAM,
  evicted, GEM handles (`amdgpu_vm_get_memory`, the fdinfo source). The next CS -ENOMEM: GTT near size = TTM placement
  (`ttm_bo.c` turns -ENOSPC into -ENOMEM); room left = page allocation (`debug.nmx_page_alloc_fails`).

### 9.5 The page pool: memory-pressure release instead of timers (proposal, not written)

`debug.nmx_pages_live` went 1.11 M -> 660 k by 11:10, so it shrinks on the Step141 timers: timer-driven release, not a
leak. Linux releases on pressure: the TTM pool shrinker (`ttm_pool_shrinker_scan`) and `ttm_global_swapout` run when
the MM asks. xnu gives a third-party kext no shrinker callback (`vm_lowmem`/zone GC hooks are not KPI). The contained
equivalent: the pool's existing timer reads `kern.memorystatus_vm_pressure_level` (1 normal, 2 warn, 4 critical) and
on warn frees every free chunk at once and parks idle userptr BOs after 5 s instead of 60 s; on normal it keeps the
pool (no periodic release while memory is plentiful, so no re-fill bursts during video). Not written: it needs
`sysctlbyname`, a new kernel import for NMXGPU (the import rule that made the trace use `current_proc`/`proc_pid`), and
it still polls. The real equivalent (a pressure notification) would be a kernel-side `EVFILT_MEMORYSTATUS`-like hook
that xnu does not export to kexts. Decision for main: accept the new import, or keep the timers.

### 9.6 Review round 1 (`478a117` on `fix/out31`)

All eight review items are fixed in `478a117`; none was rejected. Changes against 9.1-9.3:
- **Fence choice (row 1):** fences are recorded only for surfaces NMXAccel imported for scan-out, keeping the latest
  fence per context, and a fence-only submit never commits unfenced.
- **Fenced flips (rows 1/3):** a fenced flip has a 150 ms cap and resyncs instead of tripping; `kIOReturnBusy` drops
  the frame.
- **Flip completion (row 3):** completion is claimed per seq.
- **VBL (row 2):** the reference thread call is serialised, and the watchdog re-arms itself and has a 50 ms floor.

**GPU reset:** the source path is Linux's, with `amdgpu_gpu_recovery` -1 (auto). A job timeout leads to
`amdgpu_job_timedout`, then a ring reset or a full recover, both calling `amdgpu_fence_driver_force_completion`. That
signals the hardware fences, so the scheduler fence the commit worker waits on ends at the lockup timeout. Not verified
on this port: MODE2 resets have taken the machine down before (the 17:33 hard reset), so a real hang is more likely to
end the session than to leave the worker waiting.
What the CS cannot tell: whether a job writes a BO it lists, so a reader's job also counts (it can only delay a flip).

### 9.7 Review round 2 (`2b25e54` on `fix/out31`) and the post-install check

Round 2 of the review of `478a117` found seven issues (N1-N7). All are fixed in `2b25e54`, compile-checked only; they are not in out-32.

**N1 / N2 / N5: fenced flip past the 150 ms cap (NMXAccel)**
- Such a flip is no longer assumed to be on screen. It is now "stuck".
- Kept from import LRU eviction and `nmxFlipDropIdle`: its import, plus the last frame dropped as BUSY behind it (the "redo" frame).
- `nmxFlipWatch` is a thread call that runs every 4 ms. Once the bridge reports nothing pending, or a new generation:
  - it takes `front` from the bridge's current handle;
  - it resubmits the redo frame, either fence-only or after `nmxFenceWait`, so a static screen gets its last frame.
- After 2 s stuck it trips flips off (N2) and keeps watching every 100 ms.
- Any accepted submit clears the stuck and redo state, because a newer frame wins.
- The "same surface" shortcut is skipped while a flip is stuck.
- New counters: `debug.nmxaccel_flip_stuck_landed` and `debug.nmxaccel_flip_redo`.
- Residual: the step-1 drop ("previous flip still pending after 20 ms") has no redo yet. It can only happen inside the 150 ms cap, while the poll is still running.

**N3: fence lookup around a re-import (bridge)**
- Each import stores `import_ns`.
- A fence lookup for a frame committed before its surface's latest import is refused, and the frame takes the old wait.

**N4: sticky `overflow` (bridge)**
- Contexts 5 to 8 with unsignaled fences go to an overflow list, which is waited for like the others.
- Only a 9th context sets the sticky refusal. Its fence had to be dropped, so its end cannot be known.

**N6 (NMXAMDFB):** `unregisterInterrupt` stores `proc` and `fVblLast`, and reads `fDelivering`, all SEQ_CST.

**N7 (NMXAccel):** a caps call answered `kIOReturnNotReady` (it lost the init race) leaves caps unknown (-1). The next frame asks again.

**Doc correction to 9.3:** NMXAMDFB has no "vblank ref held/dropped" log line. The held state is `vbl_held` in the trace's `out31` line.

**Post-install check:** `tools/890m/out31-verify.sh [seconds=30] [dir]`
- Read-only and needs no root. Run it under the normal load with a video playing.
- It samples every out-31 counter at the start and end of the interval, snapshots both rings and runs the aggregate.
- It prints PASS / FAIL / INFO for each 9.1-9.3 verify item, then the runtime A/B `sysctl` commands for main.
- Two items cannot be scripted:
  - the WindowServer pipe-thread CPU, which needs a root spindump (command printed);
  - the on-screen check, which the owner does.

## 10. Row 12: gfx page faults in the VideoToolbox decoder (2026-11-18, read-only analysis, no code)

The codec session reported this finding. The details are in `docs/VIDEO-CODEC-MATRIX.md` on `claude/video-suite-27beee`
(`c7a37bf`).

### 10.1 What the fault says

This boot's kernel log has 23 faults between 11:27 and 12:44. All have the same signature: `[gfxhub] page fault ring:40`,
client TCP, `GCVM_L2_PROTECTION_FAULT_STATUS` 0x00241051 / 0x00341051.

Decoded:
- `MORE_FAULTS` 1;
- `PERMISSION_FAULTS` 0x5 (PTE not valid + write);
- `MAPPING_ERROR` 0: the page directory walk reached a PTE, so the VA lies inside page tables that exist;
- `RW` 1.

A write to a read-only (romap) PTE would show 0x4 instead, and NMX's romap lookup agrees: no romap entry covers these VAs.

So a shader in the decoder's VM wrote a page whose PTE has V = 0. VCNDec's image-to-buffer copy writes into a host import
of the output IOSurface (`vcndec.c` `surface_buffer()`, RADV `radv_amdgpu_winsys_bo_from_ptr`), which makes it the obvious
writer.

Timing:
- Each fault is followed by a 3 s soft recovery (`amdgpu-gfx-timeout-3s.patch`), then VCNDec's "copy fence" -12911.
- Pairs 3 s apart hit the same or the adjacent page (12:20:36/39, 12:43:26/29, 12:44:12/15). The PTE stays invalid
  across the next submit as well.

Intervals in pasid 32816, 12:23-12:37: 180, 163, 164, 163 and 162 s.

### 10.2 What writes V = 0 PTEs, and what Linux does

`amdgpu_vm_bo_update` writes `amdgpu_ttm_tt_pte_flags(..., mem)`, which sets `AMDGPU_PTE_VALID` only when the BO is not in
`TTM_PL_SYSTEM`. A freed mapping is cleared by `amdgpu_vm_clear_freed`, which writes V = 0 too.

Linux stays safe through one rule: every BO a job touches is either VM-always-valid or listed in the job's BO list.

For a listed BO, the CS:
- locks it, validates SYSTEM -> GTT (for a userptr, after re-getting the pages with `amdgpu_ttm_tt_get_user_pages`);
- updates its mapping with `flush_tlb` (`moved`);
- makes the job wait for `last_pt_update` (`amdgpu_cs_vm_handling`).

A userptr invalidation waits for the BO's fences (`amdgpu_hmm_invalidate_gfx`) before the pages may go.

### 10.3 Our port against that

**Step142 park** (`amdgpu-userptr-park.patch`, `nmx_userptr_park_ms` = 60000):
- The sweep takes an IOSurface userptr BO that no CS has listed for 60 s, under a trylock of its reservation and only when
  `dma_resv_test_signaled(BOOKKEEP)` holds.
- It moves the BO to SYSTEM (`move_notify` -> `moved`) and unpopulates it.
- The VM's next CS writes V = 0 for that BO. `amdgpu_vm_handle_moved` does this even when the BO is not in that CS's list.
- A later CS that lists the BO re-validates it: `nmx_upin_restore` in populate, bind, then `amdgpu_vm_bo_update` with
  `flush_tlb` and a sync to `last_pt_update`.
- That is Linux's flow, with the IOSurface descriptor in place of HMM, and it held in review: the touch at `amdgpu_cs.c`
  974 runs under the CS's reservations, and `debug.nmx_upin_restore_fail` / `unpark_fail` are 0.

The decoder parks heavily: `debug.nmx_userwire_by_kind` reports **VTDecoderXPCService 251 522 parked pages** (about 980 MB)
and 254 679 wired pages that the decoder imported but that are classed as "plain" (not an IOSurface's own memory, so never
parked).

**RADV** (radv-video tree):
- Host imports are not on the global BO list (`use_global_list = false`). They are listed only through
  `radv_cs_add_buffer`, which `CmdCopyImageToBuffer` calls for the destination (`radv_meta_copy.c:561`).
- VCNDec rebuilds the command buffer for every frame and waits for each copy, so the destination is listed in every copy
  submit, at least in this tree.
- It is not yet checked that the RADV loaded in VTDecoderXPCService is this tree (NVMTL's bundle may differ).

**Timers:**
- The period (about 163 s) is not a multiple of any timer: park 60 s with a 1 s sweep, pool 60 s / 10 min, surface-keep
  in WindowServer only.
- A park-caused fault would happen on the first reuse after at least 60 s idle, so its period would follow the player's
  surface reuse, not a timer.
- So the timing neither proves nor rules out park.

Ranking, as stated to main:

| cause | confidence | why |
|---|---|---|
| a parked (SYSTEM, V = 0) IOSurface BO written by a job that did not re-validate it | about 50 % | the PTE state matches exactly; the decoder is a heavy parker; out-29 also had park 60 s, but these tests did not run there |
| a freed mapping: VCNDec drops an import (LRU of 8, or session close) and frees it, or a RADV VA is reused | about 30 % | same PTE state; a synchronous fence wait per copy makes a plain use-after-free unlikely |
| TTM eviction of the userptr BO to SYSTEM under GTT pressure (the CS -ENOMEM context) | about 20 % | same PTE state and the same re-validation contract as park |

All three need one thing to have gone wrong: the BO was not re-validated by the CS that ran the faulting job. So the decisive
data is which BO the fault address belongs to, and its state at that moment.

**What decides it (no code from me yet; main's call):**
1. A/B with park off, under the same Safari/QuickTime AV1 playback for at least 10 minutes (about 4 periods):
   `sudo sysctl debug.nmx_userptr_park_ms=0` (restore: `=60000`). Faults stop -> park; they continue -> 2 or 3.
2. Fault-time lookup, an addition to `amdgpu-romap-gmc11.patch` that only reads. With `amdgpu_vm_get_vm_from_pasid` and a
   trylock of the root reservation, `amdgpu_vm_bo_lookup_mapping(vm, addr >> 12)` prints:
   - the mapping's start and last;
   - BO size, userptr flag and sid;
   - `resource->mem_type`;
   - `nmx_norec` (parked) and the age of `nmx_used`;
   - `bo_va->base.moved` and `cleared`;
   - or "no mapping" (freed).

   One fault then names the cause.

### 10.4 The fix, per cause (to be written after 10.3)

- **Park:** do what Linux does on an invalidation, but also cover jobs that touch the BO without listing it, which
  WindowServer's NVMTL paths may do as well. Leave the PTEs valid for a parked BO until the next CS lists it, i.e. park only
  unwires the pages when no VM can still reach them. Concretely:
  - park only BOs whose mapping was already rewritten, or make the park itself rewrite the mapping (V = 0) with a TLB
    flush and then refuse a CS that does not list the BO;
  - simpler and safer: `nmx_park_one` skips BOs that still have a `bo_va` mapped in any VM, i.e. park only after
    userspace unmapped the BO. That gives back less memory.

  The choice depends on what 10.3 (2) shows is writing without a list.
- **Freed mapping:** an application or RADV bug. Fix in VCNDec (keep the import until the last copy that used it has
  signalled; it is synchronous today, so look at session teardown and the LRU drop in `vcn_close`) or in RADV's
  `bo_from_ptr` VA handling.
- **Eviction:** same contract as park, re-validated by listing. Same check: which unlisted use.

### 10.5 Second reproducer: mediaanalysisd (2026-11-18, out-30 kernel, new RADV/plugin)

**15:31:04 / 07: two faults in pasid 32830, then the crash**
- Same signature as before: TCP write, V = 0, at 0x80010f202000 and 0x80010f206000.
- The kernel now prints `in process pid 965791`. That number is a thread id, 0xEBC9F, and it is mediaanalysisd's thread
  `[31696:ebc9f]`, the thread that created the VM.
- The faulting job is therefore **mediaanalysisd's own**.
- 2.5 s before the fault, NVMTL logged `storage twin: 800x1376 VkFormat 98 (IOSurface) is written through an
  optimal-tiled storage copy`.
- The 3 s soft recovery comes next. NVMTL then logs `vk: queue submit -> -4` (device lost), "disabling backend", and
  `newCommandQueue: Vulkan/NVK is down`.
- MPS then fails in `MPSImageUnaryKernel.mm:334` and asserts (`MTLReportFailure`), and the daemon aborts. **The crash
  is a consequence of the fault, not its cause.**

**The earlier faults were likely mediaanalysisd too**
- mediaanalysisd crash reports exist for 12:10:28, 12:19:17, 12:40:47, 12:43:45 and 12:44:20, each 17-20 s after a
  fault at 12:10:10, 12:19:00, 12:40:31, 12:43:26 and 12:44:12.
- So at least those "VideoToolbox decoder" faults (10.1) were most likely mediaanalysisd's.
- VCNDec's "copy fence" error 2 s later fits collateral damage: the gfx ring hangs until the soft recovery, and every
  job queued behind it fails or times out.
- The pasid -> process attribution in VIDEO-CODEC-MATRIX should be re-checked. Only builds that print `in process`
  name the VM's creator thread.

**Park is now unlikely**
- At 12:49, `debug.nmx_userwire_by_kind` showed mediaanalysisd with 688 446 IOSurface pages wired and **0 parked**.
- On out-33 at 16:04, VTDecoderXPCService had 16 201 parked pages and mediaanalysisd no userwire row at all.
- Revised ranking:

| cause | confidence |
|---|---|
| a user-space use-after-free of an IOSurface import in NVMTL: a buffer freed (GEM close -> `amdgpu_vm_clear_freed` writes V = 0 at the next CS) while a command buffer recorded with its VA is still submitted afterwards | about 60 % |
| the NVMTL storage-twin / heap-alias paths, i.e. the same kind of fault in a different object | |
| park | about 15 % |
| eviction | about 10 % |

- NVMTL's surface keep drops entries "released off the main thread" (25 in the 15:30:59 stats line), and `heap alias:
  an automatic private heap ... got no memory of its own` appears right after the fault.
- Linux would fault identically on such a job. This is not a kernel divergence; the fix belongs in the plugin, once the
  BO is named.

**Deciding instrumentation (kernel, read-only, for main to approve)**
1. A per-VM ring of the last 64 unmapped VA ranges: start, last, BO size, sid, unmap time, written in
   `amdgpu_vm_bo_unmap` / `amdgpu_vm_bo_del`.
2. The fault handler prints the hit, e.g. "freed 12 ms ago, surface 0x...", or the live mapping's BO state (10.3 (2)).

One fault then names the object, and the plugin fix follows.

**No out-33 faults yet:** none between boot (15:54) and 16:04.

**Deliberate reproducer:** `tools/890m/vision-fault-repro.swift`
- It runs Vision text recognition and classification on a fresh IOSurface-backed CVPixelBuffer per request, 4
  concurrently: the daemon's Espresso -> MPSImage path.
- It builds, but it has **not been run**: every fault costs a 3 s ring stall, and repeated faults preceded the 15:52
  freeze. Run it only with the owner's OK and with a time bound (command in the file header).

## 11. Row 13: GPU memory that is never given back (2026-11-18, read-only analysis, no code)

**Main's premise was wrong.** "pid 981 = WardaSynthesizer holds 2.6 GB of GTT" is a misattribution.

`debug.nmx_gtt` prints `task_info->tgid`. On this port that value is a **thread id**:
- `linux_current.c:97-99` sets `ts->pid = td->td_tid` and `ts->group_leader = ts`;
- `amdgpu_vm_set_task_info` copies `current->group_leader->pid` into it.

It is also the last thread that submitted on that VM. This is the same thread-id finding as 10.5. The process name column is empty for the same reason: it comes from `td_name`.

Mapped through `log show --predicate 'threadIdentifier == N'`:

| "pid" | thread | process | GTT resident (16:10) |
|---|---|---|---|
| 981 | 0x3d5 | **WindowServer[210]** | 3.23 GB, 1335 BOs |
| 9687 | 0x25d7 | Cloudflare WARP[1151] | 252 MB |
| 5770 | 0x168a | Claude Helper[779] | 250 MB |
| 56063 | 0xdaff | SimMetalHost[1072] | 176 MB |
| 7187 | 0x1c13 | Edge Helper (Aperitif)[910] | 135 MB |
| 41293 / 93395 | 0xa14d / 0x16cd3 | VTDecoderXPCService[7309] / [37997] | 105 / 150 MB |
| 54532 | 0xd504 | SimRenderServer[995] | 55 MB |

WardaSynthesizer (pid 981) has used 0.09 s of CPU since 15:55 and has no Metal log line. Its BO count could not move, yet the "981" row went 1124 -> 1158 -> 1350 -> 1335 between reads.

**Fix for the counter.** In `nmx_gtt_format`, print the process: `proc_pid(td_proc)` of the record's thread, or record the pid at `amdgpu_vm_init`. Do not change `amdgpu_vm_set_task_info`, because the fault printer shares it.

### 11.1 What WindowServer's 3.2 GB is

Read-only counters at 16:10:
- `debug.nmx_pin_by_proc`: `WindowServer surf 439073 plain 701 parked 0` pages. That is **1.67 GB of IOSurface pages wired, none parked.**
- Other processes park: Claude Helper 40k pages parked, Edge Helper 31k, VTDecoder 16k.
- System-wide `nmx_userwire_by_kind`: surface 734 records / 482k pages wired, of which **527 records / 354k pages are older than 60 s** and still wired.
- `debug.nmx_park_skip_busy 0`, `nmx_park_fail 0`. The sweep never reaches these BOs: they never look idle.

The remaining ~1.5 GB is WindowServer's own BOs. WindowServer's `/tmp/nvmtl.log` gives a partial split:
- plugin allocations live: 817 MB, then 1.43 GB (buffer census, which counts host imports too);
- images 107-134 MB;
- one MTLHeap of 2 MB.

Two copies that double memory, both by design:
- **buffer-texture shadows** ("shadowed at pitch 256", logged 12288 times; 30 GB of shadow uploads in 20480 submits);
- **multi-plane surfaces copied into a private image** ("item 7", 3840x2160 two-plane surfaces copied in and out).

Managed buffers are one CPU-visible allocation on the 890M (`NVMTL_MANAGED_SYSMEM` default), so they are **not** doubled.

### 11.2 Why WindowServer's imports never park (plugin cause, read in the source)

The plugin has a surface list (`nvmtl_vk.c:1508`):
1. An IOSurface import leaves RADV's global list.
2. A command buffer that names its own surfaces is marked exact (`radv_nvmtl_cmd_exact`).
3. A submit that contains any command buffer that is not exact carries the whole list (`radv_amdgpu_nvmtl_needs_surfaces`).

The kernel then calls `amdgpu_ttm_tt_nmx_touch` on every BO in the list (`amdgpu_cs.c`, Step142). Linux semantics are right here: a listed BO is a used BO.

`nvmtl_vk_image_write`, the "surface upload" submit (`nvmtl_vk.c:6830`), never calls `nvmtl_vk_cmd_exact`. Only the prologue and counter-reset command buffers do (`:6268`, `:6276`).

In WindowServer's log:
- submits 28672 -> 32768: 2048 of 4096 carried the whole surface list;
- the census over the same window: `surface upload` 1480 -> 3528, plus 131 `image_write_region`.

So every video frame that WindowServer uploads touches every one of its 174-518 imports. No import is ever idle for `nmx_userptr_park_ms` (60 s), and the park sweep never sees a candidate. This also costs CS time: about 1.4 µs per handle (row 10).

### 11.3 What a real driver does, and the correct design here

**Apple** (AGX, and the AMD/Intel Mac drivers):
- A resource is wired while a command buffer that lists it is in flight (the residency set or `useResource` list). Otherwise it is ordinary pageable or compressible VM memory, and IOSurface memory is pageable when no one is using it.
- `setPurgeableState:Volatile` lets the VM discard the pages under pressure. `Empty` discards them now.
- Nothing stays wired for a process's whole life just because it allocated it.

**Linux amdgpu:**
- GTT BOs are TTM `ttm_tt` pages on an LRU.
- Under pressure, `ttm_bo_swapout` (through `ttm_global_swapout` or the shrinker) copies idle, unpinned, unbusy BOs into a shmem file and unpopulates them. The next validate swaps them in (`ttm_tt_swapin`).
- Userptr pages are never pinned. HMM and the MMU notifier re-fetch them before use.
- amdgpu exposes no purgeable state for GEM BOs. Mesa frees memory on the user side.

**This port:**
- Every native BO's pages are wired from populate until destroy. `nmx_pages_live` was 1.09M pages (4.15 GB).
- `ttm_pages_limit` is half of RAM (16 GB), so `ttm_global_swapout` in `ttm_tt_populate` never runs.
- xnu never fires `vm_lowmem`, so the shrinker never runs either (Step141 note in `ttm_device.c`).
- Whether xkpi's `shmem_file_setup` gives pageable storage has not been checked.

**Correct design**, in the order Linux has it. The last two items are the real fix:
1. **Plugin: exact lists everywhere** (11.4 a). Then Step142 parks WindowServer's idle imports. This is the existing design working as intended, not a new mechanism.
2. **Plugin: honour purgeable state** (11.4 b).
3. **NMXGPU: swap out idle native GTT BOs.**
   - Back `ttm_tt_swapout` / `ttm_tt_swapin` with pageable xnu memory: an anonymous `IOBufferMemoryDescriptor` that is never wired, or a VM object. This is the shmem equivalent.
   - Drive it from a pressure signal xnu does give: the `kern.memorystatus_vm_pressure_level` notification, or the same 1 s sweep Step142 uses with an idle age.
   - Do not wait for the 16 GB `ttm_pages_limit`.
   - Candidates are BOs that are on the LRU, idle for N s, not pinned, not exported and with a signalled resv. The next CS validates them back in. That is TTM's own path, so the VM update and GART rebind are upstream code.
   - This is the general form of what Step142 does for IOSurface imports.
4. **NMXGPU: make Volatile/Empty reachable from user space.**
   - Add an NMX GEM op, e.g. a `DRM_AMDGPU_GEM_OP` extension: `MADVISE DONTNEED` / `WILLNEED`, like i915/msm/panfrost `madvise`.
   - For a DONTNEED BO the shrinker path **purges**: it drops the pages without copying them.
   - WILLNEED returns "retained" or "purged", which is exactly what `setPurgeableState:` returns.

### 11.4 The short path that is still correct

These are plugin-only changes, with no NMXGPU build.

**(a) Mark every internal one-shot command buffer exact, with `g_sl_use` for any import it touches.**
- Covers `nvmtl_vk_image_write` ("surface upload"), `image_write_region_level_layer`, `nvmtl_vk_copy_buffer`, and any other `nvmtl_vk_submit_wait_at` caller.
- These command buffers name only their staging buffer and a private image. A destination that lies on an IOSurface's own pages needs `g_sl_use(cb, mem)` first.
- Risk: an import that is used but not listed means a V=0 PTE GPU fault (the row 12 class). So add a debug-build check that every import in a command buffer's resource set was `g_sl_use`d.
- Expected effect: WindowServer's 354k "old60" pages park within about 60 s of idle (about 1.4 GB pageable), and the CS handle count drops.

**(b) Honour `setPurgeableState:` on buffers and heaps.**
- Today `NVMTLBuffer` records the state (`NVMTLObjects.m:857`) and returns NonVolatile for heap, sub-heap and host-pointer buffers.
- `NVMTLHeap` only records the state (`:3675`).
- The res1 reclaimer handles **textures only, and only for VRAM pressure**: it moves them to system memory, which is still GTT and still wired.
- For buffers, the correct short version is:
  - on `Empty`, or on `Volatile` when the process's GTT use is high, free the `VkDeviceMemory` now. Keep the `VkBuffer` and its GPU VA reserved;
  - on `NonVolatile`, allocate and bind again. Return `Empty` so the client knows the contents are gone;
  - heaps are handled the same way, as a whole.
- Metal allows this: Volatile contents may vanish at any time, and a client must set NonVolatile before use.
- Without the NMXGPU madvise (11.3 item 4), "Volatile" can only be implemented as "purge when the process is over a budget". That is a policy, but every byte it frees is genuinely freed, not hidden.
- What is not proven: whether the ML daemons (mediaanalysisd, Espresso/MPS) mark their weight buffers Volatile at all. `nvmtl_purge_report` already counts that, but it only runs at a spill. A per-process `asks ever` line would answer it.

**Should these daemons be on the 890M?** Yes. They are Metal clients on the only Metal device, as they would be on any Intel Mac with an AMD GPU. Moving them off is not a fix, and the owner does not accept that.
- WindowServer is not optional, and the memory it holds is the problem in this row.
- The ML daemons (mediaanalysisd, row 12) are the same class of client and also benefit from 11.3.
- Freeing the memory is the contract; the device the daemon runs on is not the problem.

### 11.5 To confirm (read-only, no root)

- After (a) is installed: `debug.nmx_pin_by_proc` shows WindowServer `parked` above 0 within a few minutes of a static desktop, and `nmx_userwire_by_kind` old60 pages fall.
- Native vs imported per process: extend `nmx_gtt` with a userptr-bytes column (sum of `ttm->num_pages` for BOs with `gtt->userptr`) and the real pid. Both are read-only additions.

### 11.6 The other ~1.5 GB: shadow copies and private copies (analysis and proposal; no code)

Both are **caches**. Their source of truth is an MTLBuffer or an IOSurface, which the client keeps. A cache can be dropped when idle and rebuilt on next use, and that is the correct design. Today both live as long as their texture.

**Buffer-texture shadows.**
- Created by `newTextureWithDescriptor:offset:bytesPerRow:` on an MTLBuffer whose bytesPerRow is not 256-aligned, e.g. "46x44 pitch 192 shadowed at pitch 256", logged 12288 times in WindowServer.
- AMD linear images need a 256 B pitch, so the plugin keeps a second image and copies the buffer's rows into it before every submit that uses it.
- WindowServer copied 30 GB of shadow uploads in 20480 submits, about 1.5 MB per submit.
- The copy on every use is required: CPU writes to a Shared buffer cannot be seen, and Metal guarantees they are visible to the next command buffer.
- The memory is not required. Proposal:
  - (i) free a shadow whose texture has not been used by any command buffer for N s, using the res2 LRU tick, and recreate it on next use (the copy happens then anyway);
  - (ii) for a buffer texture that is only read with `read()` and never sampled, check whether a `VkBufferView` texel buffer can replace the image. That needs no pitch rule, no shadow and no copy. It needs a shader-side check (`nvconv`/SPIR-V reflection); to be investigated, not assumed.

**Multi-plane private copies ("item 7").**
- A two-plane surface whose plane pitch the GPU cannot use (e.g. 3840x2160 with row 11524 B) gets a private image, copied in and out.
- Proposal:
  - copy **out** only when a command buffer wrote the image (usage includes render target or shader write and it was bound for writing);
  - free the private image after N s without use, as with the shadows;
  - planes whose pitch is already 256-aligned stay host imports. They already are: "420v 1920 pitch 1920 -> its own pages".

Both changes are plugin-only and use the existing res2 idle tick. Risk: the first use after idle pays the copy-in, which the current code pays on every upload anyway.

### 11.7 IPS/PSR question (g): `vbl_held` does not explain it

Across the 75 snapshots of the Docker run:
- `idle_allowed 1` and PSR `allow_active 1` in 38 (whenever `active_vblank_irq_count` was 0);
- `vbl_held 1` in only 11.

Yet the DMUB IPS counters (`rcg`, `ips1`, `ips2` entry/exit, read from the firmware's shared state) stayed **0/0 since boot** in both runs.

So the vblank reference is not what keeps IPS off. Two causes remain, and one 30 s static-screen read separates them (no video, no Docker; read `debug.nmx_frametrace` before and after):
- (1) neither capture ever had a static screen long enough: both had video playing;
- (2) the firmware never enters IPS, or never fills those counters, on this DCN 3.5.1 with our DMUB/IPS init.

If the counters stay 0 on a static screen with `idle_allowed 1`, compare the IPS mode DM chose (`init_data.flags.disable_ips`, `dc->debug` IPS fields) with what Linux picks for IP 3.5.1. No code until then.

### 11.8 out-34 fix set (compile-checked; main builds)

| item | repo / branch | commit | what |
|---|---|---|---|
| (a) NMXAccel sysctls, (b) `vbl_held` semantics, (c) five review follow-ups | frame-path-kernel `fix/out31` | `f01c1ad` (one commit, as asked at the time) | 9.x |
| (d) real process in the VM task info (`nmx_gtt`, fault print) | frame-path-kernel `fix/out31` | `873b17f` | patch `amdgpu-vm-task-tgid.patch` |
| (e) transfer-only one-shot submits exact | frame-path-plugin `fix/out31-plugin` | `c334220` | 11.2, 11.4 a; A/B `NVMTL_SL_EXACT_XFER=0` |
| (f) fault print names the BO / freed range | frame-path-kernel `fix/out31` | `c6555b4` | patch `amdgpu-vm-fault-name.patch` |
| (g) IPS | (none) | (none) | 11.7: one static-screen read first |

**Proof that (e) is complete**, i.e. that a surface used by one of those submits is listed:
- the marked submits record only barriers, `vkCmdCopy*` and `vkCmdFillBuffer` (each call chain read down to the `pvkCmd*` calls);
- RADV lists every source and destination BO of those commands itself (`radv_meta_copy.c` :73/:347/:354/:423/:561/:568/:613/:864/:865, `radv_meta_buffer.c` :246/:259/:344/:345);
- mipmap blits and timestamps are not marked.

**Correction (review of out-34, finding 2).** An earlier version of this section said "once parked, its PTEs are V = 0". That is wrong.
- `nmx_park_one` moves the BO to SYSTEM, which only puts its `bo_va` on the VM's invalidated list, and then unwires.
- The PTEs keep pointing at the old physical pages until that VM's next CS runs `amdgpu_vm_handle_moved` (`amdgpu_cs.c` 1308).
- So an unlisted use by a CS submitted **after** the park faults loudly: the PTEs are rewritten V = 0 first.
- But an unlisted use by a job **already in flight** at park time reaches unwired, pageable pages silently.
- 11.9 closes that window.

**What (e) changes in behaviour:**
- WindowServer's idle imports start parking after 60 s.
- The next use of a parked import pays a Step142 restore on WindowServer's submit (3.4: restore p99 about 1 ms, max 14.5 ms). A window that was hidden for a minute can cost one frame when it comes back.
- That is the same contract other processes already run under.

**Checks after install (read-only):**
- `debug.nmx_pin_by_proc` shows WindowServer `parked` above 0 after a few minutes of a static desktop;
- old60 pages in `nmx_userwire_by_kind` fall;
- WindowServer's log shows "transfer-only one-shot submits exact" and "carried the surface list" barely growing;
- `debug.nmx_gtt` shows real pids and names.

### 11.9 Park ordering: when may the pages go? (design for the review's finding 2; no code until out-34 is verified)

**What Linux does.**
- Userptr invalidation (`amdgpu_hmm_invalidate_gfx`, `amdgpu_hmm.c:81`) waits for the **BO's own** reservation fences (BOOKKEEP), then returns, and the pages may go.
- Eviction (`ttm_bo_evict`, then `amdgpu_bo_move_notify`, then `amdgpu_vm_bo_invalidate`) does the same wait.
- Neither clears PTEs. The VM's next CS rewrites them (`amdgpu_vm_handle_moved`).
- Linux is safe because of the CS contract: every BO a job touches is in its BO list, or is VM-always-valid and covered by the root reservation. So the job's fence is on that BO's reservation, and waiting for it covers every job that can use the pages.
- The window the review describes exists on Linux too, for a client that breaks the contract. The review's "Linux never has this window" holds only for contract-abiding clients.

**Our park against that.**
- `nmx_park_one` skips the BO unless `dma_resv_test_signaled(BOOKKEEP)` holds. It also requires that no CS listed the BO for 60 s.
- For a job that **listed** the BO, that is the same guarantee as Linux. No such job can be in flight when the pages go.
- The window is therefore exactly "a job uses the import without listing it". Until (e), that could not hurt: an unlisted import stayed wired forever. With parking, the completeness of the surface list matters.
- The plugin's lists are built by hand (`g_sl_use`, exact marks), not by the kernel, so we should not depend on them alone.

**Proposed ordering: defence in depth, and no sweep ever waits.** Split the park into states driven by the existing 1 s sweep.
1. **Move.** The BO is idle by its reservation and unused for 60 s.
   - Validate it to SYSTEM, as today. Its `bo_va` goes on `vm->invalidated` and the pages stay **wired**.
   - Record `f_vm`: a snapshot of the owning VM root reservation's BOOKKEEP fences (`dma_resv_get_singleton`). Every job of that VM in flight at this moment is in it, listed or not.
   - An import BO maps in exactly one VM: the importing process's. Exported BOs are not parked.
2. **Clear.** On a later sweep, if `f_vm` has signaled:
   - if the VM's next CS has already rewritten the mapping (the `bo_va` is no longer on `invalidated`), take that update's fence `f_pt`;
   - otherwise update it here: trylock the root reservation, then `amdgpu_vm_bo_update(adev, bo_va, clear = true)`. `handle_moved` does exactly this for a BO it cannot lock. That writes V = 0 PTEs and sets `flush_tlb`, and gives `f_pt`.
3. **Unwire.** On a later sweep, if `f_pt` has signaled: `ttm_tt_unpopulate` and `nmx_upin_park`, as today.
   - Any job submitted after step 1 went through `handle_moved` first, and a stale TLB entry is flushed at that VM's next VMID grab (`vm->tlb_seq`).
   - No job can reach the pages any more, listed or not.
4. **Abort.** If a CS validates the BO back to GTT at any point before step 3, the park is simply undone. The pages were never unwired, so there is nothing to restore.

**Cost and risk.**
- The pages are unwired 2 to 3 s later than today (two more sweeps). WindowServer's root reservation is busy almost all the time, but `f_vm` is a snapshot, so it signals within a frame or two.
- One extra page-table update per park, on the SDMA/VM entity, happens only when the VM had no CS of its own in between.
- New state per `amdgpu_ttm_tt`: a stage and two fence pointers, all under the BO's reservation as today.
- The trylocks fail softly: retry next sweep.

**Can this window explain the out-30 faults or copy errors?** Mostly no:
- A job that **listed** the BO cannot be in the window, because of the reservation check.
- The window only produces silent wrong data for an **unlisted** use by a job in flight at the moment of the park. A BO picked by the park has not been listed for 60 s, so that job would itself have had to leave it out. It never produces a V = 0 fault: a fault needs the PTEs rewritten, which happens only at a later CS, and that is the loud "after" case.
- **mediaanalysisd** (10.5) had **0 parked pages**, so neither case applies to it.
- **VTDecoderXPCService** parks (16k pages on 2026-11-18). An unlisted use of a parked import by a later CS would give exactly row 12's signature: a gfxhub write through V = 0 with the page tables present. So it stays a candidate for the VTDecoder faults.
- (f)'s new print decides it: "live mapping ... placement 0 ... userptr 1" means parked or unlisted, while "FREED ... ms ago" means a freed VA.
- Silent corruption from the in-flight case cannot be ruled out for the VCN/VT copy errors without (f) data. It needs an unlisted surface, which (e)'s completeness argument excludes for our transfer submits, and 11.9 removes in any case.

**Other review follow-ups, for the same next commit:**
- **(1)** `nvrm-accel.cpp` stuck-flip redo: `rs->retain()` before dropping `gFl.lock` for `nmxFenceWait`, `release()` after relocking.
- **(3)** fault printer: read `tbo.resource` and `tbo.ttm` only under `dma_resv_trylock(bo->tbo.base.resv)`, else print "bo busy".
- **(4)** freed-range scan: collect at most 4 hits under the spinlock, print after unlocking.
- **(5)** flips off after 600 NotReady answers: make sure that one line is logged once per boot.
