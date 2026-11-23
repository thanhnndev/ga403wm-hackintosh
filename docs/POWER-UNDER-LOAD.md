# Heat, fan and power under the working load (2026-11-23)

Question from the owner: what makes the machine hot and loud during hours of normal work? Normal work is Edge video,
the Claude desktop app, Claude CLI sessions, and sometimes Docker. This file builds on `docs/CPU-THERMALS.md` (11-08 to
11-16 cause list) and `docs/POWER-FLOOR.md` (idle floor) and does not redo them.

## 1. Live state, 14:54-14:56 (boot 14:33, read-only, the owner working)

Package and platform:
- **Load:** Edge playing video, Claude desktop app, 4 Claude CLI sessions, Spotlight finishing after boot, one
  vt_check test tool from the video session. No Docker, no emulator.
- **Package power:** **17.0 W** (RAPL energy, 60 s). The 5 s samples range from 12.9 to 20.2 W.
- **Temperature and fans:** Tctl **55 / 57 / 60 °C** (min / avg / max). Fans read raw `cpu_fan=22 gpu_fan=24`, quiet
  (the 11-16 Docker load read 59/60).
- **CPU policy:** CPPC autonomous (REQ min 23, max = highest perf, desired 0) with **EPP 191** on every CPU. AsusWmi
  profile 3, no custom fan curve (`fan_custom=0`), no PPT override (`ppt_spl/sppt/fppt=0`, firmware limits).
- **RTX:** really off. StrixDgpuGate reports `gate-powered-off Yes`, `gate-off-bus Yes`, and the vendor ID reads 0xffff
  (Eco boot 10).
- **Idle state:** `S0ix,IdleMode 0`, so idle cores HLT (CC1). No CC6 at runtime.
- **Memory:** wired 6.6 GB, compressor 0. No pressure.
- **Display:** about 35 composited frames/s (`nmxaccel_pipe_perform` +1908 in 54 s).

Per-core (`debug.amdcppc.freq`, 12 samples):

| cluster | busy-weighted MHz | mean busy per thread |
|---|---|---|
| Zen 5 (cpu 0-7) | 2661 | 7.5 % |
| Zen 5c (cpu 8-23) | 2071 | 8.0 % |

The odd SMT siblings sit at 0 % busy most of the time.

Who uses the cores (top, 60 s average, % of one core):

| process | % | class |
|---|---|---|
| WindowServer | 26 | compositor (ours: plugin/NMX per-frame cost) |
| kernel_task | 20 | our kexts' threads (no compression this boot) |
| Edge helpers (GPU + renderer) | 33 | user, video |
| vt_check | 13.5 | test tool of the video session |
| Claude desktop (app + helpers) | 23 | user (Electron) |
| claude CLI (4) | 5.3 | user |
| mds_stores | 7.5 (32 in the first minute) | Spotlight after boot, transient |
| coreaudiod, sysmond, rest | ~10 | |

That is about 1.8 cores in total.

**Reading:** at this load the machine is not hot (57 °C, low fans). The 11-16 numbers for the owner's heavy work
were **62 W and 95 °C**, with fans at 59/60. That run had Docker at 5.2 cores, the Android emulator at 1 core, the
project's Python backend at 3.1 cores, and kernel_task at 108 % from compression. The heat and fan noise come from
that class of load: about **+45 W** over the light state measured here.

## 2. Where the watts go, ranked

Watt figures are estimates unless marked measured. Per-core cost on this chip at EPP 191: about 2-3 W per fully busy
thread at 2-2.7 GHz, and 4-5 W per thread at boost (EPP 0, 11-08 A/B: 37 → 22 W for the same work).

