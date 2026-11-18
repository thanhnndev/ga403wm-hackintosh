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
| **2** | frame clock (L6/L7 vs P12) | compositor schedules from the flip-done / vblank timestamps of the real CRTC | IOFramebuffer VBL is a free-running `thread_call` at the nominal period; phase vs the real vblank is arbitrary per boot and drifts with clock mismatch and thread-call latency | anything timed from IOFB VBL aims at an imaginary vblank: a frame finished "just in time" can latch one refresh late, and the margin changes over minutes and across boots (consistent with the 0-142 drop spread on one build) | P | source (high); whether Tahoe's WindowServer/CoreDisplay times frames from IOFB VBL or from IOPresentment: **section 5 (pending)**; phase drift: not measured | `nmx_fb.cpp`: deliver `fVbl.proc` from `dm_crtc_high_irq` (a hook in `amdgpu_dm_crtc_handle_vblank` -> `nmx_fb_vblank(crtc)`), take `drm_crtc_vblank_get` while IOFramebuffer enables the VBL interrupt (`setInterruptState`), keep the timer only as a fallback when vblank IRQs are off | low-medium (VBL proc runs on the IH work-loop thread; must not block) |
| **3** | flip completion (L6 vs P11) | `dm_pflip_high_irq` completes the event in the IRQ | the IRQ already completes `flip_done`, but NMXAccel learns it by **polling every 200 µs on a thread call** (up to 50 ms) | +0-200 µs and a thread-call wake per frame; 5 000 wakeups/s while a flip is pending | L, W | source (high); 5.85 ms mean submit->seen | NMXGPU: add `nmxFlipNotify` (callback + refcon registered by NMXAccel) called from `flip_refresh` path in the pflip handler (hook after `drm_crtc_send_vblank_event` for our CRTC); NMXAccel calls `signalTransactionInterrupt` from a thread call kicked by it | low |
| **4** | serial present thread (L4 vs P6/P7) | non-blocking commit returns at once (`-EBUSY` if pending); fence wait on the commit worker | `performTransaction` waits for the fence (to 100 ms) and for the previous flip (to 20 ms) inline on the one pipe thread | one late frame delays the next transaction behind it; WindowServer's transaction queue backs up | P, L | source (high), drops 0 so far (the queue absorbs it) | follows from 1 and 3: with the fence in the commit and the latch notified, `performTransaction` never sleeps | low |
| **5** | client -> compositor sync (L2/L3 vs P1/P2) | one BO and one resv shared by all processes; the compositor's GPU job waits in the scheduler | each process has its own userptr BO of the same pages; ordering lives in user space (completion pumps, seeds); non-host-backed surfaces take CPU copies (`nvmtlSurfaceIn/Out`) | clients may wait for GPU completion on the CPU before CoreAnimation commits; CPU copies scale with resolution | P, L, W (CPU) in the apps the owner names (Electron strokes, Maps) | source (medium); how often surface-in/out copy under load: not counted -> instrumentation | NMXGPU: one GEM object per IOSurface ID shared by all importing processes (lookup through the surface hint, `drm_gem_object` refcount), so the CS adds and waits fences on one resv (`amdgpu_sync_resv`) as on Linux | high (cross-process object lifetime, WindowServer stability) |
| **6** | vblank refs and IPS (L7/L8 vs P13) | compositors hold vblank on while animating, so IPS/PSR stay off during motion | only the flips hold refs; at ~27 presents/s the CRTC's vblank IRQ can go off between presents (`disable_immediate` on DCN 3.5 APU without PSR) and `dc_allow_idle_optimizations(true)`; the next flip flushes `vblank_control_workqueue` to exit idle first | IPS entry/exit per content frame adds exit latency to the flip and churns DMUB | L, W | code path (high); whether IPS actually enters on this boot: **unknown** (`ips_support`, DMUB IPS counters only printed at suspend, `amdgpu-dm-ips-trace.patch`) | same as fix 2 (vblank ref while WindowServer wants VBL); export the DMUB IPS entry/exit counters as a sysctl (instrumentation) | low |
| **7** | interrupt context (L6/L9 vs P10/P14) | IH ring processed in hard IRQ | IH processed on an IOWorkLoop thread (kernel priority) | fence signal, pflip and vblank wait for a thread wake; one thread for all vectors' work on ring 0 | L | source (high); size: small at kernel priority, **not measured** | measure first (IRQ -> handler latency in the ring); an `IOFilterInterruptEventSource` whose filter only timestamps is cheap and safe | low (timestamp only) |
| **8** | timers (L9/V4 vs P15) | per-CPU timer softirqs, hrtimers in hard IRQ | one softclock thread runs every callout in order; a callout that sleeps on its lock delays all the others | jitter in vblank-off timers, fence fallback, VCN idle gating, sched timeouts | P (indirect), W | source (high); impact unknown | per-callout lateness counter (deadline vs run start) in `softclock_thread`; if late, a small pool of softclock threads or `thread_call` per callout class | low |
| **9** | memory policy (L2 vs Steps 141-142) | TTM pool shrinker + eviction under pressure, MMU notifiers | 2 MB chunk pool and IOSurface park/unpark on timers (5 s / 60 s / 10 min); xnu never fires `vm_lowmem` | re-wire of a parked surface on first use after 60 s idle (tab switch, Mission Control) costs a burst; pool timers wake periodically | M, occasional L | Step142 probes clean (handoff 5.2); 1828 parks / 644 unparks in 23 min | keep; replace timers by xnu memory pressure later (out of scope for stutter) | - |

