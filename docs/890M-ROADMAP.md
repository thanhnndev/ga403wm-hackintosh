# 890M port - roadmap audit (2026-10-18)

Final goal (owner): a full hardware port of the Radeon 890M on macOS Tahoe, **independent of NullMoth**, with WindowServer
composited on the iGPU (this is what removes the 500-900 % WindowServer CPU: it is CoreAnimation's software rasteriser
because no Metal device exists). Route B decision (2026-10-17, Step31): build our own stack from NullMoth v2.0.4 sources, then replace
the headless accelerator, then replace the NVIDIA userland.

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
| M3 | A non-headless accelerator so WindowServer can obtain a Metal device and present | not started; today blocked: WindowServer must stay off the allow list until M2 is solid, a hung job there means no display |
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
