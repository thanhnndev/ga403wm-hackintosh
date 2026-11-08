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
- The WindowServer sample from 18:30 (Claude app animating): `nvmtl_prefault_write` and
  `amdgpu_create_bo_from_user_mem` should be near 0 under `newTextureWithDescriptor:iosurface:`.
- No gfxhub faults. The Step135 romap print names any read-only mapping that is hit.

**Undo:**
- Plugin: the plugin installer's `--undo`.
- Kernel: `nmxsurfwire=0`, or the Step130 installer `--undo` / reinstall out-17.

Installed 2026-11-08 20:41 with the out-17 reboot still pending:
- NMXGPU out-18: UUID 194BFE13, AuxKC relinked and checked. Backup `/Library/NullMoth/step130-bk-20261108T134013Z`
  is out-17.
- Plugin a95189e: UUID 5FC87442. Backup `nvmtl-plugin-20261108T134105Z` is the edge session's tile build.
- strixsbxmap refreshed, stale 0.

Undo:
- Kernel: `sudo scripts/macos-install-step130.sh --undo`, or keep it and boot with `nmxsurfwire=0`.
- Plugin: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