Not a divergence any more (killed with today's counters): flip-import churn (11 imports in 23 min, 0 failures), CPU
copy to the panel (fallback 0, K6/beam counters 0), pipe drops (0), flip timeouts (0).

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

## 5. Closed side (REA) — in progress

NMXAccel and NMXAGDC are our source (above). The Apple side of the contract (IOAcceleratorFamily2 `IOAccelDisplayPipe`
VBL/transaction methods, what reference display-pipe drivers in the kernel collections do, and whether Tahoe's
CoreDisplay times frames from IOFramebuffer VBL or IOPresentment) is being read from
`/System/Library/KernelCollections/*.kc` with `tools/kc_disasm.py`; results go here.

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
| `frame-path/kernel-trace` (repo `nvidia-macos-driver-ws`, off `nmx-source-port` 4f6825b) | 64c11a5 | `gpu-port/xkpi/patches/amdgpu-dm-frametrace.patch` (+ `series`), `override/src/nmx_fb_bridge.c`, `xnu/nmx_fb.cpp`, `xnu/nmx_kext.cpp`, `kexts/NVRM/accel/nvrm-accel.cpp` |
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

Checks done: the patch series replays on the vendor HEAD with `--fuzz=0` and yields exactly the patched
`amdgpu_dm.c`; `amdgpu_dm.c`, `nmx_fb_bridge.c`, `nmx_fb.cpp`, `nmx_kext.cpp` compile with the tree's own scripts
(`cc.sh`, `cclk.sh`, `ccxx.sh`); new undefined symbols are only internal ones (`nmx_ft_*`, `nmx_dm_ips_counts`,
`drm_crtc_vblank_count`) plus `mach_absolute_time`/`IOMalloc`/`IOFree`, already imported by out-29, so the 581 rule
should hold (main's `nm -u` check decides). NMXAccel builds with `OGKM=~/ogkm615 NM_TAHOE=1
build/nmxaccel_build.sh kexts/NVRM <out>`; its undefined symbols are identical to the installed NMXAccel (883 = 883,
empty diff). The plugin passes `clang -fsyntax-only` with the tree's flags. Not run on the machine.

How main builds it:
1. NMXGPU: in `~/develop/projects/nmx-build-xkpi/src` (branch `nmx-source-port` @ 4f6825b) `git merge --ff-only
   frame-path/kernel-trace` (or cherry-pick 64c11a5), then `~/develop/projects/nmx-build-xkpi/build.sh out-30` in the
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

Pending section 5; current ranking above.
