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

## 6. Results: main's root run, 2026-11-19 12:36 on out-37 (`~/ga403-logs/ws-cpu-20261119-123622/`)

How the numbers were read:
- Reader: `tools/890m/ws-spin-buckets.py <mode>.spin.txt <presents>`.
- It counts **on-CPU samples only** (1 ms each). A kernel sample counts as kernel time only when the user stack ends
  in a syscall stub. Otherwise it is the stackshot's own interrupt of a thread that was running that user frame.
- Kernel frames are unsymbolicated (no KDK), so kernel time is split by syscall and caller only.
- No gfx fault lines, and `flip_tripped` 0.

Presents in 10 s: none 658, ca 1076, color 721, bitmap 754.

### 6.1 ms of CPU per present, by thread and layer

| thread | layer | none (owner's load) | ca | color | bitmap |
|---|---|---:|---:|---:|---:|
| main (`ws_main_thread`) | plugin (NVMTL, incl. its objc/malloc) | 0.49 | 0.50 | 0.54 | 0.58 |
| | RADV + libdrm (user) | 0.17 | 0.19 | 0.16 | 0.34 |
| | kernel under the driver (CS ioctl, IOConnect, BO create) | 0.37 | 0.47 | 0.34 | **1.06** |
| | kernel, other (mach IPC, mutex waits) | **2.98** | 1.07 | 1.56 | 1.02 |
| | WindowServer/CA own (SkyLight, QuartzCore, CoreDisplay, libobjc, malloc) | 1.88 | 1.59 | 1.52 | 1.60 |
| | **main total** | **5.88** | **3.82** | **4.12** | **4.60** |
| `coreanimation.pipelines` | shader translation + RADV compile | **15.00** | **1.98** | - | - |
| `nvmtl.execution` | completion (syncobj wait/reset ioctls, objc) | 0.41 | 0.37 | 0.43 | 0.50 |
| `root.user-interactive-qos` | CoreDisplay LUT burst | **34.85** | - | - | - |
| `windowserver.root_queue` | BO free (`drmCloseBufferHandle`) | 0.21 | 0.10 | - | 0.63 |
| **all threads** | | **57.4** | **6.4** | **4.8** | **6.0** |

The driver's own share of a frame is the plugin, RADV and the kernel time under the driver, on the main thread plus
the completion thread:
- 1.53 ms/present in `ca`; 1.29 in `color`; 2.31 in `bitmap`, with the per-frame import, BO create and BO free.
- On Linux the same work is about 0.1-0.3 ms.

Inside it:
- **Plugin self time is mostly the Objective-C runtime and malloc** (`objc_msgSend`, `objc_retain/release`,
  `nanov2_*`), not Vulkan work.
- **The CS ioctl costs 0.24-0.29 ms per present** (3-6 submits).
- **Completion costs about 0.1 ms**: `drmSyncobjWait` plus `drmSyncobjReset`.
- The IOSurface fence properties are within `IOConnectCallMethod`, 0.04-0.08 ms.

### 6.2 What the samples found that section 3 did not expect

**(1) Continuous pipeline creation.**
- In `com.apple.coreanimation.pipelines`, `CA::OGL::MetalContext::dispatch_async_pipeline` ->
  `create_pipeline_state` calls `-[NVMTLDevice newRenderPipelineStateWithDescriptor:]` -> `vkCreateGraphicsPipelines`
  (full RADV NIR compiles), and `newFunctionWithDescriptor:` calls the translator (`libnvmtl_translate`).
- It used **9.9 s of CPU in the 10 s `none` window** and 2.1 s in `ca`.
- A steady desktop should not be compiling. Either CoreAnimation keeps asking for new specializations (the "Uber"
  composite shaders take 18 function constants; the log shows `UberCompositeFragment specialized with 18
  constant(s)`), or it re-asks for the same ones.
- The plugin keeps no pipeline memo and passes no `VkPipelineCache`.
- RADV's disk cache directory is created per user (`nvmtl_vk.c:757`). Whether it works for `_windowserver` is
  unchecked.

**(2) A CoreDisplay LUT burst.**
- In the last 1.6 s of the `none` window, about 25 dispatch threads ran
  `CoreDisplay::DisplayPipe::RunFullDisplayPipe` -> `CombineLUTs` -> `Display::CurrentHeadroom` and spun on
  **one `std::mutex`**: 23.8 s of CPU.
- The main thread lost 1.56 ms/present to the same mutex.
- `RunFullDisplayPipe` recomputes the colour/EDR pipeline when headroom, brightness or the colour state changes. The
  owner had HDR video playing. Our HDR panel twins (StrixGOP `--hdr`) and the brightness path feed exactly those
  inputs.
- How often it fires is unknown; one burst every few seconds would be a large share of WindowServer's average CPU.

**(3) Per-frame client-surface import.**
- In `bitmap` (a new CPU-drawn image each frame), the main thread spends 0.36 ms/present in
  `amdgpu_create_bo_from_user_mem` (a userptr import, which wires the pages).
- The root queue spends 0.39 ms in `drmCloseBufferHandle` plus 0.08 in `bo_va_op` freeing them.
- On Linux the compositor imports a dma-buf: a handle lookup, nothing wired.

**(4) WindowServer's own work is 2.6-2.7 ms/present** (Apple code plus its mach IPC, in `ca`/`color`/`bitmap`).
- This part is not ours.
- It scales with CPU clock. FRAME-PATH and CPU-THERMALS measured busy Zen 5 cores at about 2.0 GHz with CPPC off,
  which inflates it relative to an M3 at 4 GHz.

## 7. Ranked fixes (expected saving per present unless noted)

| rank | fix | where | expected |
|---|---|---|---|
| **1** | **Stop the pipeline churn.** First count it: in WindowServer, per 30 s, `newRenderPipelineState` and `newFunctionWithDescriptor` calls, distinct keys (SPIR-V hash + state; name + constant values), time spent, logged through `nvlog` (P0b, plugin, small). If keys repeat, memoize both levels by key in the plugin (pipeline state objects are immutable; Apple's driver caches the same way) and give RADV a real cache (`VkPipelineCache` held by the device, plus a disk-cache directory `_windowserver` can write). If keys are new, find which CoreAnimation input changes the specialization (likely tied to item 2's headroom) | plugin `NVMTLDevice.m` pipeline paths, `nvmtl_vk.c:757` | 2 ms/present in `ca`; **about one core** under the owner's load (`none`: 9.9 s per 10 s) |
| **2** | **Find what triggers `RunFullDisplayPipe`.** Read-only: count CoreDisplay pipe rebuilds against our brightness and headroom updates (NMXBacklight in NMXGPU, StrixGOP HDR twins, the EDR headroom we report). A frequent trigger from our side (a brightness or headroom value that keeps changing by tiny steps, or a re-sent display attribute) is ours to fix; a real HDR start/stop is not | NMXGPU backlight, StrixGOP, NMXAMDFB attributes | bursts of about 20 core-seconds each; average depends on the frequency, unknown |
| 3 | **Cheap client-surface imports.** Cache the user-page wiring per IOSurface in the kernel (the surface hint already maps id <-> range), so a recycled surface re-imports without a new wire. The real form is FRAME-PATH row 5: one GEM object per IOSurface, shared by all importers | NMXGPU userptr import, `amdgpu-nmx-surface-hint.patch` | 0.5-0.8 ms/present for CPU-drawn content |
| 4 | **Leaner frame path.** Drop `@synchronized` and ObjC retain/release from the per-draw encoder path (C structs for bindings); one syncobj per command buffer reused instead of wait plus reset ioctls; then, with a KDK, break the CS ioctl's 0.1 ms per submit down by function (BO list, VM update, scheduler) | plugin encoder, `nvmtl_vk.c` submit and finish, NMXGPU CS | 0.5-0.8 ms/present |
| 5 | **CPU clock under load** (CPPC off, about 2 GHz): WindowServer's own 2.6 ms/present is Apple code and scales with it | CPU-THERMALS session's scope | not ours to patch here; noted so it is not counted as driver cost |
| - | P2 (two-plane 4K video as host imports, 12.13: df2565e logs the reason first) | plugin | 2-4 ms per 4K video frame; not exercised in this run |

Not done here: 1-4 need code. 1's counter is the first patch, before any memo.

## 8. Follow-ups after the ranking (2026-11-19, for main's next package)

### 8.1 Fix 1: what the pipelines thread was doing

WindowServer's log at the 12:36 run shows the plugin's specialization cache (AIR->SPIR-V with function constants,
`nvmtl_translate_with_fc_cached`) is mostly working, with 135-144 memory hits. Two misses were `fixed_frag_lpf_cpf`,
which took **3559 ms and 2650 ms** to translate and produced about 684 KB of SPIR-V each. RADV then compiles that.

So the 9.9 core-seconds were a few very expensive new specializations, not a stream of repeats. The real cost is
the size of the translated module (684 KB for one fragment shader), which is the translator's output. A later
step should look at it; it is out of scope for this package.

The package carries two changes in plugin b8a2baf:

**Counters** are logged every 30 s by every process (two "pipelines:" lines):
- pipelines made: render and compute;
- how many repeat a key already built in this process (what a memo would save);
- time spent and the slowest;
- SPIR-V volume;
- specialization cache hits and misses, with miss time.

**VkPipelineCache** is a per-process cache passed to every `vkCreate*Pipelines`. It is on while
`/Library/NullMoth/nvmtl-pipeline-cache` exists (rechecked every 5 s) or with `NVMTL_PIPELINE_CACHE=1`.
- Default: off.
- It is the memo for repeated keys: RADV hashes the full pipeline state.
- The `_windowserver` Mesa disk-cache directory is fine. The log at 11:55:14 says
  `/var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/C/WindowServer/nvmtl-mesa`, which is writable.
- The "Permission denied" seen earlier was a root-owned directory read by a user process. It is not WindowServer's.

### 8.2 Fix 2: what triggers the CoreDisplay CombineLUTs burst (read-only)

The mechanism is the one found in October (890M-TRACE.md Step11). `Display::CurrentHeadroom` caches only while an EDR
client has called `CoreDisplay_XRPresent`. Otherwise every `CombineLUTs` element takes the mutex. Our plane also
reports no gamma or linearization ("Attempting to get capabilities from plane with no gamma"), so CoreDisplay builds
the LUT itself instead of handing it to hardware.

The trigger is a display state change, not our brightness or headroom path:
- **12:36:14.38**: the display woke from dim (`displayDidWake`, `kLWLockFromDisplayDim` -> unlock on input).
  WindowServer then ran `IOFBSetDisplayModeAndDepth` mode 1, and NMXAccel ran `displayModeWillChange`.
  Every app then got an `edr` notification for about 2 s.
- **12:36:32-37**: about 5 s of per-frame pipe rebuilds: about 170 "plane with no gamma" lines per second, the
  framebuffer surfaces re-created and re-imported, and `edr` notifications. Safari reported
  `potentialHeadRoom=2`.
  - There was no mode set and no brightness line in the log.
  - It looks like an EDR or brightness ramp after the wake. I have not confirmed what caused it.
- In the 10 h of log before and after, there are **no other EDR storms**. The `edr` notification count is 0
  outside 12:36. Mode sets: 11:55 (boot) and 12:36:14 only.

The spindump's 23.8 core-seconds was therefore one wake/ramp event that landed inside the `none` window. It is not a
steady cost under the owner's load:
- It costs about 20 core-seconds per display wake from dim.
- It belongs below fixes 1 and 3.

The real fix is in our display path, not CoreDisplay: NMXAccel/NMXAMDFB answering the plane gamma/linearization
capability (AGDC 0x711 types 0x1/0x2/0x4) with a real DCN LUT behind it. That is the full-port item from Step10/11.
No patch was written here.

### 8.3 Fix 3: per-IOSurface userptr wiring cache: not in this package

The `bitmap` churn is a create-and-close of a userptr BO for each new client surface. A wiring cache that outlives
the BO needs its own lifetime and invalidation rules: the pages can be unmapped or freed by the owner while cached.
It belongs to FRAME-PATH row 5 (one GEM object per IOSurface), which is not a contained change.

The plugin fix f2c62c4 (surface keep) now lets two-plane surfaces expire. It does not change the `bitmap` path.

### 8.4 out-39 data (boot 2026-11-19 15:51:54)

**Pipelines (WindowServer, first minute after login).** Two 30 s reports:

| window | pipelines | new keys | repeats | creating | slowest | SPIR-V in |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 135 | 135 | 0 | 34.2 s | 4.25 s (12.9+700 KB) | 64 MB |
| 2 | 58 | 58 | 0 | 30.1 s | 2.2 s (6.6+685 KB) | 35 MB |

- Specializations in the same windows: 59 + 23 cache hits, 0 misses.
- So about 64 s of CPU in the first minute is RADV compiling about 700 KB fragment modules. The translator cost is
  zero: its disk cache hits.
- Nothing was logged after that, so the steady state has no new pipelines.
- The report is capped by nvlog after 8 lines; d850825 fixes that.

What this means for the switch:
- **The in-process VkPipelineCache cannot help:** there are 0 repeats in a process.
- What would help is RADV's **disk** cache across boots and logins. WindowServer sets
  `MESA_SHADER_CACHE_DIR=.../C/WindowServer/nvmtl-mesa` (log 15:52), yet every pipeline still compiles.
- Whether RADV writes and reads that cache is the next check, and it is read-only:
  - root `ls -la /var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/C/WindowServer/nvmtl-mesa`
  - its size before and after a WindowServer restart.
- About 700 KB of SPIR-V for one specialized `fixed_frag_*` module. **Measured, which corrects my first guess.**
  - `ffspec.swift` (scratch) loads QuartzCore's `default.metallib` through our plugin and specializes
    `fixed_frag_lpf_cpf` (60 function constants).
  - The output was parsed by opcode with `spvstat.py` / `spvvars.py` (scratch; no SPIR-V tools on the machine).

  | specialization | SPIR-V | translate | blocks | cond. branches | on a constant |
  |---|---:|---:|---:|---:|---:|
  | all 60 constants 0 / false | 684,848 B | 2.6 s | 4,099 | 865 | 0 |
  | every bool true, ints 0 | 699,260 B | 3.2 s | 4,092 | 868 | 0 |
  | unspecialized | 690,264 B | - | 4,099 | 865 | - |

  - The function constants **are** folded. All 149 `__metal_implicit_fc_pred_*` Private variables are left with
    0 loads, and no branch is left on a constant.
  - The remaining 865 branches depend on runtime data (uniforms, textures).
  - With these constant values the uber-shader is about 690 KB whatever the bools say, so my "no fold-and-prune"
    guess was wrong.
  - What is still unknown: the constant values WindowServer passes, especially the integer opcode and function
    selectors, which were 0 here. The cache file name is a hash of them.
  - Plugin 1d25988 (on top of d850825) logs the constants of any specialization miss over 500 ms, so the next build
    can translate WindowServer's real ones offline.
  - The 64 s at login is RADV compiling these modules (0 translator misses). The cheaper lever there is the RADV
    disk cache across logins: is `.../C/WindowServer/nvmtl-mesa` being written? Main is checking.

**Plane fallback reason (df2565e).**
- At 15:56:58 every `x420` plane in WindowServer and VTDecoderXPCService logged `no host import (linear alias or
  shadow image ...)`, then `item 7: private image`.
- The cause: plane 0 starts at offset 64 and plane 1 at 16,588,864; both are 64 mod 256. The DRM-linear alias is
  refused at bind (RADV binds linear images at multiples of 256).
- Fixed in plugin b855e71: a read-only wrapper with an unaligned start takes the existing btsh GPU shadow (one GPU
  copy from the host-imported pages) instead of a private image with two CPU uploads per frame.
- Writable wrappers are unchanged. `NVMTL_BTSH_OFFSET=0` gives the old behaviour.
- This is FRAME-PATH 11.6's double copy for two-plane video.

### 8.5 RADV disk cache was off in WindowServer (fix: scripts/radv/radv-disk-cache-euid.patch)

- Symptom: the WindowServer cache dir `/var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/C/WindowServer/nvmtl-mesa`
  exists (the plugin sets `MESA_SHADER_CACHE_DIR` to it) but holds 0 files. So every login recompiles all ~190
  pipelines: about 64 s of CPU in the first minute.
- Cause: WindowServer has uid 88 and ruid 0 (`ps -o pid,uid,ruid,svuid,gid,rgid,svgid` gives `88 0 0 88 0 0`).
  Mesa `disk_cache_enabled()` (src/util/disk_cache_os.c) returns false when `!__normal_user()`, which is
  `geteuid()==getuid() && getegid()==getgid()`. That check is meant for setuid programs.
- Ruled out:
  - the build option: `-DENABLE_SHADER_CACHE` is set in build-res;
  - `MESA_SHADER_CACHE_DISABLE`;
  - secure_getenv: there is no `HAVE_SECURE_GETENV` on macOS, so the dir comes from plain getenv;
  - the cache UUID: other processes use the same dylib and fill their caches (`~/.cache/mesa_shader_cache` 15 MB,
    iconservicesagent 1233 files).
- Fix (Mesa commit 085fc00, branch `fix/disk-cache-euid` in `~/develop/projects/radv-video/mesa-wt-diskcache`):
  - applies on Apple only;
  - a process with euid != ruid gets the cache when `MESA_SHADER_CACHE_DIR` is an absolute existing directory, owned
    by the euid and not group/other writable;
  - the WindowServer dir is `drwx------ _windowserver`, so it qualifies;
  - other OSes are unchanged.
- Hardening after review (Mesa 7c74449): the exception also requires real uid 0 and a non-root euid, so a
  setuid/setgid program a user starts (non-root ruid) keeps the cache off and cannot be pointed at a forged cache.
  Only the last path component is checked; its parents (`/var/folders/<x>/<y>/C`) are root-owned.
  `scripts/radv/radv-disk-cache-euid.patch` is the whole change from bffd919;
  `radv-disk-cache-euid-ruid0.incr.patch` goes on top of a tree that already has 085fc00.
- Recovery: WindowServer now loads pipelines from this cache at every login. If a corrupt or wrong cache is ever
  suspected (wrong rendering or a crash in RADV right after login), delete it as root and log in again:
  `rm -rf /var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/C/WindowServer/nvmtl-mesa/mesa_shader_cache*`
  (the folder itself is recreated by the plugin; `MESA_SHADER_CACHE_DISABLE=1` in WindowServer's environment is the
  other way out). Mesa checks every entry's CRC and the driver's build-id, so a stale cache after a RADV update is
  ignored, not loaded.
- Separate finding, not fixed here: the `com.apple.WebKit.GPU+*` nvmtl-mesa dirs are also all empty. Those processes
  have uid == ruid, so the likely cause there is a sandbox write denial.

### 8.6 out-41 x420 check: plane shadows recopied in every command buffer (fix: plugin 4b2835e)

- Boot 2026-11-19 17:17 (out-41 34090E87, plugin 582F97BC). `ws-x420-clips 2 20 30`: the x420 planes take the
  host import and the one-copy GPU shadow from b855e71 as designed ("surface 8 plane 0 3840x2160 pitch 7680 at +64 ...
  host import, read-only"; 3297 shadows made, all one-copy, no per-row path).
- Regression: `nvmtl_btsh_pre` copied every shadow in every command buffer that bound it. The prologue upload counter
  went 9,959,862 KB -> 41,699,526 KB over one 20 s clip (~31.7 GB of GPU copies, 4096 submits). WindowServer GTT
  418 -> 1374 MB after clip 1 from kept idle shadows, back to 570 MB once they expired (17:23).
- WindowServer CPU over the 101 s run: 25.4 s. No baseline; measure again with `ws-cpu-profile.sh` after the fix.
- Fix (frame-path-plugin `fix/out31-plugin` 4b2835e): a read-only shadow of an IOSurface plane (multi-plane
  surfaces, `nvmtl_vk_image_btsh_watch_surface`) copies only when the surface's seed moved since its last copy, the
  rule the private-image path already keeps (`nvmtlSurfaceIn`). The decision is made under `nvmtl_submit_mutex`, so
  the copy that took the seed is queued before every command buffer that skips; a failed prologue clears the seeds.
  Writers that move the seed: CPU writers (write lock), VCNDec after its GPU copy (e210759), and now the plugin's own
  GPU writes to host-imported planes of multi-plane surfaces (`nvmtlSurfaceOut`: `IOSurfaceLock/Unlock(0)` after
  completion). Single-plane and app-buffer shadows still copy in every command buffer. `NVMTL_BTSH_SEED=0` restores
  the old behaviour. The `buffer texture:` census line now reports "skipped at an unchanged surface seed".
- Verify after install: the skipped count grows during a paused x420 clip; prologue upload KB per clip falls to
  roughly one plane copy per decoded frame; no stale or looping frames in a playing clip (the e210759 symptom).

### 8.7 Submits and descriptor writes per present (out-41, boot 17:17): where they come from

**Submits.** The plugin's submit census in WindowServer: 4096 submissions per ~11 s during the x420 clips (~370/s
at ~60 presents/s, so ~6 per present), and all but 127 of 32768 come from `-[NVMTLCommandBuffer nvmtlSubmitAhead]`.
So every submit is one MTLCommandBuffer part WindowServer committed. Each becomes its own `vkQueueSubmit` with its own
`VkFence` (`nvmtl_vk_submit_begin`), so its own CS ioctl and its own syncobj wait plus reset on the completion thread.
Apple's driver also submits per command buffer; the cost difference is the ~0.1 ms CS ioctl per submit on our stack
(section 6.1: 0.24-0.29 ms per present).

**Descriptor writes.** The desc-cache in WindowServer (per minute, 17:22-17:25): ~370 k hits, ~23 k misses (6 %),
stale ~200 and page ~450 of them; epochs: ~10 k image (mostly `img by view`) and ~16 k buffer. Every miss is one set
allocation plus `vkUpdateDescriptorSets`: ~6 per present. The epoch bumps come from `vkDestroyImageView` and
`vkDestroyBuffer`. The writes follow from object churn (a new MTLBuffer and new texture views per frame, section 3
row C), not from the descriptor code. The fix is reuse of those objects, and the descriptor writes go with it.

**Design.**
1. Count first (one plugin patch, WindowServer only, every 30 s): commits, parts, submits, presents (NMX fence
   publications), commits that are waited on (`waitUntilScheduled` / `waitUntilCompleted`) and where in the frame;
   VkBuffer and VkImageView creates and destroys per present; desc-cache misses by reason (new handle vs epoch vs page).
2. Submit coalescing on one queue: a committed part with no CPU waiter and no event signal is held (not submitted)
   until the next commit on the same queue, a `waitUntilScheduled`/`waitUntilCompleted`, a part that signals an
   event, an NMX fence publication or present, or a 1 ms flush from the completion thread. A flush submits all held
   parts as one `VkSubmitInfo` (one CS ioctl, one fence; command buffers keep their order). Scheduled handlers run at
   the flush; completion is per batch (in-order queue, so no part completes early). Kill switch env.
3. Object reuse: per-frame MTLBuffer allocations from a size-class pool that keeps the VkBuffer (and its desc-cache
   epoch) alive across frames; texture views keyed by (image, format, range) and reused, so `vkDestroyImageView`
   stops bumping the image epoch every frame.
Step 1 decides whether 2 holds: if WindowServer waits for scheduling after each commit, the holds never batch, and
the CS cost has to come down in the kernel instead (BO list size, VM update; needs a KDK for the breakdown).

### 8.8 out-43 checks (boot 2026-11-22 09:12:45): the x420 verdict, corrected

out-43 (NMXGPU E3D447C5) with plugin DECFEDEE (fa238db), Standard mode (RTX powered).

**The seed gate works. The 84.6 GB was the Aerial wallpaper, not a gate failure.**
- First reading (wrong): `ws-x420-clips 2 20 30` at 09:17:20-09:19:01. WindowServer's prologue census went from 4096
  to 8192 submits with 29458 shadow uploads (84.6 GB, 2.9 MB average). That was read as "both 4K planes copied on every
  composite". The window mixed the clip with the Aerial wallpaper, which started in the clip gap.
- Own-process test, no install: `seedgate_test.m` loads a scratch build of plugin 5f302db through `NM_TEST_PLUGIN`. It
  wraps both planes of a 3840x2160 x420 CVPixelBuffer read-only, in the same layout WindowServer gets (plane 0 at +64,
  plane 1 at +16588864, row 7680), and reads them in N command buffers:
  - 1100 command buffers: 2 uploads, 2046 skipped, 2 shadows watched, 0 not found;
  - a new MTLTexture wrapper for every command buffer (WindowServer's pattern): the same result;
  - 3000 command buffers in 0.89 s: 4 uploads (the 250 ms net fired once), 4092 skipped.
- The seed never moved at commit or at completion. The commit-time and completion-time bumps only touch textures in
  `_surfDirty` with `_hostOn && !_hostRO`, and read-only planes never are, so there is no feedback loop.
- Producer side: `ws-x420-clips` with a seed probe showed 0 seed moves between a pool buffer's uses over 360 frames.
- What WindowServer really copied (syslog timestamps, after the clip had ended):
  - census windows 09:19:56 -> 09:22:12 and 09:22:12 -> 09:24:29 carried 99.5 GB each;
  - that is ~730 MB/s, ~90 uploads/s, 8.1 MB average;
  - WallpaperAerialsExtension and its VTDecoderXPCService started at 09:18:00, the moment WindowServer GTT jumped
    282 -> 1240 MB;
  - Aerial is 4K 10-bit HEVC (x420), decoded by Apple's decoder (VCNDec takes 8-bit only). Each decoded frame moves the
    seed and needs one copy of each plane: 30 fps x (16.6 + 8.3 MB) ≈ 746 MB/s.
- That copy is forced by the layout. CoreVideo puts plane 0 at +64, and a linear image's base must be 256-aligned, so
  these planes cannot alias the surface's pages and need a GPU shadow. The copy is GPU-side, only while the wallpaper
  is visible and animating.
- Options:
  - accept it (chosen for now);
  - ask CoreVideo for `kCVPixelBufferPlaneAlignmentKey` >= 256. That only works where we create the buffers (VCNDec's
    8-bit output; check whether VT honours it the next time VCNDec is touched);
  - a texel offset in the translated shader: not scoped.
- Lesson: before blaming the gate, split census windows by syslog timestamp and check which decoders are running.

**Surface keep never expired while nothing new was wrapped (fix: plugin 7ceff16).**
- The keep sweep ran only from `nvmtl_surface_keep`, i.e. on a miss that inserts a new wrapper.
- With the display asleep, WindowServer kept 79 entries for 10+ minutes past `NVMTL_KEEP_MS`, with 810 MB
  `gtt_resident` (the kept backings' shadows and images) and the released surfaces still allocated.
- 7ceff16 adds a dispatch timer: every `NVMTL_KEEP_TIMER_MS` (5000 ms, 0 = off), under the same
  `@synchronized(device)`, while the table has entries.
- Own-process A/B: a surface wrapped once and released is freed by 8 s with the timer and still alive at 8 s
  without it.
- The kernel's Step142 park is NOT affected: it is a delayed work of its own (every 1 s while anything can be parked).

**Frame census (this boot).**
- About 1.5 commits and 1.5 submits per present.
- Every commit is waited on: `waitUntilScheduled` count = commit count.
- Per present:
  - views: 0.02-1.8 idle, 4-6 during a video clip;
  - VkBuffers: 1.2-1.5 idle, 5-10 during a clip;
  - desc-cache misses: 5-7.5 (7.5-17 %).
- So submit coalescing (8.7 step 2) has little to give. It is dropped.

**Ranking after this boot.**
1. Descriptor misses and VkBuffer/view churn per present.
2. Warm-start pipelines: ~108 ms each with a warm Mesa cache.
   - Root count of the cache dir: 714 files, 41 written this boot, 281 written between 11-19 17:30 and this boot,
     5084 KB.
   - So the keys are mostly stable. Time the stages of one warm create (translator, vkCreateShaderModule,
     vkCreateGraphicsPipelines) in a test process before proposing a fix.
3. Aerial shadow copies (accepted).

### 8.9 Desc-cache misses and object churn per present (plugin 921113d, own-process test)

Method: `plugin/tests/carender_test.m` drives Core Animation's own renderer (CARenderer, the CA render code
WindowServer composites with) on a scratch NVMTLDevice in a test process (`NM_TEST_PLUGIN`): 6 IOSurface windows
with corner radius and shadow, a text layer, a moving cursor layer, a 4:2:0 video layer. Each frame counts as one
present in the plugin's census. Optional: video 2 (8 frames handed over as mach ports, the way WindowServer gets
them), video 3 (CVPixelBufferPool), churn N (N x [2 MTLBuffers + 1 texture view] made and dropped per frame).

| per present | WindowServer out-43 | own process, before | own process, 921113d |
|---|---|---|---|
| desc-cache misses (sets allocated + written) | 5-7.5 (7.5-17 %) | 5.00 (12.8 %) | 0.11 |
| of them: written by an earlier command buffer, still valid | (not measured) | 5.00 | 0.11 |
| device-level cache hits | - | - | 4.89 |
| with 1 VkBuffer + 1 view churned per present | - | 3.00 of 5 past a global epoch | 4.74 hits, 0.26 stale |
| set snapshot path (NVMTL_SNAP_TIMING=1) | - | ~38 us | ~31 us |
| VkBuffers / views made per present, idle | 1.2-1.5 / 0.02-1.8 | 0.00 / 0.00 | same |
| VkBuffers / views made per present, video (1, 2, 3) | 5-10 / 4-6 | 0.00-0.03 / 0.00-0.03 | same |

The cause of the miss class: the desc-cache lived in one command buffer, so each command buffer started cold and
re-wrote the 5 descriptor combinations Core Animation uses per frame. Every miss was a key that was "written before and
still valid". The fix keeps sets across command buffers (the way a Linux compositor on RADV does: wlroots' Vulkan
renderer writes one set per texture when the texture is made and only binds it per frame):
- entries own their set and are pinned by every command buffer that uses them until it retires;
- binding 640 is written at base offset 0, so the dynamic offset reaches any slot of the address page (the page is in
  the key);
