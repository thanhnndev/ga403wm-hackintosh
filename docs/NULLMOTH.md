# NullMoth driver: what we know (2026-10-12)

**Read the vendor's source first.** The driver is published with source at
<https://github.com/nullmoth/nvidia-macos-driver> (PolyForm Noncommercial; release notes in `docs/RELEASE-*.md`). The
first pass of this page was derived from the installed binaries (`strings`, `llvm-objdump`) and a `sample
WindowServer`; that was the wrong starting point, and the lag hypothesis it produced was not the best lead. The
component and recovery sections below stay valid; the lag section was replaced (2026-10-11).

**Current state (2026-10-12): upstream 1.14.2 + two machine-local patches, loaded after the next reboot.** See
"Local patches on top of upstream" below; the 1.14.0 paragraph that follows is the history of the first 1.14 install.

Installed before that: **1.14.0** (2026-10-11 19:57, `nullmoth-setup.sh` 1.14 run as root with `--pkg` (SHA-256 checked against
the release `SHA256SUMS.txt`), `--tool NullMothSafe.efi` (1.14 build), `--logo off`). Backup of the previous install:
`/Library/NullMoth/backup-20261011-195719.*`; ESP config backups `config.plist.pre-nm114-20261011-195530` (ours) and
`config.plist.nullmoth-20261011-195710` (the setup's). Config changes by the setup: the "1401: Remove NVIDIA driver" entry
gains `TextMode`, a new Misc.Tools entry "1401: Start once without NVIDIA driver" (`NullMothSafe.efi`, argument `once`);
everything else is key reordering (the iGPU class-code/name hide is kept). It also arms a "flicker stopgap" that restarts
WindowServer once per boot (opt out: `/Library/NullMoth/no-wsreset`).

1.14.0 items that matter here: display sleep turns the panel off (#90, the lock-screen symptom), stale/black windows
(#98), WebGL, the Photos crash, DSC, hardware encode, and `vramGrant` clears with `nvu_zero_wide`, so the local
vramclear patch below is obsolete (the script refuses any binary that is not 1.13.0).

Rules that apply (see `HANDOFF.md`): do not disable the driver and do not guess at boot-args/quirks. The goal is a
working NullMoth driver; a change needs a root cause and the owner's agreement.

## Local patches on top of upstream (2026-10-12)

Rule: **upstream first.** Install the release package with its own `install.sh` (backs up, has `uninstall.sh`), then
layer the machine patch; every patch is a commit in the fork `thanhnndev/nvidia-macos-driver` (the PR is the primary
artifact, the machine install is the same commit) and has its own undo. Do not hand-edit installed kexts.

| Layer | What | Where | Undo |
|---|---|---|---|
| upstream **1.14.2** | release package `~/efi-audit/upgrade-1.14.2/pkg` (SHA-256 checked), boot-arg `nvrmacpibl=1` added (1.14.1 made the NBCI backlight tables opt-in) | backup `/Library/NullMoth/backup-20261012-134122.*` | `uninstall.sh <backup>` |
| VRAM clear | `nvu_zero_stream` (`movnti`) in `vramGrant`, `debug.nvrmfb_clear_mode`; `VRAM-GRANT-STALL.md` | fork branch `nvrmfb-vram-clear-nontemporal` (`49633c9`) | `scripts/macos-nvrmfb-vramclear-patch.sh --undo` |
| OLED brightness | DPCD brightness for AUX-only panels; `OLED-BRIGHTNESS-DPCD.md` | fork branch `nvrm-edp-aux-backlight` (`3501a25` upstream PR, `2c07cf7` local kext packaging) | `scripts/macos-edpbl-install.sh --undo` |

Installed NVRMFB is the combined build of both (sha256 in `~/efi-audit/brightness/stage/SHA256SUMS`). The NVMTLDriver
bundle is upstream's again: Codex's upload-copy candidate (PR #139) was evaluated and dropped, see `WINDOWSERVER-CPU.md`.
Build / dry run / install: `scripts/macos-build-nullmoth-local.sh`, `macos-aux-kc-dryrun.sh`, `macos-edpbl-install.sh`.
NVRM itself cannot be rebuilt here (the RM objects are only in NullMoth's build tree), hence the extra kext.

## Components

Current WindowServer CPU follow-up on 1.14.0: [WINDOWSERVER-CPU.md](WINDOWSERVER-CPU.md). A reversible hide/restore
test reduced CPU from 79% to 12%; hiding only ChatGPT/Codex reduced it to 1.5%. The original sample contains real
IOSurface upload/readback work, but an application-independent driver busy loop is not supported by this test.
Repeat with no active Codex turn before attributing persistent repainting to the application.

| Piece | What it is |
|---|---|
| `NVRM.kext` | NVIDIA open-gpu-kernel-modules 610.57.04 ported to XNU. Boots GSP-RM on the RTX 5060. |
| `NVRMFB.kext` | Display framebuffer (NVKMS underneath). Publishes timings/flip path to WindowServer. |
| `NVAccel.kext` | `IOAccelerator` + Metal plugin glue. |
| `NVRMAGDC.kext` | AGDC (graphics-driver control) personality. |
| `NVRMEdpBL.kext` | **Ours, not part of upstream** (`kexts/NVRMEdpBL` in the fork): AUX (DPCD) brightness for the OLED, see `OLED-BRIGHTNESS-DPCD.md`. |
| `NVMTLDriver.bundle` | Metal driver in user space: Metal calls translated to Vulkan, using Mesa NVK (`nvkmd_nvrm` backend, Mesa 26.3.0-devel). |
| `NVIDIAShared.bundle` | AIR -> NVVM -> PTX -> sm_120 JIT. Uses NVIDIA's closed `nvvm`/`ptxjit` libraries. |
| `/Library/NullMoth/` | Installer state, `nullmoth-setup.sh`, recover daemon, allow-list. |

Kexts sit in `/Library/Extensions` and load from the auxKC built with `kmutil create -n aux`. Installed record on the
volume says driver version 1.9.0 on macOS 15 (the strings dump in older notes was 1.0.8).

## What the installer touches

* `config.plist`: ResizeGpuBars 13, ResizeAppleGpuBars -1, `Kernel/Block` IONDRVSupport, SIP `0x0A43`
  (`csr-active-config`), SecureBootModel Disabled, boot-args. A backup `config.plist.nullmoth-<time>` is made first.
* `--remove` restores from that backup. `nullmoth-setup.sh --collect-logs DIR` is a read-only collector.
* **Never run the 1401.exe "Build" afterwards**: it overwrites the ESP `config.plist`.

## Process allow-list (`/Library/NullMoth/nvmtl-allow.txt`)

One name per line. `*` = every process, `-Name` = denied, `!Name` = armed only while `debug.nvaccelfb` is non-zero.
Current content: `*` and `!WindowServer`. So everything uses the Metal translation layer and WindowServer is
armed only when the framebuffer sysctl is set.

## Logging

Only lines containing `FAIL` or `REFUS` reach syslog, prefixed `NullMoth:` and rate-limited per call site. An empty
`log show` therefore means "nothing failed", not "nothing happened". `NVRM-fb:` lines are NVRMFB info lines.

## Sysctl counters (read-only, no sudo)

`debug.nvaccelfb`, `debug.nvaccel_iop`, `debug.nvaccel_iop_async`, `debug.nvaccel_iop_flip`,
`debug.nvaccel_heads_published`, `debug.nvaccel_crc`, `debug.nvrmfb_agdc`, `debug.nvrmfb_agdc_k5`,
`debug.nvrmfb_flip_*`, `debug.nvrm_pageoff_*`. The probe script dumps all of them (`scripts/macos-nullmoth-probe.sh`).

Boot-arg switches found in the binaries (reference only, do not toggle): `-nvoff`, `-nvrmnogo`, `-nvrmnoflip`,
`-nvrmnobootscreen`, `-nvkmsnosmooth`, `-nvfbsurvey`, `nvhwvbl=0`, `nvcursor=0`, `nvhud=1`, `nvfbsample=1`,
`nvfb=1`, `nvaccel=1`, `nvaccelfb=1|3|4`.

Environment knobs of the user-space driver (read by `NVMTLDriver`; they are per-process environment and WindowServer
is launched by launchd, so they are not an easy lever): `NVMTL_NO_SURFACE_SHARE`, `NVMTL_NO_NOCOPY`,
`NVMTL_NO_SURFACE_PAGEOFF`, `NVMTL_SHARED_VRAM`, `NVMTL_SHARED_VRAM_BUDGET_MB`, `NVMTL_NO_FPS`, `NVMTL_PERF_LOG`,
`NVMTL_PSTAT`, `NVMTL_NVK_MESSAGES`, `NVMTL_VRAM_HEADROOM_MB`, `NVMTL_RES2_*`, `NVMTL_SPVCACHE_*`, `NVK_DEBUG`,
`NVK_DIAG`, `NVRM_GSUB_LOG`, `NVRM_XNU_TRACE`, ... (about 100 `NVMTL_*`, 40 `NVK_*`, 10 `NVRM_*`).

## Desktop lag and 120 Hz: what changed between 1.9.0 and 1.12.0

Read from `git compare v1.9.0...v1.12.0` (39 commits). These are the changes that touch what we saw:

| Release | Commit | Change | Relevance |
|---|---|---|---|
| 1.10.0 | `3619f95e` | `cursorApply()` used to name the primary surface too, so **every cursor move was also a primary flip, paced to vsync**, and an older frame could go back on the panel ("flash on mouse movement"). Now cursor-only commits. | Matches a laggy pointer/desktop on 1.9.0. |
| 1.10.0 | `223555ff` | `addKmsRefreshModes`: also offers rasters NVKMS validated that macOS never proposed, e.g. **modes that exist only in the EDID's DisplayID block (most 100-240 Hz modes, issue #29)**. | Our panel's 120 Hz mode is DisplayID-only (see `HANDOFF.md` item 3). |
| 1.10.0 | `4cc045dc` | Managed no-copy buffers get a VRAM copy (were read across PCIe). | Throughput of image-heavy work. |
| 1.10.0 | `db2e966e` | Flicker workaround restarts WindowServer only at the login window. | Black screen after the restart on auto-login. |
| 1.10.0 | `51546402` | Setup requires **Lilu + AMFIPass** on. Without AMFIPass, WindowServer (platform binary) refuses the ad hoc signed driver: "mapping process is a platform binary, but mapped file is not", no Metal device, black screen with a cursor. | Our `Kernel/Add` has Lilu but **no AMFIPass.kext**. |
| 1.11.0 | `9a20289a` | Setup adds boot-arg `ipc_control_port_options=0` (Firefox crashes at launch with AMFI relaxed). | Missing from our boot-args. |
| 1.12.0 | tracker | Display tracker writes `/Library/NullMoth/display-trace/{trace,kernel,ws}.txt` from the first second of every boot (per-second driver counters, refresh rate per framebuffer, WindowServer starts, EDID). Survives a forced restart. | Exactly the evidence the black-screen-above-60 Hz case needs. |

What this changes in the plan:

* The previous "copy path" hypothesis (CPU `memmove` in `nvmtlSurfaceIn`) is **not** the leading explanation any more.
  The driver's own commit message on `3619f95e` names the cursor-flip as the cause of a visible artefact, and the
  1.12 notes describe the IOSurface copy path only for the headless (Optimus) case, not ours.
* The macOS display override that was installed earlier (EDID with a 120 Hz base DTD; sources removed from the repo) works around something the
  driver now handles itself. Remove it (`sudo bash scripts/remove-display-override.sh`) when testing 1.12 so only one
  variable changes.
* Open at 1.12.0 per the vendor: "black screen or flicker above 60 Hz on some monitors". That is our 120 Hz black
  screen; the vendor's route is the display tracker plus "Send logs" (uploads to NullMoth; the owner decides).

The unknowns that remain: whether 1.12.0 actually keeps our panel at 120 Hz, and whether the lag is gone. Both need a
run on the machine.

## Desktop lag: measurements on driver 1.13.0 (2026-10-11)

Mode: 2880x1800 @ 120 Hz, not HiDPI. Tool: `tools/framepace.swift` (a window that either moves every display tick, like a
drag, or runs a layer animation) plus the NVRMFB flip counters; `scripts/macos-ws-frame-sample.sh` adds a WindowServer
`sample` (sudo) of the same frames.

| Run | App ticks | Flips/s | p99 tick | Late frames |
|---|---|---|---|---|
| move, process with the leaked `MESA_SHADER_CACHE_DIR` (below) | 116/s | 77-94 | 17-24 ms | 16-22 in 6-8 s |
| move, clean environment | 119/s | **116** | **8.5 ms** | 2-3 (one ~75 ms hitch) |
| layer animation | 119/s | 46-110 | 12 ms | 0 |

What this says:

* The composition path can sustain ~120 Hz. Average WindowServer cost is ~4.8 ms per frame (45 % of the main thread), well
  inside the 8.3 ms budget. The lag is **spikes**, not a low average.
* NVRMFB flips are asynchronous (NVAccel `iop_async`), ~5 ms each including the wait for the latch; `async_drop` stays 0.
* In WindowServer `-[NVMTLCommandBuffer commitAndWaitUntilSubmitted]` is `waitUntilCompleted` (on purpose: NVAccel cannot
  order the swap after an NVK fence). It runs 3 times per frame (compositor flush, twice in CoreDisplay `AccessComplete`), about
  1.6 ms of GPU wait per frame with no CPU/GPU overlap. All queues share one `VkQueue`, so only the wait right before the swap
  would be needed. Gain estimated small; not changed.

### Spike source 1: byte-wise VRAM clear in `vramGrant` (fix available)

Every IOSurface WindowServer backs with VRAM goes through `NVRMNVDAFramebuffer::vramGrant`, which clears the block with
`rep stosb` through the BAR1 mapping. Upstream PR nullmoth/nvidia-macos-driver#64 measured ~180 ms per 8 MB grant (byte
stores over PCIe) and ~30 ms with `rep stosq`. On this machine `debug.nvaccel_vm_alloc` grows about once per second at idle and
14 times in a 6 s window drag (1125 grants, 1.76 GB after 18 min of uptime). 1.13.0 still has the byte-wise clear.

* Measure: `bash scripts/macos-vramtest.sh` (sudo; grants and releases 8 MB five times).
  **This machine, unpatched 1.13.0 (2026-10-11): 727, 744, 951, 1122, 732 ms per 8 MB grant** (baseline sudo+sysctl
  55 ms), i.e. ~0.7-1.1 s with WindowServer blocked, 4-6x worse than the RTX 3070 Laptop in #64. Release: ~45 ms.
* Fixed upstream in 1.14.0 (`nvu_zero_wide`); re-measure with the script above. Old local fix for 1.13.0: `bash scripts/macos-nullmoth-vramclear.sh` patches 49 bytes in the installed 1.13.0
  NVRMFB (exact bytes and the register reasoning are in the script header), backs up the kext and the auxiliary kernel
  collection to `/Library/NullMoth/vramclear/`, rebuilds the collection like NullMoth's installer. `--check` verifies the
  binary first; `--undo` restores. It refuses any binary that is not the 1.13.0 one. Original and patched blocks were run
  side by side in a user-space harness (64 KB..16 MB): identical memory, `rcx`/`r12`/`r13` and flags.

### Spike source 2: `MESA_SHADER_CACHE_DIR` leaks into child processes (NullMoth bug)

`nvmtl_vk_initialize()` sets `MESA_SHADER_CACHE_DIR` to `$(DARWIN_USER_CACHE_DIR)nvmtl-mesa` in a process whose `HOME` is not
writable. The variable is exported, so every child inherits it. On this machine the Terminal process tree carries the value
of **root's** cache directory (`/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/C/nvmtl-mesa`); every Metal process started
from a shell then prints `Failed to create ... for shader cache (Permission denied)---disabling` and recompiles all NAK
shaders at every start. GUI apps started by LaunchServices inherit the `NVMTL_*` knobs (and `NVMTL_CONF_SET`) but not this
variable, so they keep the default cache under `~/.cache/mesa_shader_cache`. Effect measured above (move test, row 1 vs 2).

* Workaround for shells: `scripts/zshrc-nullmoth.sh` (drops an inherited, unwritable `MESA_SHADER_CACHE_DIR`).
* Fix belongs in the plugin: drop an inherited `MESA_SHADER_CACHE_DIR` that is not writable before choosing the cache, and
  record the variable in `NVMTL_CONF_SET` like the conf knobs so children forget it. Reported upstream.

### Boot: 15-19 s in `snapshotBootScreen`

`NVRM-xnu: boot screen: copied 2880x1800 pitch 16384 (28800 KB) from the console ... in 15271 ms` (18674 ms the boot before).
The copy reads the GOP framebuffer through `map(kIOMapInhibitCache)` with 8-byte loads, ~1.9 MB/s over PCIe. Workaround:
`-nvrmnobootscreen`. Upstream could read through a write-combined mapping with streaming loads (MOVNTDQA) or use the copy
engine, or skip the copy when the console is the verbose text console.

### Scaled modes go black (no HiDPI)

See `HANDOFF.md` item 7: `switchMode` test commit of a 1440x900 surface onto the 2880x1800 raster fails, NVRMFB keeps the old
mode, WindowServer does not, the panel shows nothing new. No HiDPI modes are offered even with a scale-resolutions override.
(That override marked its entries mirror-only, see `HANDOFF.md` item 7 round d; fixed in `scripts/macos-install-hidpi.sh`.)

### Not the cause

* `nvmtlSurfaceIn` (CPU upload of an IOSurface into a private image) only copies when the IOSurface seed changed; a window
  drag does not change contents.
* NVRAM / ESP logging of `itlmt7925` and `ItlDiag` was not tied to frame spikes (not measured separately).

## Other things seen, effect unknown

* `kernelmanagerd` "restricted lookup table" errors were seen in the log of the same boot.
* Shutdown-stall reports exist in DiagnosticReports.
* Neither has been tied to a user-visible problem.

## Recovery paths

* OpenCore picker tool **"1401: Remove NVIDIA driver"** (`EFI/OC/Tools/NullMothSafe.efi`, FullNvramAccess): sets the
  NVRAM variable `7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-remove`. At the next macOS start the recover daemon
  (`/Library/NullMoth/nullmoth-recover.sh`) clears the variable, runs `nullmoth-setup.sh --remove`
  (log: `/Library/NullMoth/recover.log`) and reboots. It needs macOS to reach userspace, so it is not a fix for a
  panic-at-boot.
* `--remove` restores the original config from `EFI/OC/config.plist.nullmoth-*` and removes the kexts.
* `1401 --crash-check` is only a UI that asks before sending anything.
