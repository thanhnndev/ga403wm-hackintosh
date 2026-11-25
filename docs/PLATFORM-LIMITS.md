# Platform limits: what each ASUS profile sets on macOS vs Linux / Windows (2026-11-16)

Sub-session report for the main coordinator. Question: under daily load on AC in Turbo the package draws 62 W at
Tctl 91-96 °C. Are the ASUS profiles on macOS applying the power limits (SPL / sPPT / fPPT) and fan curves that
Windows (Armoury Crate) and Linux (asus-wmi, asus-armoury, asusctl) apply, or are they left at firmware defaults?

**Short answer.** The profiles on macOS apply the same things the other two OSes apply for the three preset modes.
On every OS a preset is just one WMI write, throttle thermal policy `0x00120075`; the BIOS then loads that mode's
power limits and fan curve itself. Neither Linux nor Armoury Crate writes PPT values or fan curves for Silent,
Balanced or Turbo. They write them only in a "Manual" or custom mode. "Left at firmware defaults" is therefore the
designed behaviour, not a gap.

62 W at 91-96 °C is what Turbo is built to do on this chassis. Windows Turbo allows the CPU 80 W sustained. The chip
stops short of that because it reaches its temperature limit with the fans already near maximum. Balanced (about
45 W sustained) and Silent (about 35 W) are the profiles that make the machine cool and quiet.

There is one real bug, and it is fixed on a branch: AsusWmi read the wrong firmware fan curve for Turbo and Silent
(see 4). A second item, reading the actual PPT limits back from the SMU, needs new kext code (see 3).

## 1. What a profile change does on macOS today