- validity uses per-handle bucket epochs instead of the global epochs.
The last-frame checksum is identical with the cache on, off, and with the desc-cache off.

Size of the win: ~7 us per present on the set path, i.e. small next to WindowServer's ~2 ms per present. Own-process
CPU per frame (unthrottled, ~530 fps) is ~850 us, 227 us of it system. Most samples are Core Animation, RADV
recording and fence waits (sleeping, not spinning). The desc-cache was not where WindowServer's CPU goes.

Churn: my process does not reproduce WindowServer's VkBuffer/view churn. Surface keep holds the video wraps in all
three video modes. What makes WindowServer's 1.2-1.5 idle and 5-10 clip VkBuffers per present can only be read in
WindowServer. Knobs (nvrm610.conf, no env needed):
- `NVMTL_CHURN_SITES=1` prints the busiest creating call sites with the census (release syslog, 30 s);
- `NVMTL_SNAP_TIMING=1` adds the set path time per present.
The census line "misses per present" now also says how many of WindowServer's misses the device-level cache served
and how many the old global epochs would have thrown away.

## 9. Idle-day series (out-44 + plugin 27611e6 package)

### 9.1 Top-down WindowServer CPU and who dirties a "static" desktop (out-43 data, 2026-11-22 10:05)

Inputs: `~/ga403-logs/ws-cpu-20261122-100512/none.*` (WindowServer-only spindump at 1 ms, 554 presents in 10 s,
`tools/890m/ws-spin-buckets.py none.spin.txt 554`) and `~/ga403-logs/ws-dirty-1005.spin.txt` (all processes, 10 ms, 10 s).

