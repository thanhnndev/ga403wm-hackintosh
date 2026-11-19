# WS-CPU: WindowServer CPU per frame on the 890M stack (2026-11-19, out-37)

What the owner raised: WindowServer on a MacBook Pro M3 sits at about 0.5 % CPU. Here it was 26-42 % at about 50
presents/s on out-34, which is about 5-8 ms of CPU per frame. This document follows the FRAME-PATH method:
1. measure what we can;
2. read the per-frame path in our source;
3. compare it with Linux;
4. rank the divergences;
5. then write patches.

The older `docs/WINDOWSERVER-CPU.md` describes the NVIDIA/NullMoth 1.14 stack on Sequoia (CPU upload copies to an
RTX). It does not describe this stack.

Per-present cost is the number to compare. The 0.5 % on the M3 is a mostly static desktop (a few presents/s), so
compare milliseconds per present, not percent.

## 1. Measured on out-37 without root (2026-11-19 12:25, the owner's load: Chrome video, Claude, Docker)

`tools/890m/present-rate.sh` and a per-thread `ps -M` delta over 10 s, against `debug.nmxaccel_flip_submitted`:

| sample | presents/s | WindowServer CPU (one core) | CPU per present |
|---|---:|---:|---:|
| 12:24, 10 s | 15.1 | 5.2 % | 3.5 ms |
| 12:26, 10 s | 30.1 | 17.3 % user + 4.2 % sys | **5.75 ms user + 1.40 ms sys = 7.1 ms** |

Split of the 12:26 sample by thread (only threads alive at both ends; dispatch threads that came and went count in the
process total only):

| thread | priority | user ms/present | sys ms/present |
|---|---|---:|---:|
| main (CGXUpdateDisplay, compositor) | 79R | **5.22** | **1.06** |
| thread 6 | 31T (default timeshare, where a no-QoS dispatch queue runs: `nvmtl.execution` completion) | 0.30 | 0.20 |
| thread 5 | 31T | 0.13 | 0.03 |
| thread 1 | 79R | 0.07 | 0.03 |

Since boot (11:54): 6:31 of CPU, 5:11 user and 1:19 sys, so about 80 % of it is user space.

**Reading:** about 90 % of the cost is on the compositor's own thread, and most of that is user space. The completion
path (row 1 of FRAME-PATH) is about 0.5 ms per present. On Linux the whole compositor frame is typically 0.3-1 ms of
CPU (mutter/kwin with RADV and amdgpu), with a CS ioctl of 20-50 µs. On the M3 it is a few tenths of a millisecond.
**The 5 ms of user time on the main thread is the gap.** The stack samples in section 4 say whose code it is.

### 1.1 Per-frame operations that the plugin's own counters show (WindowServer, `log show`, 11:55-12:25)

| what | rate | per present (at ~30/s) | source |
|---|---|---|---|
| Vulkan submissions (`nvmtlSubmitAhead`) | 4096 per 20-45 s, so 90-200/s | **3-6 CS ioctls** (Linux: 1) | `submit census` lines |
| BO handles per submission | 17 average (WS-only surface list, exact lists) | - | `BO list` line |
| new `MTLBuffer` (plugin buffer objects) | about 1 per submission, 8M-1.3G B allocated live | 3-6 | `buffer census` |
| descriptor-cache misses (a set is written: `vkUpdateDescriptorSets`) | ~290-380/s | ~10 | `desc-cache stats` (hits ~1300-4400/s) |
| `MTLTexture` objects released | 94 489 in 16 min, so ~100/s | ~3 | `image census` |
| buffer-texture shadow uploads (an unaligned-pitch texture over a buffer gets a shadow image; its upload is a prologue command buffer) | 4096 more uploads per 4096 submits after the start (1.6 GB uploaded in the first minute) | ~1 copy; **not** an extra CS: the prologue rides in the same `vkQueueSubmit` (`nvmtl_vk.c:6309-6330`, `cbs[]`), the census text "each WAS its own submit" is stale | `pre-submit prologue census` |
| surface-in CPU copies (`nvmtlSurfaceIn` -> `nvmtl_vk_image_write`: memcpy into staging plus a transfer submit and **a wait**) | 2000 per 33 s while 2-plane 3840x2160 surfaces (Aerial wallpaper / video) were on screen, about 0 otherwise | 2 copies, ~12 MB, per video frame | `G13 surface-in #` lines, 12:06-12:07 |
| IOSurface fence properties (`NMXFencePending`, `NMXFenceSubmitted`, `NMXFenceDone`) | 3 calls per written surface | measured **5.6-8.8 µs per call**, so <0.1 ms | `tools`-free microbenchmark (`IOSurfaceSetValue(s)` on an own surface) |
| `debug.nmxaccel_fence_wait` sysctl read | cached 1 s (it was ~1 % before) | 0 | `NVMTLEventSync.m:104-117` |

