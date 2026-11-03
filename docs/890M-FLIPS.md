# 890M page flips: design notes (Step97, 2026-11-03)

Goal: the display scans a buffer the GPU wrote, switched at vblank and only after the GPU has finished with it (the
fence). No CPU copy and no tearing. Today NMXAccel's `performTransaction` does three things in a row for every frame:

1. it waits for the fence (4.0 ms);
2. it waits for the beam (2.2 ms);
3. it does the K6 CPU copy (3.2 ms).

That is ~9.4 ms of serial present path per frame. It holds the panel at ~75 fps, against the 8.33 ms budget of the
2880x1800 OLED at 120 Hz. kernel_task sits at ~28% CPU, mostly from the copy.

The NMXAccel code is in the fork (PolyForm, NullMoth):
- `thanhnndev/nvidia-macos-driver`, branch `ci/nmxaccel-flip`, files `kexts/NVRM/accel/nvrm-accel.cpp` and
  `kexts/NVRM/nmx_flip_abi.h`.

This file only describes it.

## 1. What WindowServer renders into today, and why the copy exists

The live boot log (23:14 boot, NMXAccel 1b9c7b9f) shows the following.

**The framebuffer resource.** `initFramebufferResource` runs only for index 0, four times at boot. Each time it wraps
the bridge's single live scanout (phys 0x87c000000, 2880x1800, pitch 11520, 20738048 bytes) in an `NVVidMemory`
flagged `fScanout`. The family soon calls `deallocPhysical` on it ("SCANOUT -- not ours to free").
- This resource is not where WindowServer composites.
- It exists for the family's legacy flip-buffer path (`submitFlipBufferTransaction`) and to make the pipe active.
  Before 30237fd, a framebuffer that reported phys 0 left the pipe inactive and every transaction failed.

**The composite target.** Every transaction's plane 0 is an IOSurface from CoreDisplay's own swap chain. The K6
lines show:
- 2880x1800, BGRA (0x42475241), row 11520, memory descriptor 20828160 bytes (1808 rows);
- surface ids rotating 0x2, 0x3, 0x5, 0x6 during login, then a new set (0x7f, 0x6, 0x84, ...) after login;
- plane resource `NMXResource` with **no vidmem** (`vidmem 0 bytes`): `resourceTypeForIOSurface` returns 0x80, a
  system-memory IOSurface;
- WindowServer's NVMTL imports those pages into RADV as userptr BOs and renders into them on the GPU.

**Why the copy exists.** DCN scans exactly one buffer: the VRAM buffer that `nmx_fb_bridge.c` creates once
(`drm_client_framebuffer_create` + a single modeset commit). DCN has no address for the IOSurface pages. They are not
in the GART, and DC was brought up without GPU VM:
- `nmx_fb_before_attach` sets `amdgpu_sg_display = 0` before DM init;
- so `amdgpu_dm_init` sets `adev->mode_info.gpu_vm_support = false`.

The bridge also never flips. So the CPU has to move the pixels from the IOSurface into the scanned buffer, and pace the
copy against the scan so a refresh never shows two frames (Step83).

## 2. What display control NMXAccel has into NMXGPU today

`NMXAMDFB::callPlatformFunction` (xkpi `xnu/nmx_fb.cpp`) answers only `nvScanoutInfo`: kva, phys, width, height and
pitch of the one buffer. Everything else goes to `IOFramebuffer` or `IOService`, which return unsupported:
- `nvAllocVram` is not implemented on the AMD side, so NMXAccel cannot get VRAM from NMXGPU;
- there is no flip call;
- the "NullMoth display: pipe:" trace lines (setDisplayMode, scanout ok, register VBL, get/setAttribute) are the
  IOFramebuffer surface only;
- the VBL that CoreDisplay sees is a thread-call timer at the mode's refresh (`vblFire`), not the hardware vblank.