**WindowServer, all threads: 9.31 ms CPU per present** (proc utime 3.71 s + stime 1.74 s over the 10 s).

| bucket | ms/present | biggest frames |
|---|---|---|
| Apple user code (rest) | 4.36 | QuartzCore 1.11, SkyLight 0.69, libsystem_platform (memmove/memset) 0.63, malloc 0.25, objc 0.20 (ws_main_thread) |
| kernel, not our driver | 2.23 | mach_msg2_trap under CGXRunOneServicesPass 0.75, bsdthread_ctl 0.30, CGXPostReplyMessage 0.27 |
| plugin (NVMTL) | 1.26 | commitAndWaitUntilSubmitted 0.48, drawIndexed 0.31, nvmtlSubmitWithEvents 0.23, setRenderPipelineState 0.14, newTiledTextureWithDescriptor 0.14 |
| kernel, our driver | 1.00 | CS submit ioctl 0.33, syncobj wait/reset (nvmtl.execution 0.61 in all), bo free / VA ioctls (root_queue, NVMTLTexture dealloc 0.15) |
| RADV | 0.46 | command recording, descriptor writes |

ws_main_thread alone is 7.34 ms per present (rest 3.51, k-other 1.86, plugin 0.94, k-drv 0.65, radv 0.37).

**The top two costs:**
1. The present rate itself. Apple's per-present compositor work (QuartzCore, SkyLight, client IPC: about
   6.6 ms/present of user and kernel time that is not ours) scales with how many frames clients commit. The desktop
   is not static: something commits about 55 frames per second.
