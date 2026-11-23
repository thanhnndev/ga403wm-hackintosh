# 890M power features: upstream vs the port (2026-11-23)

Follows up on docs/POWER-UNDER-LOAD.md (branch power/under-load), sections 2-3. Under light load the package draws
17 W, while the cores account for only 4-6 W. About 6-8 W is "SoC / GFX / memory, not split". This note covers:

- step 1: the readout that splits that number;
- step 2: what in the port could keep the GFX island up between frames;
- the power features compared with upstream.

Nothing here was installed or turned on.

## 1. Readout (frame-path-kernel fix/out31: bb730aa, eb14cc4, e6938f9, 4194a26)

| sysctl | what |
|---|---|
| `debug.nmx_gpu_metrics` | amdgpu `gpu_metrics_v3_0` from `smu_v14_0_0_get_gpu_metrics` (one SMU metrics-table transfer, cache bypassed) |
| `debug.nmx_pp_features` | the SMU feature list, the same text Linux shows in `pp_features` (`smu_cmn_get_pp_feature_mask`) |

Both sysctls are read-only and registered in `nmx_oids[]`. Neither runs anything periodic. A size probe does not
query the SMU, and nothing is queried while `in_suspend` or `in_s0ix` is set.

**Patch and plumbing.** The formatter is in patch `amdgpu-nmx-power-readout` (`amdgpu_pm.c`, plus three counters in
`amdgpu_gfx.c`). The bridge wrapper is `nmx_power_format` in `nmx_fb_bridge.c`.

**Why not the sysfs bridge.** The Linux sysfs attributes (`gpu_metrics`, `pp_features`, `amdgpu_pm_info`) cannot be
read through the bridge. Every `amdgpu_pm` show handler first calls `pm_runtime_get_if_active()`, and in FreeBSD
LinuxKPI that is a TODO stub that returns `-EINVAL` (`linux/pm_runtime.h`). The readout calls `amdgpu_dpm_*`
directly instead.

**Safety (4194a26, after review).** The readout makes no SMU query in four situations:

- during a GPU reset or suspend: `amdgpu_in_reset`, `in_suspend` or `in_s0ix`, checked first and again under
  `pm.mutex` right before the transfer;
- across the port's own power change: `NMXGPU::setPowerState` holds a lock that the sysctl only try-locks;
- while the GPU is powered down;
- while it holds no lock: the shared metrics table is copied under `pm.mutex`.

To read it, no root is needed: `tools/890m/power-readout.sh [samples] [interval]`.

**Does the read itself wake GFX?** Run `power-readout.sh wake [quiet_s]` at a static screen. It does two
back-to-back reads (the driver counters must not move), then compares one read after a quiet minute with the last
read of a minute of 1 Hz polling, then takes a quiet read again. If the polled read shows higher GFX power, gfxclk or
GFX activity at the same flips/s, the PMFW wakes GFX to serve the table: use single reads only.

### Lines in `debug.nmx_gpu_metrics`

| line | content |
|---|---|
| `dpm_enabled ... pp_feature ... pg_flags ... cg_flags` | the driver's power configuration (compare with section 3) |
| `gfxoff allowed_by_mask req_count state ...` | GFXOFF bookkeeping. `req_count 0` means no holder; `state 1` means AllowGfxOff was sent to the PMFW. SMU 14.0.0's ppt has no gfxoff status/residency/entrycount, so those three show `r-22` (`-EINVAL` from `smu_get_*_gfxoff`). |
| `gfxoff_ctrl allow exit hold` | counters in `amdgpu_gfx_off_ctrl`. `allow`: the last holder let go. `exit`: a holder pulled GFX back up while GFXOFF was allowed (a forced power-up, followed by 100 ms before the next allow). `hold`: every new holder. |
| `smu workload_mask power_profile_mode video_refs 3d_refs` | the SMU workload profile. VIDEO is held while the VCN is busy, plus 1 s after. |
| `power_mw socket apu gfx all_core ipu dgpu sys soc_rest` | PMFW time-filtered mW. `soc_rest` = socket − all_core − gfx − ipu, the "not split" share. |
| `core_power_mw`, `clk_mhz`, `core_clk_mhz` | gfx / soc / fclk / uclk / vclk / vpe clocks, plus per-core clocks |
| `activity_pct gfx vcn`, `dram_mbs`, `core_c0_pct` | busy %, DRAM bandwidth, per-core C0 residency |
| `temp_cC`, `throttle ...` | temperatures (centi-°C) and throttle residency counters |