On the DRM side the bridge is an in-kernel DRM client. It only does `drm_client_modeset_commit` (blocking) on probe,
hotplug, restore and display power. A primary-surface address change at vblank does not exist yet. It would be cheap
to add, because the DRM client already holds the CRTC, the plane and the modeset locks. Details are in section 4.

What NMXAccel can do alone:
- **Read** DCN registers over BAR5. The beam code already maps it.
- The HUBP0 registers (DCN 3.5, segment 2 base 0x34C0, HUBPREQ stride 0xdc) can be read the same way:
  `DCSURF_PRIMARY_SURFACE_ADDRESS` 0x060a/0x060b, `DCSURF_FLIP_CONTROL` 0x061b (bit 8 `SURFACE_FLIP_PENDING`) and
  `DCSURF_SURFACE_INUSE` 0x0620/0x0621.
- The new code logs them as a read-only cross-check.

Writing HUBP registers behind DC's back is possible in principle, but it would not work here:
- there is no second scan-capable buffer to point HUBP at (no spare VRAM, and no GART entry for any IOSurface);
- DC would overwrite the address on its next commit;
- so it was rejected.

## 3. Memory: what DCN can scan here

- **VRAM carve-out.** Linear XRGB8888 2880x1800 with pitch 11520 (45 x 256 bytes) is what DCN scans today, from a
  `VRAM_CONTIGUOUS` dumb buffer. Two more such buffers (2 x 20.7 MB) from the same bridge call work without any DC
  configuration change. NMXAccel cannot allocate them itself.
- **GTT (system memory through the GART).**
  - Linux scans out of GTT by default on APUs ("sg display").
  - It needs `adev->mode_info.gpu_vm_support = true` at DM init. `amdgpu_display_supported_domains` only adds GTT
    when that is set and the BO has `AMDGPU_GEM_CREATE_CPU_GTT_USWC`.
  - `dm_plane_helper_prepare_fb` pins with those domains and does `amdgpu_ttm_alloc_gart`.
  - The IOSurfaces are linear, page-aligned, with pitch 11520 (256-byte aligned) and format BGRA = DRM XRGB8888.
    The later 10-bit `l10r` format is DRM XRGB2101010, which DCN also scans natively.
  - So the composite target itself can be scanned, with zero copies, once its pages are an sg BO in the GART and DC
    runs with GPU VM on. That needs NMXGPU changes (section 4).

## 4. Design

### Chosen: zero-copy scanout of the composited IOSurface (mode 1), with copy+flip (mode 2) as a stepping stone

- **Mode 1, zero copy.**
  - NMXGPU imports CoreDisplay's IOSurface pages as a GTT scan-out buffer, once per surface (cached: the chain is
    3-4 surfaces).
  - Each frame, after the fence, NMXAccel asks for a vblank-latched flip to that surface.
  - No CPU copy, no beam wait, no GPU copy.
  - WindowServer's composite is what the panel shows.
- **Mode 2, copy + flip.**
  - NMXGPU allocates two more VRAM buffers like the one it has.
  - NMXAccel copies into a back buffer (unpaced, because it is off screen) and flips to it.
  - This keeps the CPU copy but removes the beam wait and all tearing logic.
  - The NMXGPU change is smaller (no DC configuration change), so it can land first.

Why not the other shapes:
- **Rotating several `initFramebufferResource` buffers.** CoreDisplay never renders into them. It renders into its
  IOSurfaces, so this needs a copy anyway.
- **SDMA blit into a VRAM chain.** This also needs the IOSurface in the GART, and adds ~1 ms of GPU time plus 41 MB
  of memory traffic per frame. The direct scan has neither.

### Ordering and tearing safety (NMXAccel side)

performTransaction with `debug.nmxaccel_flip` = 1 or 2 runs these steps:

1. **Fence.**
   - `nmxFenceWait` as today: sleeps until `NMXFenceDone >= NMXFencePending`, capped at 100 ms. It now returns false
     on the cap.
   - A frame whose wait timed out is **never flipped**. It takes the copy path.