Code: rog-control-macos `feat/gpu-mode` @ 2cf905e (installed: AsusWmi 0.3.0, RogControl 0.6.0, AmdCppcPolicy from
PR #16, which is contained in `feat/gpu-mode`).

Call chain for a profile change. RogControl `Apply.mode()` (`macos/RogControl/RogControl.swift:431`) sends
`Asus.set(.profile, n)` to the AsusWmi user client, which runs `AsusWmi::setValue(ASUS_SET_PROFILE)`
(`kexts/AsusWmi/AsusWmi.cpp:558`). That calls `devs(0x00120075, n)`, which evaluates `ATKD.WMNB` DEVS. Per the
October DSDT audit (`docs/ASUSCTL-MACOS.md`), the BIOS handles this with `WCHK`/`W15H`, a software SMI on port 0xB2.
AsusWmi then clears its own `fanCustom` flag and `pptSet[]`. AmdCppcPolicy, a root daemon that polls every 5 s, reads
`set_profile` and writes EPP to all 24 CPUs. Nothing else is written. RogControl repeats the same sequence on every
AC/battery change and at login, using a separate setting set for each power source.

| Mode (RogControl / Armoury Crate) | Thermal policy `0x00120075` | SPL `0x001200A3` | sPPT `0x001200A0` | fPPT `0x001200C1` | APU / platform sPPT `0x001200B0/B1` | Fan curve `0x00110024/25` | NV boost / temp `0x001200C0/C2` | EPP (AmdCppcPolicy) |
|---|---|---|---|---|---|---|---|---|
| Silent | **set** (2) | firmware (BIOS loads it with the mode) | firmware | firmware | not present on this BIOS | firmware (EC auto) | firmware | **set** 255 |
| Balanced ("Performance") | **set** (0) | firmware | firmware | firmware | not present | firmware | firmware | **set** 191 (AC and battery) |
| Turbo (AC only in RogControl) | **set** (1) | firmware | firmware | firmware | not present | firmware | firmware | **set** 0 on AC, 191 on battery |
| Manual | **set** (0) first | **set** (user, 15-80 W AC / 15-35 W DC) | **set** | **set** | – | **set**: the chosen firmware curve copied as a custom curve (needed before PPT, as asus-armoury `requires_fan_curve`) | firmware | 191 |

"firmware" means the value the BIOS SMI handler loads for that policy. macOS cannot read it back: DSTS on the PPT IDs
returns a constant `0x00010000`, and DSTS on the policy always returns 3 (see 3).

## 2. What Linux and Windows set (GA403W*)

**WMI device IDs** (Linux `include/linux/platform_data/x86/asus-wmi.h`): throttle policy `0x00120075` (values
0 default/balanced, 1 overboost/turbo, 2 silent), PPT_PL1_SPL `0x001200A3`, PPT_PL2_SPPT `0x001200A0`, PPT_PL3_FPPT
`0x001200C1`, APU sPPT `0x001200B0`, platform sPPT `0x001200B1`, NV dynamic boost `0x001200C0`, NV temp target
`0x001200C2`, dGPU TGP `0x00120098`, CPU / GPU / mid fan curve `0x00110024` / `0x00110025` / `0x00110032`, fan speed
`0x00110013` / `0x00110014`.

**On this BIOS** (October DSDT audit): the three PPT IDs reach AMD `ALIB` function 0x0C (`UTDP`, value × 1000 mW) and
cannot be read back. `0x001200B0` and `0x001200B1` are absent. `0x00110032` (mid fan) is absent: the machine has two
fans. `0x00120098` was not checked.

**asus-armoury limits for GA403WM** (Denis Benato, "add support for GA403WM", LKML 2026-01-02). These match
AsusWmi's `kAcPpt` / `kDcPpt` exactly:

| | SPL min-max | sPPT min-max | fPPT min-max | NV dyn boost | NV temp target | NV TGP | `*_def` |
|---|---|---|---|---|---|---|---|
| AC | 15-80 W | 25-80 W | 35-80 W | 0-15 W | 75-87 °C | 55-85 W | none given, so init falls back to max |
| Battery | 15-35 W | 25-35 W | 35-65 W | – | 75-87 °C | – | none |

`requires_fan_curve = true`. GA403WW (RTX 5080) has the same CPU limits, with NV boost up to 25 W and TGP 80-95 W.

**What Linux writes on a profile change:**
- asus-wmi `throttle_thermal_policy_write()` writes `0x00120075` and marks every custom fan curve disabled ("Must set
  to disabled if mode is toggled").
- asus-armoury writes PPT only from its sysfs store (`armoury_set_devstate`). It returns `-EBUSY` unless a custom fan
  curve is active. Its `*_def` values only seed `rog_tunables`; they are never written on a profile or AC change.
- asusd (`ctrl_platform.rs`, `config.rs`) writes the profile, then re-applies stored fan curves and PPT only if the
  per-profile tuning group is `enabled`. That defaults to `false`. Defaults: AC → Performance (turbo), battery →
  Quiet, `platform_profile_linked_epp = true` (Quiet `power`, Balanced `balance_power`, Performance `performance`).

So by default Linux also leaves the presets' limits and fan curves to the firmware, and also runs EPP `performance`
in Turbo. Our EPP table is the same as asusd's.

**Windows / Armoury Crate**: the presets set the policy and the Windows power-mode overlay. Manual mode writes PPT
and fan curves. Measured per-mode CPU limits, Notebookcheck's G14 2025 review (GA403WW, same CPU and chassis), table
"Testing conditions":

| Mode | CPU TDP (short / sustained) | GPU TGP | max fan noise |
|---|---|---|---|
| Quiet (Silent) | 65 / 35 W | 45 W | 42 dB(A) |
| Performance (our Balanced) | 65 / 45 W | 95 W | 52.1 dB(A) |
| Turbo | 80 W (sustained 80 W) | 110 W | 54.4 dB(A) |
| Battery (Performance, the most battery allows) | 40 / 31 W | 43 W | 36 dB(A) |

A secondary source, a third-party test PDF for the GA403WR / HX 370 that we could not verify, gives Cinebench 10 min:
Silent ~42 W average at ~79 °C, Turbo ~74 W average at ~95 °C. The GA403WM (RTX 5060) firmware may set lower
numbers than the WW; we found no per-mode measurement for the WM.

## 3. What the live machine reports (read-only, 2026-11-16 ~19:20)

Read-only commands only: `sysctl debug.asuswmi.status`, `debug.amdcppc.*`, the `RogControl --doctor` read, and
user-client selector 2 (DSTS fan-curve read) through a small IOKit reader in the scratchpad. No DEVS, no EC write.

| | On AC (first read) | On battery (later read) |
|---|---|---|
| Profile set by RogControl | 1 Turbo (`set_profile=1`) | 2 Silent |
| DSTS `0x00120075` | `0x00010003` (always 3 on this BIOS: useless) | same |
| Custom fan curve / PPT override | none (`fan_custom=0`, `ppt_*=0`) | none |
| Fans CPU / GPU | 5900 / 6100 rpm | 2400 rpm (CPU) |
| Package (RAPL) / Tctl | 52.2 W / 90.5 °C | 25.2 W / 81.4 °C |
| EPP | 0 on all CPUs | (191/255 per policy) |
| Clocks | Zen 5 ~4.87 GHz, Zen 5c ~3.26 GHz under load | – |
| NV base TGP / dyn boost / temp target | 55 W / DSTS 0 / DSTS 0 (not readable) | |

**Cannot be read today:** the SPL / sPPT / fPPT the firmware actually loaded. The BIOS returns no value for them. The
real numbers live in the SMU (STAPM / PPT limits in the PM table, as ryzenadj reads them). Reading them requires
sending SMU mailbox messages (transfer table, then read the DRAM table) from a kext. That is new code. It sends
commands, so it is not a pure register read, and I did not try it. AmdCppc already maps the SMU mailbox registers
(`debug.amdcppc.psp`: `smu_msg/arg/resp`). See design item D3.

## 4. Fan: under EC auto, but AsusWmi labelled the curves wrong (fixed on a branch)

The fans are under EC automatic control with the active profile's firmware curve. Nothing on macOS overrides it
(`fan_custom=0`).

DSTS on `0x00110024/25` takes a **curve index**, not the policy value. The firmware numbers its curves 0 balanced,
1 silent, 2 turbo, while the policy is 0 balanced, 1 turbo, 2 silent. Linux swaps the two in
`fan_curve_get_factory_default`. AsusWmi passed the policy value through. Live readout (temp/duty):

| Firmware index | CPU curve | GPU curve | Really |
|---|---|---|---|
| 0 | 47/1 62/8 65/13 68/18 70/22 72/32 74/39 76/53 | 47/1 … 73/53 | Balanced |
| 1 (AsusWmi called it "turbo") | 43/1 68/6 70/8 72/13 74/18 76/22 78/32 255/32 | 43/1 … 70/32 255/32 | **Silent** |
| 2 (AsusWmi called it "silent") | 64/13 66/18 68/32 70/39 72/53 74/58 76/72 78/86 | 57/13 … 74/86 | **Turbo** |

Proof: in Turbo the fans ran 5900/6100 rpm at Tctl 90 °C. Only the index-2 curve (86 % from 78 °C) gives that; the
index-1 curve would cap at 32 %.

Consequences of the bug:
1. RogControl's fan-curve view showed Silent's curve in Turbo and the reverse.
2. Manual with fan base "Turbo" loaded the Silent curve. `fanWrite` then refused it (the 255 °C point fails the
   ≤105 °C check, and the 32 % top fails the ≥40 % rule), so Manual-on-Turbo never worked. Manual-on-Silent wrote the
   Turbo curve, which is louder than asked.
3. `sysctl debug.asuswmi.fan_custom=1` in Turbo would have tried to pin the fans to the Silent curve. It was refused
   for the same reason, so it never ran.
4. `test/rogcontrol_curve_test.swift` called the Silent curve "Real GA403WM Turbo firmware endpoint".

Fix: rog-control-macos branch **`fix/fan-curve-index` @ 44ee05c** (on top of `feat/gpu-mode`). `fanRead` maps policy
to curve index; the ABI is unchanged (callers still pass the policy value); AsusWmi becomes 0.3.1; the test label is
corrected. Built with `scripts/build.sh AsusWmi` (rc 0, not installed, not loaded); `scripts/test-rogcontrol.sh`
passes.

Still open after the fix: Manual with fan base **Silent** will now be refused. The real Silent curve has the 255 °C
unused point and a 32 % top, and our `fanWrite` rules reject both. Either RogControl offers only Balanced and Turbo as
Manual fan bases, or `fanWrite` accepts trailing 255 °C points that copy the previous duty. The 40 % rule is our own;
whether to relax it for a copied firmware curve is main's call.

## 5. Is 62 W at 96 °C expected, and what should each profile sustain?

Yes for Turbo. Windows Turbo lets the CPU sustain 80 W. With the fans on the Turbo curve's top point (86 %, about
6000 rpm), the HX 370 reaches its Tctl limit (~95 °C) before it reaches 80 W. 62 W at 91-96 °C under a mixed load
(Docker, the RTX powered by the gate's false trip, the video path) is that same situation. The October all-core bench
on macOS gave ~65 W steady at 85 °C in Turbo, also consistent. **The heat in Turbo is designed, not a missing limit.**

Targets to measure against (all-core sustained, AC unless stated). Sources: Notebookcheck table above, asus-armoury
ranges, our October bench.

| Profile | Sustained package (target) | Short boost | Expected Tctl under sustained all-core | Fans |
|---|---|---|---|---|
| Silent (AC) | ≤ 35 W | ≤ 65 W | ≤ ~80 °C | ≤ ~2500 rpm, often off at idle |
| Balanced (AC) | ≤ 45 W | ≤ 65 W | ≤ ~88 °C | ~3000 rpm |
| Turbo (AC) | ≤ 80 W; temperature-limited at ~95 °C in practice | 80 W | 92-96 °C | ~6000 rpm |
| Battery (Balanced / Silent) | ≤ 31 W | ≤ 40 W | – | quiet |

These are ceilings under full load. At daily load (mostly bursts), EPP decides most of the power below the ceiling.
That is why the 11-08 EPP A/B in Turbo moved 37 → 22 W without touching any limit.

## 6. The gap, and the design

**Gap 1 (preset limits): none.** macOS does what Linux and Windows do. Owner action, not code: use Balanced on AC
for daily work (≤45 W ceiling, EPP 191). This is the handoff's item 2, and it is now backed by the limit numbers.

**Gap 2 (fan-curve index): fixed** on `fix/fan-curve-index`, as described in 4.

**Gap 3 (no proof the SMI applied the limits):** the BIOS does not report PPT. Design:

- **D1, no code, test after install of anything (or now, on the owner's word):** switch to Balanced on AC, run
  `RogControl --bench 60` (it already cycles Silent / Balanced / Turbo with all CPUs busy and restores the profile). A
  pass is a sustained package within about 5 W of 35 / 45 / ≤80 W, with Tctl and rpm in the ranges in 5. If Balanced
  sustains ~60 W, the SMI does not load the limits on macOS, and D2 becomes necessary.
- **D2, only if D1 fails:** an opt-in "firmware limits" table in AsusWmi that writes the three PPT IDs after every
  profile change and every AC/DC change, using the Notebookcheck values (Silent 35/65/65, Balanced 45/65/65, Turbo
  80/80/80; battery 31/40/40). Where it goes: `AsusWmi::setValue(ASUS_SET_PROFILE)`, after the successful DEVS, behind
  a new `ASUS_SET_PROFILE_LIMITS` flag set by RogControl. It needs `fanCustomFromFirmware()` first, because of
  `requires_fan_curve`, and that only works once Gap 2 is fixed. This departs from Linux and Windows, so do it only
  with D1 evidence.
- **D3, read-back (new code, AmdCppc):** a `debug.amdcppc.limits` sysctl that asks the SMU for its PM table (the
  ryzenadj method: SMU message "transfer table to DRAM", then read STAPM limit/value, fast/slow PPT limit/value, THM
  limit). This would turn "unknown" in table 1 into measured values per profile. It sends SMU commands, so it needs an
  owner OK before it runs. Not written in this session.

**Relation to the open PRs:** #16 (EPP per profile, asusctl linked-EPP defaults) is already contained in #17
(`feat/gpu-mode`), and `fix/fan-curve-index` sits on #17. Merge order: #16 → #17 → `fix/fan-curve-index` (or rebase
it onto main after #17). The fix does not depend on GPU-mode code; it only touches `fanRead`, the ABI comment, the
version and one test label.

**What main should test after installing AsusWmi 0.3.1** (reboot needed; batch it with other changes):
1. Read-only: the fan-curve reader (or RogControl's Fans tab) shows Turbo = the 86 % curve and Silent = the 32 %
   curve with no 255 point plotted.
2. Owner's OK needed (it writes): RogControl Manual with fan base Turbo is accepted; `fan_custom` becomes 1; the
   fans do not change speed at the same Tctl (same curve, now custom); a profile change returns them to auto.
3. D1 bench above, recording package W / Tctl / rpm per profile, to fill in the measured column of table 1.

## 7. Assumptions in the handoff, questioned

- "62 W at 96 °C means limits and fan curve are left at firmware defaults": they are, but that is also what
  Linux and Windows do. The firmware default for Turbo is the 80 W limit, and 62 W is below it. The cause is the
  Turbo profile itself, plus the load.
- "Fan curve wrong for the profile": no. The EC runs the right curve. Only our read of it was wrong, which would
  have mattered for Manual mode.
- `ASUSCTL-MACOS.md` says "ppt_* status shows 0". That 0 means "not overridden", not 0 W. RogControl's popover
  label "Power limit: Profile" is correct.
- Turbo on battery: RogControl already maps Turbo to EPP 191 on battery and disables the button. Correct, since
  Armoury Crate also caps battery at Performance.
- No Linux power numbers exist for this machine. A turbostat run under Linux (each profile, all-core) would confirm
  the WM's own limits better than the WW review.

## Sources

- Linux `include/linux/platform_data/x86/asus-wmi.h`, `drivers/platform/x86/asus-wmi.c`, `asus-armoury.c` (torvalds
  master, read 2026-11-16).
- [asus-armoury: add support for GA403WM](https://lkml.iu.edu/2601.0/01127.html),
  [GA403WW](https://lkml.iu.edu/2601.2/06032.html) (Denis Benato).
- asusctl `asusd/src/ctrl_platform.rs`, `asus_armoury.rs`, `config.rs` (flukejones/asusctl main).
- [Notebookcheck, Zephyrus G14 2025 review (GA403WW)](https://www.notebookcheck.net/14-inches-with-the-GeForce-RTX-5080-Laptop-Asus-ROG-Zephyrus-G14-2025-review.1014019.0.html),
  table "Testing conditions".
- [Third-party test PDF (GA403WR, unverified)](https://www.bestlaptop.deals/products/Asus-ROG-Zephyrus-G14/test-pdf/1762872258492-asus-rog-zephyrus-g14-2025.pdf).
- This repo: `docs/ASUSCTL-MACOS.md` (October DSDT audit), rog-control-macos `docs/CPU-POWER.md`, branch
  `thermal/idle-ab` `docs/CPU-THERMALS.md`.
- The DSDT was not decompiled again in this session: there is no `iasl` on this machine. Section 1's BIOS paths
  come from the October audit.