2. Our stack: about 2.7 ms/present (plugin 1.26 + RADV 0.46 + driver ioctls 1.00). The largest single item is the
   synchronous submit path (commitAndWaitUntilSubmitted + CS ioctl + syncobj wait, about 1.4 ms together). Draw
   recording is next (drawIndexed + pipeline state + texture creation, about 0.6 ms). Texture create and free per
   frame (newTiledTexture 0.14 + dealloc 0.15 + BO/VA ioctls) is the churn that 8.9 counts.

**Who dirties the screen (ws-dirty-1005, CPU over 10 s):** WindowServer 3.54 s. The clients that produce frames:
- **The Claude desktop app** (2.9 s in all). Renderer [906] 1.46 s: the `Compositor` thread (0.39 s) and
  CrRendererMain run in all 1001 samples, plus five raster workers at ~0.12 s each. GPU process [781] 1.42 s:
  CrGpuMain 0.75 s, VizCompositorThread 0.39 s, and a `CVDisplayLink` thread live in all 1001 samples, with short
  display-link threads started and stopped about every 100 ms. This is a running BeginFrame loop: a CSS
  animation or a streaming view in the app (a session that is "working" keeps a spinner/shimmer going). Each frame
  is a CA commit to WindowServer.
- **Activity Monitor** [2454] 1.03 s on its main thread (graph updates; CA commits in 65 samples).
- spindump 3.59 s and osascript 1.09 s are the measurement itself.