2. **One flip in flight.**
   - If the previous flip has not latched, perform waits for it, up to 20 ms.
   - If it still has not latched, the frame is dropped (`flip_drop`). It is never queued behind a pending flip.
3. **Generation.**
   - If the bridge put its own buffer back (display power, restore, hotplug), NMXAccel resyncs to what is really on
     screen (`flip_generation`).
4. **Flip.** `nmxFlipSubmit(handle)`. DC programs the HUBP address with `SURFACE_FLIP_TYPE` = vsync, so the switch
   happens only in the vertical blank and every refresh shows exactly one whole frame.
5. **Completion = latch.**
   - The transaction is complete only once the display has latched the flip.
   - In async mode (default), performTransaction returns at once and `isTransactionComplete` reports false. A thread
     call polls `nmxFlipStatus` every 200 µs (cap 50 ms), then calls `signalTransactionInterrupt(pipe)`. This is the
     shape the NVIDIA build's `nvaccel_iop_async` used.
   - `debug.nmxaccel_flip_sync=1` waits inside performTransaction instead.
   - Because completion means "on screen", the family's live transaction, the one whose surface is still being scanned,
     is retired only when its replacement is visible.
6. **Safety net for the surface on screen.**
   - NMXAccel records the on-screen surface's `NMXFencePending` at the flip.
   - If it grows while the surface is still on screen (CoreDisplay committed GPU work into it), the event is counted
     (`flip_front_written`) and logged.
   - After 16 such events, zero copy turns itself off.
7. **Fallback.**
   - Any refusal or unsupported frame takes the K6 copy.
   - If the home buffer is not on screen, the frame is first copied into it while it is off screen (no pacing), then
     NMXAccel flips home and waits for the latch.
   - Later frames use the paced K6 copy exactly as before.
   - Flips turn off for the boot (`debug.nmxaccel_flip_tripped=1`, write 0 to re-arm) after any of these:
     - 8 consecutive failures;
     - a 50 ms latch timeout;
     - a failed home flip;
     - a failed status call.

With `debug.nmxaccel_flip=0` (default), the new code costs one branch per frame and never calls NMXGPU.

### Run-time switches and counters (NMXAccel `ci/nmxaccel-flip`)

| sysctl | |
|---|---|
| `debug.nmxaccel_flip` (RW, 0) | 0 = K6 copy, 1 = zero copy, 2 = copy + flip |
| `debug.nmxaccel_flip_sync` (RW, 0) | 1 = wait for the latch inside performTransaction |
| `debug.nmxaccel_flip_api` (RD) | NMXGPU flip caps; -1 = not asked yet (asked on the first frame with flip on), 0 = no API |
| `debug.nmxaccel_flip_tripped` (RW) | 1 = turned itself off; write 0 to re-arm |
| `debug.nmxaccel_flip_{submitted,latched,fallback,refused,timeouts,home,imports,import_fail,front_written,wait_us,same,drop,generation,hw_mismatch}` (RD) | counters |

Turn on with `sudo sysctl -w debug.nmxaccel_flip=1` (or `=2`). Turn off with `=0`: the next frame copies into the home
buffer and flips home. Log lines start with `iop: flip:` (48-line budget) and include HUBP0 address and in-use readback.

With today's NMXGPU, turning it on logs `NMXGPU flip API MISSING`, sets `flip_api` to 0, and nothing else changes.

Build:
- fork commit 37493db on `ci/nmxaccel-flip`, on top of a24692f;
- CI run 41676848764;
- artifact `~/ga403-logs/step97/ci/NMXAccel.kext`, binary sha256
  `bf7c7ea8c233d22a89ecc6395ddc8508fbdcbd9bc77865c657eff1ab38247944`;
- `NMXDisplayPipeEnabled` is true, as in the earlier CI builds.

## 5. NMXGPU-side requirement (not implemented; NMXGPU must not be touched by this step)

Where it hooks:
- `NMXAMDFB::callPlatformFunction` in xkpi `xnu/nmx_fb.cpp`, next to `nvScanoutInfo`;
- the work goes into new functions in `override/src/nmx_fb_bridge.c`, which already owns the DRM client, the
  modesets and the home buffer.

