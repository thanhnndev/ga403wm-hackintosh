# CPU thermals on macOS: why the HX 370 runs hot, and the fixes

2026-11-08, macOS 26.7.2 (25G332), boots of 11:24, 11:33 (Step130) and 11:46 (Step130c). AC power, ASUS profile Turbo.
Sensors: `debug.amdcppc.sensors` (Tctl from SMN 0x59800 like k10temp; package power from the RAPL energy counter),
`debug.amdcppc.freq` (APERF/MPERF per CPU), `powermetrics --samplers interrupts,tasks`, `spindump`, NMXAccel counters.

None of these runs were a true idle: this Claude session was streaming and Spotlight was reindexing after each boot.
The numbers are the load the owner sees in daily use, not an idle floor. Re-measure the idle floor with the screen
static and no app animating after the fixes.

## Measured

| What | Value |
|---|---|
| Package power, light load (~1.1-3 cores busy in total) | 26-45 W, Tctl 70-80 °C (fans 4700/4900 rpm) |
| Same load, EPP 128 instead of 0 (A/B, policy daemon paused) | 37 → 22 W and 26 → 16 W, Tctl ~75 → ~62 °C |
| Clock while busy at EPP 0 / EPP 128 | ~3.5 GHz / ~2.6-2.7 GHz (busy-weighted), Zen 5 cores up to 5.0 GHz |
| WindowServer | 47-58 % of a core |
| kernel_task | 29-33 % of a core, ~5,800 interrupt wakeups/s |
| NMXDisplayPipe kernel thread (spindump, 5 s) | 0.82 s CPU = 16 % of a core, the largest kernel thread |
| 890M frames CPU-copied to scanout | ~92-111 frames/s, 20.7 MB each (2880x1800x4) = 1.9-2.3 GB/s memcpy |
| `nmxaccel_beam_copy_us` (copy + scan-line waits) | 3.3 s per 10 s (11:33 boot), 7.4 s per 10 s (11:46 boot) |
| Hardware flips | `flip_tripped 1`, `flip_import_fail 8`, `flip_submitted 0` on both Step130 boots |
| IPIs | 2,900-7,700 per CPU per s, ~120,000/s in total |
| Local timer interrupts | ~1,100/s on even CPUs, ~230/s on odd |
| I2C controller A (VoodooI2C touchpad, `-vi2c-force-polling`) | 10,000 IRQs/s on CPU 0 |
| 890M (VGA vector) | ~1,085 IRQs/s |
| RTX 5060 | PCI power state 2 (D0) all the time, NVRM power state 1, 4 NVRMDisplay heads |
| Assertions | coreaudiod PreventUserIdleSystemSleep for rogaudiod's output engine (always running), Electron (Claude) NoIdleSleep |

## Causes, ranked

1. **No CPU idle driver: every idle core only does HLT (C1).** `machine_idle()` in this kernel (checked in
   `/System/Library/Kernels/kernel`) calls `pmDispatch->MachineIdle` (offset 0x10) when set, else `sti; hlt; cli`.
   On AMD nothing registers MachineIdle (StrixS0ix registers only `pmCPUHalt`, for system sleep), so an awake core
   never power-gates into CC6 and the package never idles deeply. Linux (`acpi_idle`) and Windows use the firmware
   `_CST`: C1 MWAIT, C2 IO 0x414 (18 µs), C3 IO 0x415 (350 µs), both CC6. With ~120k IPIs/s and HLT, every core also
   wakes thousands of times per second at full voltage. This is the main reason the idle floor is high; it costs the
   most at idle and light load.