### 1.2 Per-frame plugin work, read in the source (`frame-path-plugin` `fix/out31-plugin` 920832a)

For each command buffer that CoreAnimation commits in WindowServer:
- `nvmtl_vk_cmd_begin` (`nvmtl_vk.c:5209`): pop a command pool, `vkAllocateCommandBuffers`, `vkBeginCommandBuffer`,
  pop or create a 2-entry timestamp query pool, reset it, and write a timestamp (for `GPUStartTime`/`GPUEndTime`).
- Each render encoder: the Metal calls are recorded, and the Vulkan render pass, its load variant (`nvmtl_rp_variant`,
  under a global mutex) and its attachment views are made at begin.
- Each draw: the binding table is snapshotted into a descriptor set (`nvmtl_snapshot_set_c`: reuse of the last set, a
  desc-cache hash lookup, or a new set written with `vkUpdateDescriptorSets`), the pipeline is bound, and `vkCmdDraw*`
  is called.
- Commit, `nvmtl_vk_submit_begin_at` (`nvmtl_vk.c:6273`):
  - a prologue command buffer for shadow uploads, in the same `VkSubmitInfo` (one CS);
  - the BO list (surface list plus exact list);
  - `vkQueueSubmit` (RADV: winsys BO list, `amdgpu_cs_submit_raw2`, the CS ioctl);
  - a syncobj for the completion thread;
  - the fence marks.
- Completion on `nvmtl.execution`: syncobj wait, timestamps, the `NMXFenceDone` property, and releases.

The plugin already times these stages (`nvmtl_perf_note`, `PERFSUB` with hook/end/fence/submit/wait/retire). However,
it is switched on by `NVMTL_PERF_LOG` in the environment and prints to stderr, so **it cannot be used in WindowServer
as built**. Section 5 (P0) makes it usable there.

## 2. What Linux spends on the same frame (reference)