Every call takes one request struct (`kexts/NVRM/nmx_flip_abi.h` in the fork, ABI version 1) as `param1`. Unknown
names must keep returning `kIOReturnUnsupported`, because that is the feature detection. Handle 0 is the home buffer.

| call | does |
|---|---|
| `nmxFlipCaps` | caps bits: SUBMIT (1), IMPORT (2), VRAM_CHAIN (4), XRGB8888 (0x100), XRGB2101010 (0x200). Also the mode's width/height/pitch, max imports, and generation. |
| `nmxFlipBuffers` (mode 2) | Up to 2 more `drm_client_framebuffer_create(client, w, h, XRGB8888)`, each with the same contiguity check and vmap as `nmx_fb_open`. Returns `{phys, kva, size, pitch, gpuAddr = amdgpu_bo_gpu_offset, handle}` per buffer; buf[0] is home. |
| `nmxFlipImport` (mode 1) | In: a prepared `IOMemoryDescriptor *`, offset 0, width/height/pitch/format. Builds an sg_table from the descriptor's physical segments (`getPhysicalSegment(..., kIOMemoryMapperNone)`; the Step92 userptr pin path already turns descriptor pages into TTM pages). Creates a `ttm_bo_type_sg` amdgpu BO with `AMDGPU_GEM_CREATE_CPU_GTT_USWC` (required by `amdgpu_display_supported_domains`). Pins it in GTT and runs `amdgpu_ttm_alloc_gart`. Then `drm_gem_handle_create(client->file, ...)`, and `drm_internal_framebuffer_create` with `DRM_FORMAT_MOD_LINEAR`, `pitches[0]` = IOSurface row bytes and `DRM_MODE_FB_MODIFIERS`, as `drm_client_buffer_addfb` does. Returns the handle and `gpuAddr`. |
| `nmxFlipRelease` | `kIOReturnBusy` if the handle is current or pending. Otherwise: fb put, GEM handle delete, unpin, unref. NMXAccel completes and releases the descriptor only after this succeeds. |
| `nmxFlipSubmit` | Non-blocking atomic commit that only swaps the primary plane's fb on each CRTC the bridge lit. Steps below the table. |
| `nmxFlipStatus` | Never sleeps: `seqSubmitted`, `seqLatched`, `current`, `pending`, `generation`, `drm_crtc_vblank_count` and time. |

`nmxFlipSubmit` steps:
1. `drm_modeset_acquire_init`, `drm_atomic_state_alloc`.
2. `drm_atomic_get_plane_state(crtc->primary)` and `drm_atomic_set_fb_for_plane`.
3. `drm_atomic_get_crtc_state`, so the commit tracks flip_done.
4. `drm_atomic_nonblocking_commit`, with `-EDEADLK` backoff.
5. Take a ref on the CRTC's new `drm_crtc_commit`. Its `flip_done` completing means "latched".
6. Return `seq`.

`nmxFlipSubmit` constraints:
- Refuse with `kIOReturnBusy` while the previous flip is not `flip_done`.
- Must be callable from a sleeping-capable kernel thread (the IOAcceleratorFamily workloop or a thread call).
- **Do not** change the client modesets' `ms->fb`. Restore, hotplug and display power must keep committing the home
  buffer, and must bump `generation` (in `bridge_restore`, `bridge_hotplug`, `nmx_fb_power`).
- A pure address swap with the same format, size and pitch is DC `UPDATE_TYPE_FAST`: `dc_update_planes_and_stream`
  with a flip address latched at vblank, and `dm_pflip_high_irq` completes the event.

Mode 1 also needs one boot-time change:
- DM must be initialised with GPU VM on: leave `amdgpu_sg_display` at -1 in `nmx_fb_before_attach`.
- `nmx_fb_open` must still get a VRAM-contiguous home buffer. With sg display on, the dumb buffer would be placed in
  GTT on an APU with a small carve-out, and the contiguity check would fail. A minimal way: clear
  `adev->mode_info.gpu_vm_support` around `drm_client_framebuffer_create`, then set it back.