2. **The 890M's hardware flip is off, so every frame is copied by the CPU.** NMXGPU's flip import fails ("NMX flip:
   import failed at descriptor page (0)", refused 0xe00002bc) for the first 8 surfaces, NMXAccel trips flips off for
   the boot, and every WindowServer frame takes the K6 beam copy: 20.7 MB per frame at ~100 fps keeps one core busy
   and the memory controller streaming ~2 GB/s, so the SoC cannot drop the fabric/memory clocks. On the Step99 boot
   zero-copy (mode 1) worked: beam and copy 0, kernel_task 29 → 22 %. So **yes, the 890M work is involved**, but as a
   regression of the flip path on the source-built NMXGPU (Step129+), not because of the GPU port as such.
   WindowServer's own ~50 % follows what apps draw (the Claude window streaming here).
3. **ASUS profile Turbo → EPP 0.** `com.itlmt7925.AmdCppcPolicy` maps profile 1 (Turbo) on AC to EPP 0 (maximum
   performance), so any short burst runs at up to 5 GHz. Measured: EPP 128 saves ~40 % package power (−10 to −15 W)
   and ~13 °C at the same load. This matches Linux: power-profiles-daemon "performance" also writes EPP 0; Windows
   Turbo is the same. Balanced (Performance in RogControl) gives EPP 128, battery 191, Silent 255.
4. **Interrupt load.** The touchpad I2C controller at 10k IRQs/s on CPU 0 (polling mode, because the touchpad's GPIO
   interrupt is not used), local timers at ~1.1 kHz on half the CPUs, ~1k/s from the 890M. Each one wakes a core
   out of HLT. Smaller than 1-3 but it keeps CPU 0 from ever idling. The main session links the 11:19 panic (CPU 0
   stuck in the APIC handleInterrupt path, docs/890M-TRACE.md) to this same 10k/s I2C load on CPU 0, so fixing the
   touchpad interrupt mode is also a stability item, not only a power one.
5. **RTX 5060 never leaves D0.** It sits on the shared heat pipes. D3cold needs `\_SB.PCI0.GPP9.PG00._OFF` (SSDT-5
   "OptRf2"), and NVRM has no runtime power management. Not changed here (ACPI and NullMoth are the owner's call).
   No dGPU telemetry is exposed (no power/temperature sysctl from NVRM), so its share is not measured.
6. **Audio engine always running.** rogaudiod keeps the HDA output engine open (coreaudiod 1.5-3 %, rogaudiod 0.8 %,
   and a PreventUserIdleSystemSleep assertion). Small.

Not causes: no hypervisor (`kern.hv_vmm_present 0`) and no VM running; no CPU hog daemons (rogaudiod, rogkeyd,
RogControl, TapGuard, auxguard, AmdCppcPolicy are each < 1 %); Spotlight (mds_stores 2.1 GB of writes) only for the
first ~10 minutes after a boot.

## Fixes

| # | Fix | State | Expected effect |
|---|---|---|---|
| 1 | StrixS0ix 0.1.14: `MachineIdle` hook. Per-CPU predicted idle (average of the last idle lengths); < 40 µs HLT, else `_CST` C2 (CC6); mode 2 adds C3 for ≥ 2 ms when PM1 BM_STS is clear (Linux `acpi_idle_bm_check`). IO C-state read with IF=0, then `sti; nop; cli` takes the waking interrupt; ARAT keeps the APIC timer running in CC6. Loads in mode 0 (= stock HLT), switched live with `s0ix-set idle 1/2`, statistics in `S0ix,IdleStats`. | built, `scripts/macos-install-s0ix-idle.sh` (AuxKC relink), not installed: needs the main session's next reboot | idle cores power-gated; several W lower idle/light-load package power, lower Tctl. Measure with `s0ix-set idle 0/1/2` A/B on one boot. |
| 2 | Restore the zero-copy flip: find why `nmxFlipImport` now fails at the descriptor page on the source-built NMXGPU (Step129+); meanwhile mode 2 (VRAM chain, beam 0 on the Step99 boot) could be tried with `debug.nmxaccel_flip=2` + `debug.nmxaccel_flip_tripped=0`. | main session (NMXGPU/NMXAccel are theirs) | removes ~2 GB/s memcpy and 15-70 % of a core in kernel_task |
| 3 | Daily profile Performance (EPP 128) instead of Turbo, or a Turbo EPP that is not 0 (e.g. 64) in AmdCppcPolicy. | owner's choice | −10 to −15 W, −13 °C at light load (measured) |
| 4 | Touchpad: GPIO interrupt instead of `-vi2c-force-polling` | later; needs AMD GPIO interrupt work in VoodooGPIO | CPU 0 can idle |
| 5 | RTX D3cold through `GPP9.PG00._OFF` when nothing uses the dGPU | owner decision, ACPI + NullMoth | several W at idle, cooler shared heat pipes |

How to verify after fix 1 (same boot, same load, root):
```
sudo build/s0ix-set idlestats reset; sysctl -n debug.amdcppc.sensors   # then 60 s later:
sysctl -n debug.amdcppc.sensors; sudo build/s0ix-set idlestats show; ioreg -r -c StrixS0ix -d1 | grep IdleStats
```
Run that for `idle 0`, `idle 1`, `idle 2`. Safety: `idle 0` returns to the stock path at once; boot-arg
`-s0ixidleoff` leaves the hook out.

## Best practice: what asusctl and G-Helper do

Sources read on 2026-11-08: asusctl 321b111 (gitlab asus-linux/asusctl), G-Helper 49dbbe1 (github seerge/g-helper).

| | asusctl (Linux) | G-Helper (Windows) | AmdCppcPolicy here |
|---|---|---|---|
| Silent / Quiet (policy 2) | EPP `power` (255) | overlay "Best Power Efficiency" | 255 |
| Performance / Balanced (policy 0) | EPP `balance_power` (191) | overlay "Balanced" | **128 → 191** (rog-control-macos branch `cppc-epp-asusctl-defaults`, installed) |
| Turbo / Performance (policy 1) | EPP `performance` (0) | overlay "Best Performance" | 0 |
| Default profile | Performance on AC, Quiet on battery (`platform_profile_on_ac/battery`) | last mode chosen per power source | RogControl: last mode per source |
| CPU boost | not touched | not touched by default (`auto_boost` -1) | not touched |

asusctl links EPP to the profile by default (`platform_profile_linked_epp: true`, asusd/src/config.rs). So Turbo with
EPP 0 is what both tools do too, and they still idle cool: on Linux and Windows the idle cores sit in CC6 between
bursts, which macOS on AMD does not do yet (cause 1). The profile mapping is a smaller lever (cause 3); the idle
driver (fix 1) is the part that makes Turbo behave like it does on Linux/Windows.

## After the Step131 reboot (12:14 boot: NMXGPU out-11 + StrixS0ix 0.1.14)

- **Flip fixed** (out-11, PAGE_MASK in `nmx_fb_bridge.c`): `flip_tripped 0`, `import_fail 0`, 10 imports, every frame
  submitted and latched in hardware, `beam_copy_us` stays 0. kernel_task ~30 % → ~19 % of a core. Cause 2 is gone.
- **Idle hook works**: in mode 1 the cores spend ~90 % of their time in `_CST` C2 (CC6), e.g. 1.0 M C2 entries and
  506 CPU-seconds of C2 per 25 s phase over 24 CPUs; HLT drops to ~1 %. Mode 2 also enters C3, but PM1 BM_STS demotes
  it often (5-7k of ~25k tries per 30 s). No hang, no visible lag in 6 mode switches.
- **Package power did not drop measurably yet.** Alternating 0/1(/2) on the same boot, 25-40 s per phase:

  | Run | mode 0 | mode 1 | mode 2 |
  |---|---|---|---|
  | chat streaming, round 1 / 2 / 3 | 25.3 / 39.6 / 14.9 W | 24.9 / 34.0 / 15.1 W | 22.7 / 30.3 W |
  | hands off, 3 pairs (12:33-12:36) | 25.2 / 21.4 / 26.9 W | 26.8 / 23.5 / 24.9 W | - |

  The "hands off" run was not idle: the screen still updated 80-110 frames/s and WindowServer used 57-95 % of a core,
  because Microsoft Edge was playing video (Edge helper 41 %, VTDecoderXPCService 6 %; the edge-video-lag session's
  test), plus Chrome and the Claude GPU process (39 %). Under that load the package is held up by the SoC
  (890M compose and video decode, display, memory), not by the cores, so C1 vs CC6 makes little difference.
- Profile was Balanced (EPP 191) for these runs.

Still to do: a true idle run (no video, no app animating, display on), same script
(`idle-clean.sh`: alternates `s0ix-set idle 0/1`, logs Tctl, package power, frames/s, WindowServer %CPU, idle
residency). Expected: the mode 1 gain shows up there, where cores are idle >95 % of the time. The machine is left in
idle mode 1 for this boot (boot default stays 0 until the idle run confirms it).

## Idle A/B and the real cost: WindowServer per frame (18:00–18:40, 2026-11-08)

**True idle** (`tools/idle-attrib.sh`, run detached, hands off, nothing animating): 5.5 W package, Tctl 47 °C,
2–3 frames/s, WindowServer 1 %. The earlier "10 W idle" was the Claude app's spinner keeping the screen at ~80
frames/s. ReportCrash at 11–13 % was the bluetoothd crash loop (handed to the BT session).

**Idle mode A/B** (`tools/cpu-idle-ab.sh`):
- 18:05, steady 80 frames/s, CPUs 95 % idle: modes 0, 1 and 2 all read 9.9–10.1 W.
- 18:15: unusable, because another session started (69–120 frames/s, 14→27 W drift).
- No gain is shown at this load. The boot default stays 0. True idle is not compared yet.

**Why a small animation costs 5–20 W.** The Claude app only redraws a spinner and new text; its own processes
use ~40 % (normal for Electron). WindowServer, however, uses 78–94 % of a core at 75–100 frames/s: 7.0 s user
and 2.4 s system per 10 s. That is ~5 ms of compositor CPU per frame, against ~1 ms on a real Mac.

`sample WindowServer 10` (root, ~100 frames/s, 1.33 ms per sample; the main thread is 66 % busy) gives this
per-frame split:

| Path (inclusive, main thread) | samples | ≈ ms/frame |
|---|---|---|
| `CDDisplay::render_update` (whole composite) | 3660 | 4.9 |
| `CA::OGL::render` (layer encoding through NVMTL → RADV) | 2938 | 3.9 |
| vibrancy / backdrop blur (`render_vibrant_color_matrix`, `capture_in_place_backdrop`, blur) | ~900 | 1.2 |
| `commitAndWaitUntilSubmitted` (synchronous submit, `cs_submit` ioctl) | 585 | 0.8 |
| `newTextureWithDescriptor:iosurface:` → `nvmtl_vk_buffer_import_host` → `amdgpu_create_bo_from_user_mem` + VA map | 532 | 0.7 |
| `CoreDisplay::Display::Present` | 349 | 0.5 |
| `nvmtl_prefault_write` | 210 | 0.3 |

Worker threads also spend ~2.9 s per 10 s blocked in `drmSyncobjWait`, called from `nvmtl_vk_submit_finish` via
`nvmtl_pump_buffers`. That time is blocked, not burning CPU. Short-lived workqueue threads account for about half
of WindowServer's CPU time: thread create/exit churn from the pump.

**Fixable items (all in the NVMTL WindowServer plugin, owned by the main session):**
1. **IOSurface import on surface keep misses.** The live plugin (`nmx-plugin-camcopy` cb1a5e6) already caches
   imports ("surface keep"). The 0.7 ms/frame is the miss path: `nvmtlNewSurfaceTexture:` → `nvmtl_prefault_write`
   (210 samples, a write fault per page) plus `nvmtl_vk_buffer_import_host` (240, userptr BO + VA map). That comes
   to roughly 10 misses/s, each costing a few ms. The 30 s reports show where they come from: new surfaces (20–25
   per 30 s), "same surface other key" (14), expired (6–20), and idle-cap drops of Electron tile surfaces
   (1472×256, 768×64, 320×64) after ~28 s idle that come back within 40–200 ms. Handed to the edge-video-lag session,
   which owns surface keep.
2. **Synchronous commit.** `commitAndWaitUntilSubmitted` blocks the compositor main thread on the submit
   (0.8 ms per frame).
3. **Pump thread churn.** Fence waits run on fresh dispatch workqueue threads. One long-lived waiter thread
   would avoid the create/exit cost.
4. Structural: every Metal call is translated to Vulkan on the CPU (encoder binds, sampler pipelines, snapshot
   and resref bookkeeping). This is the bulk of the remaining 3.9 ms, and only shrinks with translator work.

kernel_task at ~30 % during animation is not profiled yet. It needs a kernel profile (`spindump` or kperf),
which is a separate step.

## Root cause of the IOSurface import cost: AMD surfaces are not GPU resources (trace 2026-11-08 19:00)

Surface keep (the per-process cache) only lowers how often the cost is paid. The cost exists because on the 890M an
IOSurface never becomes a GPU resource in the kernel.

**NVIDIA path (upstream NullMoth, "item 7"):**
- `NVAccel::resourceTypeForIOSurface` lets IOAcceleratorFamily2 build a per-surface device cache
  (`IOGraphicsAccelerator2::deviceCacheForIOSurface`, an `NVResource` with VRAM).
- The plugin imports it by surface ID (`nvmtl_vk_surface_vram` → NVK `stage_import` →
  `nvAccelSurfVram`: `IOSurfaceRoot::lookupSurface`, device cache, RM share).
- Result: one GPU allocation per surface, shared by every process, and its lifetime follows the IOSurface.

**AMD path (NMX_ACCEL):**
- `resourceTypeForIOSurface` returns 0x80 (`nvrm-accel.cpp`: "UMA IOSurfaces use the family system-memory path";
  "Vulkan/RADV owns execution memory").
- `nvmtl_vk_surface_share_on()` is off, because RADV has no `stage_import`.
- So every process that wraps a surface imports it from its own user mapping:
  `IOSurfaceGetBaseAddress` → `nvmtl_prefault_write` (one page fault per page in that process's fresh mapping) →
  `amdgpu_create_bo_from_user_mem` (userptr: wire the pages through the task's VM map) → VA map.
- It is repeated per process, and again after every surface keep drop.

**Root fix (design, not built):** import IOSurfaces by ID in the kernel, the same shape as item 7.
1. NMXGPU gets an ioctl that imports an IOSurface by ID:
   - Look it up for the calling task with `IOSurfaceRoot::lookupSurface`, which also checks that the task can see it.
   - Take `IOSurface::getMemoryDescriptor` and `prepare()` it once.
   - Export it as a kernel dma-buf whose `map_dma_buf` returns the descriptor's physical segments. The port's
     dma-buf exists (`override/src/nmx_dma_buf.c`); only file descriptors are missing, and none are needed here.
   - `drm_gem_prime_import` it into the caller's DRM file, which returns a GEM handle.
   - Cache one dma-buf per surface, and release it when the IOSurface dies. That release can come from the family's
     device cache if `resourceTypeForIOSurface` stops returning 0x80 for these surfaces.
2. RADV gets a `stage_import` equivalent (a patch next to `radv-nvmtl-surface-list.patch`): during
   `vkAllocateMemory` with the staged record, it calls the ioctl and wraps the returned GEM handle
   (`amdgpu_bo_import`, KMS handle type) instead of an fd.
3. In the plugin, `nvmtl_vk_surface_share_on()` becomes true on AMD, so `nvmtl_vk_surface_vram` is the first path.
   The userptr host import stays as the fallback.

**What it removes:**
- the per-process page faults (210 samples) and the userptr wire (240);
- re-imports after keep drops: a re-wrap becomes a GEM lookup plus a VA map;
- the hundreds of host-pointer BOs per process on the submit BO list (trace parts 7–9).

**What it does not touch:** the Metal→Vulkan encode cost (~3.9 ms per frame) and the synchronous submit. Those
are the next two root causes, each with its own design.

**Risk:**
- Coherency with CPU writes: IOSurface lock/unlock. The userptr path has the same issue today.
- Surfaces mapped read-only (the 23:18 fault): the ioctl must take the access mode from the caller's mapping.

### Step137: IOSurface imports pin the surface's own memory (installed 2026-11-08 20:41, next reboot)

Root fix, step 1. RADV and libdrm do not change: the plugin keeps importing host pointers. The kernel's userptr pin now
takes the IOSurface's pages from the surface itself, instead of faulting the range in through the process's map.

**Kernel: NMXGPU out-18 66db7c2c** (fork `nmx-source-port` 8f9364c, on top of Step136 out-17)
- `patches/amdgpu-nmx-surface-hint.patch`: driver ioctl `DRM_AMDGPU_NMX_SURFACE_HINT` (0x5e,
  `{addr, size, surface_id}`), DRM_RENDER_ALLOW. It records "this task's range [addr, addr + size) is IOSurface N"
  in a 64-entry ring that expires after 2 s.
- `xnu/nmx_mm.cpp` `nmx_xnu_user_wire`: when a hint matches the exact range being wired, the pin goes through
  `surf_wire`:
  - `IOSurfaceRoot::lookupSurface(id, task)`: only a surface that task may use.
  - `IOSurface::getMemoryDescriptor` → `prepare()`, and the pages come from it.
  - The claim is checked first: the range's first page is wired through the process's map, with the access asked
    for, and must be the surface's first page.
  - Any failure falls back to the old user wire. The hint survives a failed attempt, so the read-only retry (Step96,
    WindowServer's r-- client surfaces) still uses it.
- New imports: `IOSurfaceRoot::lookupSurface` and `IOSurface::getMemoryDescriptor`, both already imported by
  NMXAccel and NVAccel (Step128 rule). `com.apple.iokit.IOSurface` was added to OSBundleLibraries.
- Counters: `debug.nmx_surf_{hint,wire,miss,bad_page,no_surf,short,prep_fail}`.
- Boot-arg `nmxsurfwire=0` turns the surface path off.

**Plugin a95189e** (`nmx-plugin-camcopy`, on top of the edge session's 5ba6363 tile keep)
- Before each host import, the plugin sends the hint on its own `/dev/dri/renderD128` fd.
- When the hint is accepted, it faults in only the first page instead of the whole surface.
- On a kernel without the ioctl, the first hint gets EINVAL and the hint is turned off for that process. Tested on
  the live out-17: `surfkeep_test 50` PASS, log `surface hint: refused (Invalid argument), off for this process`.
- `NVMTL_SURF_HINT=0` turns it off.
- Binary `out/NVMTLDriver-surfhint` (7db6968c). It includes the tile keep fix, so it replaces `NVMTLDriver-tiles`.

**Verify after the boot:**
- `sysctl debug.nmx_surf_wire` grows, and `nmx_surf_bad_page` / `miss` stay small.
- The WindowServer sample from 18:30 (Claude app in use; Reduce Motion is on, so not an animation — see the correction at the end): `nvmtl_prefault_write` and
  `amdgpu_create_bo_from_user_mem` should be near 0 under `newTextureWithDescriptor:iosurface:`.
- No gfxhub faults. The Step135 romap print names any read-only mapping that is hit.

**Undo:**
- Plugin: the plugin installer's `--undo`.
- Kernel: `nmxsurfwire=0`, or the Step130 installer `--undo` / reinstall out-17.

Installed 2026-11-08 20:41 (out-17 has been live since the 20:26 boot), loads at the next reboot:
- NMXGPU out-18: UUID 194BFE13, AuxKC relinked and checked. Backup `/Library/NullMoth/step130-bk-20261108T134013Z`
  is out-17.
- Plugin a95189e: UUID 5FC87442. Backup `nvmtl-plugin-20261108T134105Z` is the edge session's tile build.
- strixsbxmap refreshed, stale 0.

Undo:
- Kernel: `sudo scripts/macos-install-step130.sh --undo`, or keep it and boot with `nmxsurfwire=0`.
- Plugin: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.

Review by the edge-video session (2026-11-08): the hint path is correct as written.
- Sandboxed processes (VTDecoderXPCService, com.apple.WebKit.GPU) cannot open `/dev/dri`. The hint is off in them,
  so for now the gain is in WindowServer only. Later step: send the hint through the sandbox-safe DRM path RADV uses
  in those processes.
- A failed surface pin falls back to a plain wire on pages that were not prefaulted beyond the first. That costs the
  Step132 retry, so watch `debug.nmx_surf_miss` after the boot.
- `nvmtl_surface_hint`'s static fd is set without a lock. That is safe while every caller runs under
  `@synchronized(device)`, as they do today.

**Step137 boot (2026-11-08 20:52, out-18 194BFE13 + plugin a95189e)**
- Loaded. WindowServer logs `surface hint: on` and hinted its first import (20 MB). No GPU faults or NMX pin errors.
- `sample WindowServer 10` at 21:00 with the Claude app in use (not animating: Reduce Motion is on), compared with 18:30 (both out of ~7.5–7.9k main-thread samples):

  | WindowServer main thread | 18:30 (before) | 21:00 (Step137) |
  |---|---|---|
  | `newTextureWithDescriptor:iosurface:` | 524 | 67 |
  | `nvmtl_prefault_write` | 210 | 0 |
  | `nvmtl_vk_buffer_import_host` | 240 | 75 |
  | `commitAndWaitUntilSubmitted` | 585 | 403 |
  | `CDDisplay::render_update` | 3660 | 1979 |
  | main thread busy | 66 % | 50 % |

  The import path is down ~87 %, and the per-page prefault is gone. The 21:00 run also includes the tile keep fix.
- The whole-system comparison is not valid yet. Eight minutes after boot, Docker (~150 %), Spotlight indexing and
  a spindump were running, at 40 W and 91 °C.
- The `debug.nmx_surf_*` counters were never registered in out-18 (no `sysctl_register_oid`). Fixed in Step137b,
  nmx-source-port f31cedf, built as out-19 (0DEC255D). It only adds the counters, so it goes into the next batch.
- New lead from the WindowServer log: `pre-submit prologue census: 16384 submits carried 126277 uploads ... 5087922
  KB buffer-texture shadow`. That is ~310 KB of CPU upload per submit for buffer textures, the next hot spot to
  profile.

## Daily load re-baseline: video + Claude + Docker (boot 20:52, 21:15–21:30, 2026-11-08)

Video, the Claude app and Docker running together is normal use on this machine, so this is the load to fix.
On AC: 27–40 W package, Tctl 78–91 °C.

**Where the CPU goes (`top`, 3 s, 21:28):**

| Process | CPU | Cause |
|---|---|---|
| com.docker.backend (two processes) | 95 % (39 min of CPU since boot) | parses ~4,000 HyperKit log lines a second (regex + Go GC) |
| WindowServer | 55–78 % | see the sections above; import path back to ~8 % of the main thread under load |
| com.docker.hyperkit | 54–86 % | its vCPU threads print one line per guest WRMSR |
| mds_stores | 36 % | not traced (possibly the Docker log files rotating every 1–2 s) |
| kernel_task | 22–130 % | memory compression, see below |
| bluetoothd | 14–33 % | LE advertising restart loop, ~15,000 log lines a second |

### 1. Docker: the guest writes MSR 0xC0000502 on context switches and HyperKit logs every write

- `~/Library/Containers/com.docker.docker/Data/log/host/monitor.log` rotates 1 MB every 1–2 s, all of it
  `main.hyperkit: wrmsr to register 0xc0000502(0x1) on vcpu N`: 8,482 lines in 2.15 s, spread over all 24 vCPUs.
  The backend log carries the same lines again.
- 0xC0000502 is `MSR_AMD_WORKLOAD_HRST`, the Zen 5 workload-classification history reset. Linux writes it on task
  switches when CPUID 0x80000021 EAX bit 22 (`X86_FEATURE_AMD_WORKLOAD_CLASS`) is set. The guest is
  7.0.14-linuxkit.
- The host sets that bit (`cpuid 0x80000021`: EAX 0x597fffcf, bit 22 = 1). RyzenHV's HyperKit CPUID clean-up
  (`kext/Source/HvFrontend.cpp`, `tVcpuRun`) handles leaves 0x80000001, 0x80000008 and 0x80000026, but not 0x80000021,
  so the guest sees the feature. HyperKit does not emulate the MSR, so every write goes to user space and prints.
- `sample com.docker.hyperkit 5`: `vmexit_wrmsr → fprintf` has 2,830 samples, more than `hv_vmx_vcpu_run` (1,556,
  which includes guest run time). Most of those are vCPUs waiting on the stderr lock, so guest threads stall too.
- Fix (RyzenHV, owned by the ryzenhv session; reported, not patched here): clear 0x80000021 EAX bit 22 in the
  HyperKit fix-up, or treat the MSR write as a no-op in the kernel. Either removes the exits, the log lines,
  the backend's parsing and the log churn. Expected saving: most of the backend's ~1 core plus part of HyperKit.
- Separate: RyzenHV counts ~26,000 NPT faults a second with all 2,097,152 guest pages already mapped. HyperKit's
  MMIO paths (`vmexit_inst_emul`, `emulate_mem`) are nearly absent from the sample, so these are not user-space
  MMIO. They need an exit-reason trace in RyzenHV (ryzenhv session).

### 2. Memory pressure drives kernel_task (with docs/890M-TRACE.md part 26)

- 20.0 GB of 32 GB is wired: RyzenHV 8.42 GB (Docker's 8 GB guest, wired in full), NMXGPU 5.80 GB, zones 2.81 GB,
  PTE+PMAP 0.9 GB, IOSurface 314 MB. No swap.
- kernel_task's CPU is VM_compressor (two threads), VM_pageout_scan and VM_cswap_trigger: 9.6 s of 13.3 s per 10 s
  in the 21:16 spindump. The rest is USB XHCI threads (~1.3 s) and NMXIrq (0.18 s).
- Part 26 found the NMXGPU fictitious page-record leak (`nmx_phys_to_page`, records never freed) and
  `kalloc.type.var4.256` growing during playback. That is the main session's fix.
- Docker's VM size is the owner's call. With RyzenHV wiring guest RAM, a 4–6 GB VM gives macOS 2–4 GB back.

### 3. bluetoothd: LE advertising fails and is retried with no back-off

- `log stream --process bluetoothd` for 5 s: 74,872 lines. About 140 times a second, `Server.LE.Advertise` starts
  the four Continuity instances (Apple types 16, 9, 18), the stack answers `multipleAdvStartCb Could not start
  advertising : STATUS 718 (status=65535)` / `failed to start advertising instance 1 ... Abort`, and the server
  starts again at once. Each round also dumps the full advertising-set parameters.
- `system_profiler`: Transport UART, Chipset THIRD_PARTY_DONGLE. status 65535 looks like no HCI status came back,
  so the controller (or the UART path) does not answer the extended-advertising enable for instance 1.
- The two busy threads (0xd67 HCI receive, 0xd66 run loop) used 1.8 s of CPU in 10 s, mostly short wakeups.
- Fix belongs to the Bluetooth work (MtkBtFw / mt7925-macos): find the HCI command that fails for instance 1
  (PacketLogger or the MtkBtFw HCI log), then either make the controller accept it or report fewer advertising
  sets so bluetoothd stops asking. A quick user-side test: turn off Handoff and AirDrop and see whether the loop stops.
- The USB XHCI kernel threads in kernel_task may be the same loop if the UART path runs over USB. Not checked.

### Not done yet

- powermetrics interrupt and wakeup data (needs root; the 21:15 run failed on a bad flag).
- mds_stores cause (needs `fs_usage` as root).
- Whether WindowServer's imports under load are hint misses: needs the out-19 counters.

### kernel_task without memory pressure (21:16 spindump, 13.3 s of CPU in 10 s)

- VM threads (2× VM_compressor, VM_pageout_scan, VM_cswap_trigger): 9.6 s. The cause is the wired memory above;
  the NMXGPU leak is Step138 (a1c786c, video/main session) and the 5.8 GB NMXGPU tag is theirs too.
- Everything else is ~3.7 s, about 0.37 of one core:
  - USB XHCI threads 1.34 s. XHC0 0.36 s and its USB2 port 0x00300000 0.32 s (the UGREEN mouse dongle, so input
    while moving the mouse). XHCI@81000000 0.27 s (ASUS FHD webcam bus; check whether the camera was streaming).
    XHCI@80000000 0.20 s, XHCI@60000000 0.20 s.
  - NMXGPU threads: NMXIrq 0.18, NMXDisplayPipe 0.11, gfx_0.0.0 0.11, dm_vblank_control 0.10, sdma0 0.09,
    linuxkpi_irq_wq 0.07, nmx softclock 0.03 (≈0.7 s together).
  - Three unnamed priority-81 threads 0.65 s, NVMe 0.09, CCFaultReporter 0.08.
- Nothing outside memory pressure needs a fix now. Re-measure after Step138 and a smaller Docker VM.

### Update from the ryzenhv session (2026-11-08)

- The WRMSR fix is RyzenHV 0.7.17 (ryzen-hypervisor.framework b57c8fa, branch research/ga403wm-zen5): the HyperKit
  CPUID fix-up clears 0x80000021 EAX bit 22. Built and tested, not installed; the owner decides. It takes effect for a
  newly booted guest, so restart Docker Desktop after the kext loads. Their flight recorder had 18 % of exits as
  WRMSR ecx=0xC0000502.
- The NPT faults are xAPIC accesses, mostly EOI writes (`mov [APIC fixmap + 0xB0], eax`). HyperKit emulates the
  APIC in user space through EPT violations, as on an Intel Mac without APICv. Not a RyzenHV bug. Making them
  cheaper needs AVIC or x2APIC support in HyperKit, a separate large project.
- After installing: check `monitor.log` no longer shows `wrmsr to register 0xc0000502` and com.docker.backend drops
  from ~95 % CPU.

## Re-baseline on the 21:51 boot (out-20 Step138, RyzenHV 0.7.17, BtLeDlFix 1.3.0), 21:56–22:00

Load: Chrome video, the Claude app, the pathcan backend's python dev server (one full core, another project).
**Docker was not started on this boot** (no hyperkit, RyzenHV `vmCreates 0`), so this is not like-for-like with
20:52 and the Docker fix is not confirmed yet. Starting Docker is the owner's call.

| | 20:52 boot (21:15–21:43) | 21:51 boot (21:56) |
|---|---|---|
| Package power / Tctl | 27–40 W / 78–91 °C | 20–41 W / 79–90 °C (python dev server at 85–100 %) |
| Wired total | 19.2–20.0 GB | 7.68 GB |
| RyzenHV wired | 8.42 GB | 96 KB (no VM) |
| NMXGPU tag | 5.80 → 4.89 GB | 3.07 GB |
| zones | 2.81–2.91 GB | 1.37 GB |
| `kalloc.type.var4.256` | 810 → 860 MB, growing | 12 KB (leak fixed) |
| Compressor / swap | 4–7 GB / 0 | 0 / 0 |
| kernel_task CPU per 10 s | 13.3–21.7 s | 3.4 s |
| of which VM threads | 9.6–16.7 s | 1.2 s |
| WS main thread busy | 50 % (21:00) | 22 % |
| `render_update` samples | 1,979 | 315 |
| bluetoothd | 14–33 % | ~2 % (BtLeDlFix, no STATUS 718) |

- Step137 counters (out-20): `nmx_surf_hint` 886, `nmx_surf_wire` 886, `nmx_surf_miss` 0. Every hinted surface import
  is pinned through the IOSurface path. `nmx_userwire_pages` 555,021 (2.1 GB of user pages pinned at the time),
  `nmx_userrec_kept` 0.
- WindowServer main thread (`sample WindowServer 10`, Chrome video + Claude): the import path is nearly gone
  (`nvmtl_vk_buffer_import_host` 22, `amdgpu_create_bo_from_user_mem` 15 of 8,171). What remains is Core Animation
  layer rendering inside `render_update` (~250), reply `mach_msg` to clients (~190) and voucher disposal (~160).
- kernel_task without VM threads: ~2.2 s per 10 s. USB XHCI threads ~0.96 s, dm_vblank_control 0.13, Wi-Fi
  input 0.12, NVMe 0.11, NMXIrq 0.06.
- powermetrics interrupts (5 s): IPI 51,870/s, timer 14,452/s, NVMe 1,317/s, I2C touchpad (I2CA) 836/s, GPU 334/s.
  IPIs and timers sit mostly on the even CPUs (0, 2, 4, 6: 3.5–5.2k IPI/s each). The IPI rate is the next thing
  to attribute: 52k/s is high for this load.
- Still open: confirm the Docker WRMSR fix once Docker runs (expect no `wrmsr to register 0xc0000502` lines in
  `monitor.log` and com.docker.backend near idle), then measure the full daily mix again. With Docker the wired
  total will add ~8.4 GB for the VM.

## Who sends the IPIs (21:59–22:01, boot 21:51)

Method: `powermetrics --samplers interrupts,tasks` on its own, then a 2 s `ktrace dump -f S0x0140,C0x17,C0x19`
(scheduler, pmap, MP), with each `MACH_SCHED_REMOTE_AST` matched to the `MACH_MKRUNNABLE` just before it on the
same CPU (waker → wakee). Thread names come from the spindump of the same boot.

- **The 51,870 IPIs/s from the 21:56 capture was mostly my own tooling.** Measured with powermetrics alone it is
  26–34k/s; in the ktrace, remote ASTs run at 27.6k/s.
- **There are no TLB shootdowns** (no `PMAP_flush_*` or `MP_TLB_FLUSH` events), so user-page wiring is not the cause.
  Every IPI is a scheduler wakeup of a thread on another core (`MACH_SCHED_REMOTE_AST`).
- IPIs land on the even CPUs (0, 2, … 22: 0.7–4k/s each; odd CPUs ~30/s). Those are the SMT primaries, where the
  scheduler places threads first.

| Waker → wakee | IPIs/s | What it is |
|---|---|---|
| WindowServer ↔ osascript | 5,945 + 5,660 | **measurement artefact**: while an `osascript … with administrator privileges` command runs, osascript and WindowServer ping-pong ~6k messages a second. It also inflates WindowServer's CPU in every root capture. The 47 min of osascript CPU seen at 21:28 was another session's hung prompt doing the same. |
| ItlXhciKick worker → 4 xHCI work loops | 3,657 (≈916 each) | our `ItlXhciKick` (docs/USB-XHCI-LAG.md) signals each AMD xHCI controller every 1 ms. Two of the four (XHC3@60000000, XHC4@81000000) have no USB devices. |
| apps → WindowServer, Claude app and helpers | ~4,000 | normal client/server traffic |
| thread call kernel-high → CCFaultReporter | ~600 | CoreCapture; the only CoreCapture pipes on the system belong to `itlmt7925` (Wi-Fi). Lead for the Wi-Fi owner. |
| NMXGPU threads (linuxkpi_irq_wq, gfx_0.0.0, ttm, NMXIrq, thread call high) | ~1,600 | GPU fence and IRQ work, roughly per frame |
| idle → IONVMeController, mds, corespotlightd, HID | ~1,900 | disk I/O, Spotlight, input |

**Fix for the ItlXhciKick share** (branch `thermal/xhcikick-idle`, 3fd2fb1, built UUID F05A2652, not installed):
a controller with no device in the IOUSB plane is kicked every 16 ms instead of every 1 ms. A hot-plug arrives on
interrupter 0, whose MSI works, and the slow kick covers enumeration until the next 3 s scan marks the controller
busy. Expected: ~1,800 fewer wakeups and IPIs a second. Boot-arg `itlkickidle=<n>`; `itlkickidle=1` = old behaviour.
Installing it means replacing the kext on the ESP (OpenCore), so it waits for the owner and the next batch.

Also seen in the kext: it writes its statistics to NVRAM with `IONVRAM-FORCESYNCNOW` every minute after the first
two minutes, i.e. a forced NVRAM flash write each minute for as long as the machine runs. Worth gating behind a
boot-arg (not changed here).

## Docker fix confirmed, clean IPI count, WindowServer split (22:05, boot 21:51, Docker started by the owner)

**Docker (RyzenHV 0.7.17):** with a freshly booted guest (hyperkit up 2:41, 24 vCPUs), `monitor.log` has
**0** `wrmsr to register 0xc0000502` lines (was ~4,000/s). com.docker.hyperkit uses 3–15 % CPU and
com.docker.backend is no longer in the top 12 (was 95 %). Fixed.

**Clean IPI trace** (root job started through `launchctl submit` 3 s after osascript exited, so no osascript in the
trace): 20,690 remote ASTs/s with Docker running. ItlXhciKick → the four xHCI work loops is 3,631/s (18 %), the
largest single kernel sender. Within user space, hyperkit's vCPU threads wake each other ~1,700/s.

**WindowServer main thread** (`sample WindowServer 10`, same clean start; Claude app in use, Docker up):
7,430 samples, `render_update` 1,950, about half the thread busy. Busy leaf samples by owner:

| Owner | Samples | Detail |
|---|---|---|
| Apple: Core Animation, objc, malloc, CoreFoundation (`render_update` layer walk) | ~1,400 | normal CA cost for the layers on screen |
| **Apple, client-driven: `_XGetRegisteredCursorImages` → `memmove`** | **368** | a client asks WindowServer for every registered cursor image, and WindowServer copies them each time (~5 % of the thread). The requester is not identified: sampling Claude, its helpers and XKey did not catch it. WindowServer's busiest reply target is the Claude app (347 wakeups/s). |
| IOSurface shared-event queries from CA (`IOSurfaceClientQueryTransactionList`) | 162 | Apple's path, triggered per layer image |
| **Ours: RADV CS submit ioctl** | 241 | inherent per frame |
| **Ours: `vkCreateFence` → `vk_drm_syncobj_init` per submit** (`nvmtl_vk_submit_begin_at`) | 95 | a new syncobj for every submit; a fence pool would remove it |
| **Ours: `newTextureWithDescriptor:` (non-IOSurface) → `radv_bo_create`** | 64 + 28 VA ops | a new BO per transient CA texture; a small BO cache in the plugin would remove it |
| **Ours: `__sysctl` in `nvmtlSubmitWithEvent`** | 47 | a sysctl read on every submit; read it once |
| Ours: other plugin + RADV work (state emit, snapshots, btsh notes) | ~330 | |

Our share is ~12 % of the main thread, and three items in it are avoidable (fence pool, texture BO cache,
per-submit sysctl, ~200 samples together, ~2.7 % of the thread). The import path is gone (Step137). The remaining
cost is mostly Core Animation itself plus the unexplained cursor-image requests.

## Correction: no Claude animation; what changes every frame (22:10)

The owner has Reduce Motion on, so the Claude app runs no animations. "Claude animating" in the sections above was
wrong; this is what the traces actually show.

**Who wakes WindowServer** (clean 2 s ktrace, `MACH_MKRUNNABLE` of WindowServer threads by other processes):

| Client → WindowServer thread | Wakeups/s |
|---|---|
| Claude app → main thread (window server messages, cursor queries) | 162 |
| Chrome GPU process → CA render server (CA commits from Chrome) | 50 |
| Claude app → CA render server (CA commits) | 46 |
| HID drivers / kernel → event threads | ~250 |

**The Claude app polls the system cursor on every mouse move.** `sample Claude 8` at 1 ms: 946 samples (12 % of its
main thread) in

`-[NSTrackingArea mouseMoved:]` → Electron → `+[NSCursor(NSDeprecated) currentSystemCursor]` → `SLSCopyRegisteredCursorImages`

and on the server side WindowServer runs `_XGetRegisteredCursorImages` and copies every registered cursor image
(the 368 `memmove` samples, ~5 % of WindowServer's main thread). The cost scales with mouse-event rate over a
Claude window (the UGREEN dongle reports at a high rate). It is Electron/Claude-app behaviour, not ours, and not
fixable on our side; it disappears when the mouse is still or over another app.

**Claude's message rate follows input, not frames:** `top -stats msgsent` every 2 s over 20 s gave 285–2,800
messages/s, moving with its CPU (3.6–37 %). A per-frame animation would be flat. So the `render_update` and Core
Animation cost in WindowServer comes from real content changes: Claude's own redraws while the owner types and
scrolls, its hover/cursor updates while the mouse moves, and Chrome's ~50 commits/s (the video or page in Chrome).

**Corrected WindowServer split** (22:05 sample, 7,430 main-thread samples):
- ~19 % Core Animation layer walk and draw for those real updates (Apple code, driven by Claude input redraws and
  Chrome's commits);
- ~5 % cursor-image copies requested by Claude on mouse moves (Apple code, Claude-driven);
- ~2 % IOSurface shared-event queries by Core Animation;
- ~12 % ours (plugin + RADV + ioctls), of which ~2.7 % is avoidable (fence pool, texture BO cache, per-submit sysctl);
- the rest idle.

Not tested: a run with the mouse still and nothing typed, which would isolate Chrome's commit rate alone.

**Memory with Docker running again:** `top` at 22:11 shows 18 GB wired and 5.3 GB in the compressor, back to the
20:52 pattern minus the NMXGPU leak. The 8 GB Docker VM (RyzenHV wires it in full) is again the main term; the size
is the owner's call.

**ItlXhciKick NVRAM** (branch `thermal/xhcikick-idle`, b862dec, UUID 7BE7395F, not installed): full counters now go to
an `itlz0` registry property on the service. NVRAM keeps the 10 s writes for the first two minutes (early-boot
panics), then is written only when the per-controller health line changes. Before, it forced a flash write every
minute.

## Plugin items from the WindowServer split (branch `plugin/thermal`, fork thanhnndev/nvidia-macos-driver)

`9bfd0c5` on top of camera-copy-890m 9c6d1ed. Built in `~/develop/projects/nmx-plugin-thermal/out/plugin-9bfd0c5`
(UUID 4893C10D), not installed, not run yet.

- **Fence pool** (`nvmtl_vk.c`): `nvmtl_vk_submit_begin_at` took a new `VkFence` on every commit, which RADV turns into
  a DRM syncobj create and destroy (95 of 7,430 WindowServer main-thread samples). Fences now come from a 32-entry
  pool. One goes back only after a successful wait and `vkResetFences`. A failed or timed-out wait still keeps the
  fence out, as before. `NVMTL_FENCE_POOL=0` restores the old behaviour.
- **Fence-wait sysctl** (`NVMTLEventSync.m`): `debug.nmxaccel_fence_wait` was read on every commit (47 samples). It is
  still a runtime toggle, but now read at most once a second.
- **Texture BO cache: not done.** WindowServer already parks images for reuse by exact descriptor
  (`nvmtl_vk_image_park`). At 22:14 it had made only ~128 such textures since the 21:51 boot (42 hits, 86 misses), so
  the 64 `radv_bo_create` samples were a few large allocations of varying size, not per-frame work. Reusing memory
  across sizes would touch the VRAM budget, residency eviction and system-memory spill paths inside WindowServer,
  for ~0.9 % of its main thread. Not worth the risk.
- Build note: `build/build_plugin.sh` builds from `~/nvmtl-build/LIVE` and lacks `-framework IOKit`, which 9c6d1ed
  needs. I built with the same flags plus `-framework IOKit`, using the Vulkan headers from
  `nmx-plugin-890m/out/vk/include` (`~/Vulkan-Headers` does not exist on this machine).

## Boot 23:51 check (plugin 9bfd0c5, ItlXhciKick 5D179C74, StrixS0ix 0.1.15, Wi-Fi 25F33563), 23:55–00:07

Load: Chrome video, Claude app, Docker (pathcan containers idle), pathcan python backend.

**Power:** 17–28 W, Tctl 64–66 °C (20:52 boot: 27–40 W, 78–91 °C). Wired 16.3 GB, compressor 1.7 GB.

**Plugin fence pool and sysctl cache work** (`sample WindowServer 10`, 7,517 main-thread samples):
`vk_drm_syncobj_init`, `vk_common_CreateFence` and `DestroyFence` have 0 samples (95 before). `__sysctl` has 1 (47 before).
The main thread is ~45 % busy, with `render_update` 1,653 and the Chrome video import path
(`nvmtl_vk_buffer_import_host`) 117. Cursor copies are 0 (the mouse was not moving over Claude).

**Hands-off run** (00:06, owner away from mouse and keyboard for ~35 s, root job started 8 s after the password):
the WindowServer main thread was idle, 85 of 8,814 samples (~1 %). Only ~13 wakeups/s came from clients.
Chrome's video was not drawing in that window (Chrome dropped out of `top`), so Chrome's own cost could not be
isolated. The result says that **with no interaction and no visible animation, WindowServer costs ~1 %**; everything
above that follows what is on screen and what the user does.

**IPIs (remote ASTs):**

| | Normal use (00:03) | Hands off (00:06) |
|---|---|---|
| Total | 65,390/s (includes 7.3k/s WindowServer ↔ another session's osascript) | 28,553/s |
| hyperkit vCPU → vCPU | 9,145 | 15,401 |
| Docker backend ↔ itself, hyperkit, kernel | ~2,700 | ~4,500 |
| ItlXhciKick → xHCI work loops | 1,957 (busy 920 + 920, empty 58 + 58) | 1,825 |
| k:71938/k:64276 → k:583 | ~610 | 552 |

- **ItlXhciKick:** the two empty controllers are now woken 58/s instead of ~916/s. Its total went from 3,631/s
  to ~1,950/s, as designed.
- **Docker is now the largest IPI source**, with every container idle: the 24-vCPU guest's vCPU threads wake each
  other 9–15k/s, plus ~4k/s from the backend. hyperkit uses 73–124 % CPU while user-space sampling sees only ~0.15
  core in `hv_vmx_vcpu_run`, so most of that time is inside the kext (exits ~9.4k/s, NPT ~6.4k/s, 0 WRMSR lines).
  Fewer vCPUs for the Docker VM (Docker Desktop setting, owner's call) should cut both. The in-kext time is a lead
  for the ryzenhv session.
- **CCFaultReporter:** not confirmed. The spindump for thread names failed (wrong `spindump` argument form), and an
  unnamed kernel thread k:583 is still woken ~550–610/s by one kernel thread. That matches the old CCFaultReporter
  pattern; it needs one named kernel stackshot to settle.

**NMXGPU user-page records (`debug.nmx_userrec_*`):** live 131,524 at 23:55. From 23:59 it was stable at
457k–469k over 3 minutes (30 s samples), so there is no growth after warm-up and the Step138 fix holds. Pinned user
pages: 828k–860k (~3.3 GB). The churn is high: `made` and `freed` both rise by ~1.7 M per 30 s, i.e. **~56,000 page
records created and freed per second** during video. That is per-frame userptr pin/unpin and worth a per-caller
counter (main/video sessions).