**How to tell whether GFXOFF is entered.** The PMFW gives no residency counter, so the evidence has to be combined:

1. `state 1` and `req_count 0` mean the driver allowed GFXOFF.
2. Over the sample interval, `exit` and `hold` deltas near zero mean nothing in the driver is pulling GFX back up.
3. At a static screen, `gfx` power and gfxclk fall to the floor.

If GFX power stays at hundreds of mW with `activity_pct gfx` near 0, GFX is clock-gated but not off.

## 2. What could keep GFX up between frames: source check

**The software VBL timer.** It does not keep GFX up any more.

- Since out-31 row 2 (`nmx_fb.cpp`), IOFramebuffer VBLs come from the CRTC vblank IRQ. NMXGPU holds a DRM vblank
  reference (`drm_crtc_vblank_get`) only while one of IOFramebuffer's `'vbl '` registrations is enabled.
  IOFramebuffer itself turns them off after idle frames (`deferredVBLDisable`).
- With no registration on, the reference is dropped and the timer goes idle (`fTimerIdle`). While the CRTC delivers,
  the timer only wakes every 100 ms as a watchdog.
- The timer touches only the CPU, never the GFX island.
- Linux follows the same rule. A compositor that wants vblank events keeps the DRM vblank IRQ on. On DCN 3.5 with a
  PSR panel, DRM switches it off 2 frames after the last user (the `offdelay_ms` path in `amdgpu_dm.c`).

**G's `patches/power-floor/nmx-fb-vbl-gate.patch`** (commit 9bb57d6, 2026-11-16). It is superseded and was never
built.

- It was written against the pre-out-31 `nmx_fb.cpp`. Back then, one `Irq fVbl` timer fired at the panel rate for
  ever, because `setInterruptState` and `unregisterInterrupt` were no-ops.
- The patch stopped that timer while IOFramebuffer had the VBL interrupt masked, with boot-arg `nmxvblgate=0` to undo.
- out-31 row 2 rewrote the same code: slots, a refcounted `setInterruptState`, CRTC-vblank delivery, and an idle
  timer. So the patch no longer applies, and its intent is already in the shipped code.

**PSR1.** The port's behaviour matches Linux.

- It is enabled (`psr feature_enabled 1, version 0` = PSR1; the sink has no PSR-SU).
- Linux enters PSR1 only when two things hold:
  - the vblank IRQ is off (`amdgpu_dm_crtc_set_panel_sr_feature`);
  - `allow_sr_entry` is set, which needs 5 consecutive fast commits (`sr_skip_count`).
- Our flips are `drm_atomic_nonblocking_commit` plane updates, the same fast path a Linux compositor uses. Linux
  disables PSR1 whenever the vblank IRQ is on.
- Live sample, 15:11 today, under the owner's load: flips 86.8/s, VBL 87.0/s, `vbl_held 1`,
  `active_vblank_irq_count 1`, `psr allow_active 0`. The screen was redrawing continuously, and Linux would also keep
  PSR off here.
- Earlier, at a static screen, out31-verify showed `vbl_held 0`. Whether PSR then actually entered is a question for
  the first boot with the readout.

**Other port timers and threads.** None of them touches GC registers or calls `amdgpu_gfx_off_ctrl`. They wake the
CPU only.

- Fence completion is IRQ-driven as upstream (`AMDGPU_FENCE_JIFFIES_TIMEOUT`). irqwatch's 2 ms poll runs only in
  degraded mode and reads memory, not GC.