No other client showed frame work. Our own VBL/damage path does not create presents by itself: the presents follow
client commits. The test that settles this is idle-day test 1 (all-process spindump with the Claude app idle or
closed). The expected answer is that presents fall to the 5 s Aerial bursts and the clock.

### 9.2 Address lowering: disk cache of the lowered modules (plugin 0f2a94a, own process; next package)

WindowServer lowers every Core Animation specialization at every start (`nvmtl_address_shader_g`: translator
`nvmtl_lower_buffer_addresses_ex` plus our physical-bounds, helper and read-only passes). This happens after the fc
cache has already served the translated SPIR-V from disk. Each lowering is 50-200 ms. An align-guarded module is lowered twice: flags 0 reports the
promise, then flags 1 makes the SAFE module. The result was cached only in memory.

0f2a94a stores the lowered module next to the fc entries: `spvcache/<sha256>.low1.<translator tag>.c3.spv`, with the
same owner and the same trimmer. The key is SHA-256 over:
- the input SPIR-V and the effective flags;
- the table mode (UBO/SSBO) and the align guard;
- the plugin's own image UUID;
- the code-changing `NVMTL_*` knobs (the translator's getenv list: `NVMTL_NO_*`, `MATRIX8*`, `WG_*`, `I64*`, `ARGBUF*`,
  `XLATE*`, `B78*`; ours: `TABLE_*`).