| stage | Linux, RADV + amdgpu, a compositor frame | here |
|---|---|---|
| compositor's own scene work (layer tree, damage, shaders chosen) | mutter/kwin: 0.1-0.5 ms | CoreAnimation in WindowServer: the same order on the M3 (0.5 % at idle); to be read from the samples |
| API recording | GL/Vulkan driver: per draw ~0.5-2 µs; descriptor sets from a pool, often push descriptors | Metal -> plugin -> Vulkan -> RADV: two translation layers, per draw unknown -> samples |
| submissions per frame | 1 (`DRM_IOCTL_AMDGPU_CS`), 20-50 µs incl. BO list | 3-6 (one per CoreAnimation command buffer) |
| CPU pixel copies | none (dma-buf, the GPU samples the client's BO) | surface-in for multi-plane surfaces and some shadows (11.6); none for single-plane host imports |
| completion | the kernel; the compositor reads one fd event | a user thread per command buffer: syncobj wait plus IOSurface properties (~0.5 ms/present measured) |

## 3. Candidate divergences (ranked by expected CPU per present, **before** the samples; each line says what in the spindump confirms or kills it)

| # | candidate | expected | confirm in the spindump |
|---|---|---|---|
| A | Metal -> Vulkan translation per draw in WindowServer (binding snapshot, desc-cache hash, `vkUpdateDescriptorSets` on miss, pipeline variant lookup, `@synchronized` per call, ObjC retain/release of every bound object) | the largest unknown: CoreAnimation issues hundreds of small draws per frame for a busy desktop; 5-10 µs each would be 1-3 ms | main-thread time under `-[NVMTLRenderCommandEncoder ...]`, `nvmtl_snapshot_set*`, `nvmtl_dc_lookup`, `radv_UpdateDescriptorSets`, `objc_msgSend`/`objc_retain` |
| B | per-command-buffer fixed cost times 3-6 per present: pool pop, query pool, render-pass variants, BO list building, `vkQueueSubmit` -> RADV `radv_amdgpu_winsys_cs_submit` -> CS ioctl, syncobj create/export | 0.3-1 ms user + the 1.06 ms sys | `nvmtl_vk_submit_begin_at`, `radv_queue_submit`, kernel frames under `amdgpu_cs_ioctl` (`amdgpu_cs_parser_bos`, `amdgpu_vm_bo_update`, `ttm_bo_validate`, userptr checks) in the spindump's kernel stacks |
| C | object churn: a new `MTLBuffer` per submission and ~3 texture objects per present (VkBuffer/VkImageView create and destroy, heap placement, keep-cache sweeps every 100 ms) | 0.2-1 ms | `newBufferWithLength`, `nvmtl_vk_buffer_create`, `vkCreateImageView`, `nvmtl_keep_sweep` |
| D | CPU pixel copies: surface-in of multi-plane surfaces (video, Aerial wallpaper: ~12 MB per frame) and buffer-texture shadows plus writebacks | 0 on a plain desktop, **2-4 ms per video frame** when a 2-plane 4K surface is composited | `nvmtlSurfaceIn` -> `nvmtl_vk_image_write` -> `_platform_memmove`; `shadow`/`writeback` frames |
| E | kernel time on the main thread (1.06 ms/present): CS ioctls, IOSurface IPC (measured small), `IOSurfaceLock`, `mach_msg` to the accelerator | 1 ms | kernel frames in the spindump (it records kernel stacks) |
| F | WindowServer's own work that is different on this machine: no hardware overlay planes (FRAME-PATH PV3: every video frame is a full-screen composite), HiDPI 2880x1800 at 120 Hz nominal, the 30 % CPU of `WallpaperAerialsExtension` feeding WindowServer 4K frames | in the CoreAnimation share | `CA::Render::` and `CA::OGL::` time outside plugin frames |

## 4. Profiling procedure (for main: one root command, about 90 s, bounded, installs nothing)

`tools/890m/ws-redraw-load.swift` is a repeatable redraw load. It is synthetic, opens a 600 pt window and exits
by itself. It has three modes:
- `ca`: a layer spun by a render-server animation; WindowServer only, the client commits nothing.
- `color`: the client changes a layer colour at 60 Hz; one CA commit per frame, no client GPU work.
- `bitmap`: the client replaces a CPU-drawn image at 60 Hz, the way a CPU-drawn app does.

`tools/890m/ws-cpu-profile.sh`, run as root, does the following for `none` (the owner's own load only) and each mode:
1. starts the load as the console user;
2. waits 3 s;
3. takes `spindump <WindowServer pid> 10 1 -onlyTarget -noProcessingWhileSampling` (a kernel stackshot: WindowServer
   is neither attached nor suspended) and, at the same time, the per-thread `ps -M` delta and the present count.

```bash
osascript -e 'do shell script "/Users/thanhnndev/develop/projects/ga403wm-hackintosh/.claude/worktrees/hungry-mclean-f82082/tools/890m/ws-cpu-profile.sh" with administrator privileges'
```

The output goes to `~/ga403-logs/ws-cpu-<time>/` (`<mode>.spin.txt`, `<mode>.cpu.txt`). The owner sees a small window
spin or change colour three times, 13 s each. The owner should keep using the machine as usual; video playing is fine,
because `none` records that baseline and the modes are read as the difference from it.

What I do with it: per mode, (presents, CPU per present), and the main thread's samples bucketed by owner:
- CoreAnimation/SkyLight;
- the plugin (`NVMTL*`, `nvmtl_*`);
- RADV (`radv_*`, `ac_*`, `si_*`);
- libdrm/ioctl and kernel (amdgpu, ttm, IOSurface, mach);
- libobjc/malloc.

Each bucket is converted to ms per present. That table replaces section 3's "expected" column and ranks the fixes.

## 5. Fixes already justified by the source (independent of the samples; sizes to be confirmed)

| # | fix | where | expected saving |
|---|---|---|---|
| P0 (held) | the plugin's stage timers in WindowServer (file switch, thread CPU, `nvlog` per 10 s). They time only the submit stages (hook/end/fence/submit/retire), not encoding, which is candidate A, and encoding is interleaved with CoreAnimation's own work on the same thread. The spindump answers both, so P0 is written only if the samples leave a stage unresolved | `nvmtl_vk.c:3222-3262` | instrumentation |
| P2 | multi-plane surfaces as host imports per plane (11.6: today "private image, copied in and out, more than one plane"): the GPU samples the planes in place | `NVMTLDevice.m` item 7 / plane-host path | 2-4 ms per 4K video frame composited |
| P3 | after the samples: whichever of A/B/C dominates (descriptor push/caching, per-command-buffer state reuse, buffer/view recycling) | - | sized by section 4 |

Not a fix (the owner's rule): reducing the present rate, hiding windows, or moving WindowServer off the GPU.