- Userptr park: a 1 s delayed work.
- `nmx_beat`: 1 s, stops after 40 beats.
- `nmx_page` thread call; `holdCall_`.

**GC MMIO in the patch series.** It appears only on error paths:

- `amdgpu-ibprobe` and `amdgpu-ringdump2` (ring timeout);
- `amdgpu-vmregs` and `amdgpu-wptr-flush-b13` (VM fault / coredump);
- `amdgpu-irqwatch-fence` reads IH registers (OSS, not GC).

Upstream brackets GC reads with `amdgpu_gfx_off_ctrl(false/true)`; these paths do not. During GFXOFF they can read
garbage. That costs no power, but it makes the diagnostic wrong (see section 4).

**User space.** `AMDGPU_INFO_READ_MMR_REG` brackets its reads with `gfx_off_ctrl` and forces GFX up each time. Mesa
reads registers only at device init. If anything polls it, the `hold` and `exit` counters will show it.

**The likely real cost is the redraw rate, not a timer.** At 87 flips/s, WindowServer composes a full frame every
vblank, so GFX wakes at panel rate. A Linux desktop playing the same video presents at the video rate and is otherwise
static. Which client keeps WindowServer redrawing (Claude renderer, Edge WebRTC) belongs to the WS-CPU track. The
readout answers what it costs: `gfx` mW and `activity_pct gfx` at 87 flips/s, compared with a static screen.

## 3. Power features: upstream default / ours / reason

The patch audit found no patch in `patches/series` that touches gfxoff, pg/cg flags, `amdgpu_pp_feature_mask`, DPM,
clock gating, VCN/JPEG power gating or DC PSR/IPS settings. The only power-related patches are traces:
`amdgpu-dm-ips-trace`, `amdgpu-dm-frametrace`, and the flipdone PSR flags. So every row below is upstream behaviour.

| feature | upstream default (this tree) | ours | reason / note |
|---|---|---|---|
| GFXOFF (`PP_GFXOFF_MASK` 0x8000) | on. `amdgpu_pp_feature_mask = 0xfff7bfff`; cleared only for SR-IOV or `sched_policy == NO_HWS` (default HWS). | same | late_init gates GFX PG, `gfx_off_req_count` 1→0, AllowGfxOff after 100 ms. Not yet verified on our boot: readout `gfxoff` line. |
| GFX PG (`AMD_PG_SUPPORT_GFX_PG`) | on (soc21.c, GC 11.5.0) | same | readout `pg_flags` |
| GFX clock gating: CGCG/CGLS/MGCG/FGCG/3D CGCG/CGLS, REPEATER_FGCG, PERF_CLK | on | same | readout `cg_flags` |
| MC / HDP / ATHUB / IH / BIF clock gating | on | same | `cg_flags` |
| VCN: DPG, PG, MGCG; JPEG: DPG, PG, MGCG | on. Gated 1 s after the last job (`VCN_IDLE_TIMEOUT`); VIDEO workload profile while busy. | same | VCNDec decodes on the VCN, so the same rules apply. |
| SMU DPM / deep sleep (GFX, SOC, FCLK, VCN DPM; DS_*) | PMFW-owned; the driver enables the default feature set | same | readout `nmx_pp_features` |
| Runtime PM (BOCO/BACO) | none on an APU | none ("Runtime PM not available") | Same as Linux. Its only effect here is the `pm_runtime_get_if_active` stub that breaks the sysfs readers. |
| PSR1 | on for DCN 3.5.0 (`DC_DISABLE_PSR` not set) | on (`feature_enabled 1`) | entry rules identical (section 2) |
| PSR-SU | sink-dependent | not offered by the sink (PSR ver 1) | n/a |
| Panel Replay | off (`DC_REPLAY_MASK` 0x200 not in default `amdgpu_dc_feature_mask = 2`) | off (`replay 0`) | upstream default |
| DMUB IPS | `DMUB_IPS_RCG_IN_ACTIVE_IPS2_IN_OFF` (6) when PMFW < 93.99 (IPS2 + Z8 hard-hang workaround); `ENABLE` on newer PMFW (GC 11.5.0) | 6 (PMFW 93.11, `smu_ver 0b5d0b00`) | upstream logic on our firmware |
| FBC | off by default | off | upstream |
| Stable pstate | only on a context request (`AMDGPU_CTX_OP_SET_STABLE_PSTATE`, e.g. RADV SQTT) | the plugin does not request it | n/a |