Log paths and census switches are left out. A first version keyed every `NVMTL_*` variable, and its per-process
`NVMTL_LOG_PATH` split the cache. The file is `"NVLW" | version | status | info[4] | SPIR-V`, and the align-guard info
comes back with a hit, so the flags-0 decision is the same. A refused module (status 0) is cached too. A torn or
foreign file is a miss. `NVMTL_LOWER_DISKCACHE=0` turns the cache off.

Own process (`carender_test 40 0 6`, 6 windows with shadows and text, AIR and fc caches warm):

| run | lowerings | lowering ms | 40 frames wall |
|---|---|---|---|
| disk cache off | 18 | 1127-1285 | 0.86-0.93 s |
| cache on, cold | 18 (stored) | 1191-1284 | 0.86-0.91 s |
| cache on, warm | 0 (16 disk hits) | 0 | 0.25-0.28 s |

**Correctness:**
- Two independent cold runs wrote byte-identical files for the 12 modules both reached.
- The last-frame checksum of this test depends on timing even with the cache off: three values appeared across
  identical cache-off and cache-miss runs. With an 80 ms delay added to each disk hit, the hit run gives the cache-off
  checksum exactly (7bc2d707...), so a hit renders what a fresh lowering does.

**Lower once:** the cold start still lowers an align-guarded module twice. Removing the flags-0 pass needs the
translator to return the SAFE module, or the promise info, from one call (a translator change). With the disk cache
that cost is paid once per machine per plugin/translator version, not at every WindowServer start.
In WindowServer the expected gain at login is the sum of the post-reboot P5 lines (16 lowerings, about 1.2 s in
our process).