- This turns on DC's host-VM path (`is_hvm_enabled`). That is Linux's default on Strix, but it is a change to the
  boot-critical display bring-up, and it must be tested on its own boot.
- Mode 2 needs none of this.

## 6. Expected savings

| | fence | beam wait | copy | present path (serial) | kernel CPU |
|---|---|---|---|---|---|
| today (K6) | 4.0 ms | 2.2 ms | 3.2 ms | ~9.4 ms | ~28% kernel_task |
| mode 2 (copy+flip, async) | 4.0 ms | 0 | ~3 ms (unpaced, to VRAM over the BAR) | ~7 ms | copy only |
| mode 1 (zero copy, async) | 4.0 ms | 0 | 0 | ~4 ms + ~50 µs of calls | the 200 µs status polls |

In async mode the vblank wait is off the serial path: the transaction completes at the latch, and WindowServer can
encode the next frame meanwhile. Mode 1 should make 120 Hz reachable if the GPU's ~4-5 ms composite fits. In sync mode
performTransaction sleeps up to one refresh (on average half of one, ~4.2 ms) but still does no copy.

## 7. Risks and unknowns, stated plainly

- **CoreDisplay writing into the surface on screen.**
  - Zero copy is safe only if CoreDisplay reuses a chain surface after the family retires the transaction that
    showed it. The family's symbols (`releaseLiveTransaction`, `get_finished_transactions`) suggest that model.
  - It has not been verified for this family on this OS, and the async completion was never proven on the AMD pipe.
  - If CoreDisplay does write the surface on screen, that refresh tears or shows half-drawn pixels. Nothing crashes.
  - `flip_front_written` counts it, and 16 events turn zero copy off.
  - A chain of only 2 surfaces would make it likely. The logs show 3-4.
- **Lost interrupts (H2, the 23:09 boot).**
  - Flip completion relies on DCN's pflip interrupt through the IH.
  - With interrupts lost, nothing latches as far as DRM knows. NMXAccel times out after 50 ms and trips back to K6.
  - The home flip is a DRM commit too, and the commit worker can block up to 10 s in `wait_for_flip_done`. So the panel
    could freeze on the last flipped frame until interrupts recover.
  - The IH self-heal poll (Step96 next item 1) should cover the DCN pflip source as well.
- **Coherency of system-memory scanout.**
  - DCN reads system memory without snooping.
  - GPU-written pixels are in DRAM once the fence signals (NVMTL marks done after completion).
  - Pixels the CPU wrote into a display surface with write-back caching could be stale on screen until evicted.
  - The WindowServer GPU compositor should not do that. If it does, NMXGPU's import would need a `clflush` of the
    surface per frame, ~1-2 ms but still less than the copy.
- **Wired memory.** Each imported surface stays wired while cached: up to 4 x 20.8 MB. An import that NMXGPU refuses
  to release is left wired on purpose, rather than unwiring pages DCN may still fetch.
- **Chain larger than 4 surfaces.** Imports would churn (one import per frame). The cache size is 4 and is visible in
  `flip_imports`.
- **Format changes.**
  - BGRA and l10r imports use different DRM formats, so the first flip after a change is a DC full update, not a fast
    one. It is slower but still latched.
  - Flipping home (XRGB8888) from an l10r surface is the same.
- **ODM / pipe split.** At 2880x1800@120 DC may combine two HUBPs. Only HUBP0 is read back, as a diagnostic.
  `flip_hw_mismatch` may then count harmless differences.
- **performTransaction context.** The status and submit calls must not sleep for long while the family's gate is held.
  The spec requires status never to sleep, and submit to be non-blocking.
- **Not tested on hardware.** Rules for this step: no GPU tests, no sysctl changes on the live desktop. The CI build
  compiles, and the default (0) path is unchanged apart from one branch.