## 4. What to turn on first, and the risk

**Nothing in the kernel is off that upstream has on.** So the first boot is a measurement, not a switch. Run
`power-readout.sh 15 2` in each of three states:

1. owner load with video;
2. the same with the video paused;
3. a static screen.

The verdict comes from these signals:

| signal | meaning |
|---|---|
| `gfxoff state 1`, `req_count 0` | the driver allows GFXOFF |
| `exit` delta near 0 | nothing forces GFX up |
| `power_mw gfx` and `clk_mhz gfx` at the floor on a static screen | GFXOFF is reached |
| `soc_rest` | the SoC / fabric / memory share |
| `clk_mhz fclk` / `uclk` | do the fabric and memory clocks drop |
| `activity_pct vcn`, `vclk` | VCN cost during video |

What to do next depends on what the readout shows:

1. **`req_count > 0`, or `hold` keeps growing.** A holder is pinning GFX up: find the caller and fix it (the
   `READ_MMR_REG` ioctl from user space, or a port path). Risk: none; this is a fix.
2. **`state 0` with `req_count 0`.** The 100 ms delayed work (`gfx_off_delay_work`) is not running under xkpi. Fix the
   workqueue path. Risk: low. The PMFW sequences the exit, the same as on Linux.
3. **GFXOFF works but GFX still costs watts at 87 flips/s.** The cost is the redraw rate. The fix belongs in the
   WindowServer / frame path (present at the content rate, let IOFramebuffer drop the VBL so PSR1 can enter), not in
   the power features.
4. **Bracket our diagnostic GC reads with `amdgpu_gfx_off_ctrl(false/true)`**, as upstream does around every direct GC
   MMIO (ibprobe, ringdump2, vmregs, coredump). This is correctness for diagnostics, not power. Risk: none on the
   normal path; on an error path it can add a GFX power-up.

Not recommended:

- **IPS2 in active idle (`DMUB_IPS_ENABLE`).** Upstream forbids it on PMFW < 93.99 because IPS2 + Z8 can hard-hang
  the machine. Ours is 93.11. Revisit only after a BIOS/PMFW update.
- **Panel Replay.** The sink reports PSR1 only, so there is likely nothing to gain. The risk is flicker or black
  frames.

**How Linux avoids a hang at GFXOFF exit on this chip (GC 11.5.0, SMU 14.0.0):**

- **The driver never sequences GFX power itself.** It sends AllowGfxOff or DisallowGfxOff to the PMFW
  (`smu_v14_0_gfx_off_control`, PPSMC 0x19 / 0x1A). RLC, IMU and PMFW do the power-down and power-up. On 11.5, GFX is
  powered up through the IMU (`set_gfx_power_up_by_imu`).
- **Work submission does not call the driver to wake GFX.** It wakes GFX through doorbells, which MES/RLC firmware
  handles.
- **Every driver access to GC registers is bracketed** by `amdgpu_gfx_off_ctrl(false)` and `(true)`: the
  `READ_MMR_REG` ioctl, the SPM VMID update, debugfs, and powergating changes. Touching GC MMIO while GFX is off is
  the classic hang, or garbage read.
- **A 100 ms hysteresis** (`GFX_OFF_DELAY_ENABLE`) stops re-entry thrash. In s0ix the allow is sent immediately.
- **Firmware fixes and quirks keyed on the PMFW version** cover the rest. The DCN 3.5 IPS2/Z8 workaround above is one
  of them, and our PMFW gets it. This tree has no GFXOFF quirk list for 11.5; that list exists only for gfx9.

The port runs all of this unchanged. The only port-specific risk is the unbracketed GC reads on our error paths
(item 4 above).