| # | Where | Load | Estimate | Ours? |
|---|---|---|---|---|
| 1 | **Docker VM under RyzenHV.** hyperkit + backend 5.2 cores (11-16), 0.7-1.2 cores with idle containers (11-09). The 9-15k IPI/s figure is from 11-16 with a 24-vCPU guest; Docker Desktop is at 8 vCPUs / 8 GB since then (to be re-measured, `docs/RYZENHV-EXITS.md`). An idle Linux guest exits tens of thousands of times per second to user space (APIC MMIO, HLT; `ryzen-hypervisor.framework/tools/hvf-exit-bench`). RyzenHV wires the whole guest (12.3 GB), which made kernel_task compress at 108 %. | Docker | **10-20 W** of the 45 W step (overhead part; the containers' real work is the owner's) | **yes**: RyzenHV (ryzenhv session); vCPU/RAM limits are the owner's Docker setting |
| 2 | **Owner's own work** in that step: Python backend 3.1 cores, emulator 1 core, Claude CLI, Edge renderer. | Docker | 15-25 W | no |
| 3 | **SoC / GFX / memory, not split.** The light state is 17 W while the cores do ~1.8 threads (≈ 4-6 W). True idle is 5.5 W (11-08). That leaves ≈ 6-8 W for the 890M, VCN, display and fabric with one video. Whether GFX power-gates between frames (GFXOFF) and whether the fabric drops clocks is **unknown**: no sysctl exposes SMU `gpu_metrics`. Boot log: `PSR support 1`, `Runtime PM not available`. Typical Linux on Strix Point plays 1080p video at about 8-10 W package. | every load | 3-6 W possibly recoverable (estimate, unverified) | **yes**: NMXGPU (main) |
| 4 | **WindowServer per-frame cost.** 26 % of a core at ~35 frames/s ≈ 7 ms of CPU per frame (11-08: ~5 ms; a real Mac ~1 ms). Video at 60 fps takes it to ~40-45 % of a core. | video, any animation | 1-2 W | **yes**: plugin / NMX (main) |
| 5 | **kernel_task 20 % with no compression.** Our polling threads: Wi-Fi RX/TX pump (1k wakeups/s, `IODelay` windows under traffic), ItlXhciKick (1 kHz), VoodooI2C touchpad polling (~10k IRQ/s on CPU 0). They also cap how deep idle cores can sleep. | always | 0.7-1.5 W (and they cap #6) | **yes**: Wi-Fi session, main |
| 6 | **No CC6 at runtime** (idle mode 0, HLT). Cores are ~92 % idle at this load; on Linux `acpi_idle` C2 power-gates them. The 11-08 A/B at 80 frames/s showed no difference (9.9-10.1 W in every mode), which points again at #3 (SoC-bound), not at the cores. | light | 0.5-2 W, measured 0 at 80 fps | yes: StrixS0ix (main), runtime switch exists |
| 7 | **Platform policy.** EPP 191 with CPPC autonomous is exactly what Linux `amd-pstate-epp` (active mode, `balance_power`) requests; the hardware then picks the same clocks (2.66 GHz Zen 5 / 2.07 GHz Zen 5c here). Boost, core parking and the fan curve are firmware defaults in both OSes. **No gap here except C-states (#6).** EPP 0 was the large lever and has been fixed since 11-16. | all | 0 vs Linux | n/a (no change proposed) |
| ~~8~~ | ~~10-bit 4K video in a software decoder~~: **struck** (main/F, 11-23). VCNDec 0.2.0 decodes 10-bit on the VCN since 11-18. Today's Edge video was VP9/AV1 8-bit on the VCN, and the 4K 10-bit frames at 13:31 were the Aerial wallpaper, also on the VCN. | | 0 | n/a |

## 3. The two changes that would lower heat and fan noise most during work

1. **RyzenHV idle-guest and memory cost (#1).** Ours, in the ryzenhv session:
   - Keep guest exits in the kernel: APIC timer, ICR and EOI emulation, and HLT blocking without a round trip to
     user space.
   - Stop wiring the whole guest: map it lazily and pageable.

   On the owner's side, Docker Desktop at 8 vCPUs and a smaller RAM size gives part of it at once, with no code.

   Expected:
   - with idle containers, −0.5 to −1 core (≈ −2 to −4 W);
   - under the 11-16 load, about −1 core of exit/IPI overhead plus −1 core of compression (kernel_task 108 % → ~10 %);
   - in total ≈ **−8 to −15 W**. That is about −10 °C at the 95 °C point, and the fans drop from 59/60 toward ~40.

   This is the only lever that matches the size of the heat the owner feels.
2. **A GPU/SoC power readout, then the SoC fix it points to (#3).** Ours, NMXGPU; **taken by F (video session) on 11-23**.
   - Step 1, read-only: a sysctl `debug.nmx_gpu_metrics` that returns amdgpu's `gpu_metrics_v3_0` (SMU 14.0.x). It
     carries `average_socket_power`, `average_gfx_power`, `average_soc_power`, `average_core_power[]`, `average_gfxclk`,
     `average_fclk/uclk`, `average_gfx_activity`, `average_vcn_activity` and the core temperatures, from
     `amdgpu_dpm_get_gpu_metrics()`. It answers "does the 890M gate between frames, and what does video cost per rail"
     directly. It costs one SMU table read per query, nothing periodic.
   - Step 2: what it points to. Either GFXOFF is not entered (`pp_feature` / gfx_off_ctrl state in the port), or the
     fabric is held up by the 120 Hz software VBL timer and no PSR (`patches/power-floor/nmx-fb-vbl-gate.patch` exists,
     not built).

   Expected: **−3 to −6 W** at every light and video load. That is most of the time the machine is on; it brings the
   17 W state toward Linux's ~10 W and lowers the base that Docker heat stacks on. This is an estimate until step 1
   reads the rails.

Not proposed (rules): pmset, SIP, `rhv_*` boot-args, the AC profile. A lower sustained PPT (SPL) in the Balanced
profile would cap the Docker peak directly (asusctl allows it on Linux). It trades speed for heat and is the owner's
call; listed here only as an option.

## 4. Measurements still needed

Owner or main, with Docker running as in daily work (needs root, about 60 s, no Edge interaction):
```
sudo ~/develop/projects/ga403wm-power/tools/health-probe.sh docker-1 60 /var/tmp/health
```
It adds IPIs and interrupts (3 s ktrace) to the table. Compare it with
`tools/health/2026-11-23/145427-work-1.txt` (same tool, no Docker). Then `sudo zprint -t | head -20` for the wired
split. The 11-16 Docker numbers were taken at EPP 0; this run gives the EPP 191 baseline for item 1.

Raw outputs of this run: `tools/health/2026-11-23/` (probe table, 5 s samples of RAPL/Tctl/fans/frames, 60 s top).
