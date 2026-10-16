# OLED brightness: the panel is AUX-only, RM's backlight call does nothing (2026-10-12)

Machine: GA403WM, RTX 5060 Laptop, built-in 2880x1800 OLED (eDP, `displayId 0x200`), NullMoth 1.14.0 loaded / 1.14.2 installed.
RogControl used to carry a software `Dimmer` (black click-through window) as a workaround; it was removed on 2026-10-12. This page is the cause.

## Evidence

`tools/nvrm-dpcd.c` opens the NVRM user client from user space (no root), allocates a root client / device /
subdevice / `NV04_DISPLAY_COMMON` and reads the panel's DPCD through `NV0073_CTRL_CMD_DP_AUXCH_CTRL` (the control NVKMS
uses for DPCD). `./nvrm-dpcd 0x200` prints:

```
DPCD 0x000: 14 1e c4 01 ...        DP 1.4, HBR3, 4 lanes
DPCD 0x700: 05 9b 86 14            eDP 1.4b, cap1 0x9b, cap2 0x86
DPCD 0x720: 00 00 00 00 0b 0b 0b 00   display control 0, mode 0, level 0x0000, PWMGEN bits 11
RM get brightness (type 1..3): status 0x1b NV_ERR_INSUFFICIENT_PERMISSIONS   (privileged control, kernel clients only)
```

Decoded (VESA eDP names):

* `0x701 = 0x9b`: TCON backlight adjustment capable, **BACKLIGHT_AUX_ENABLE_CAP clear** (the BL_EN pin does the enable).
* `0x702 = 0x86`: **BRIGHTNESS_PWM_PIN_CAP clear**, **BRIGHTNESS_AUX_SET_CAP set**, 16-bit level, vblank update.
  So the panel has no PWM input at all: the only brightness control is DPCD 0x722/0x723 in mode 0x721 = 2.
* `0x721 = 0`, `0x722/3 = 0`: the panel is in its default mode (PWM pin) and RM never switched it. NVKMS's
  `nvKmsSetBacklight` (-> `NV0073_CTRL_CMD_SPECIFIC_SET_BACKLIGHT_BRIGHTNESS`, handled in the GSP firmware, source not
  available) returns success while the registers keep these values.
* Writing by hand works at register level: `0x722/3 = 07 ff` then `0x721 = 02` is accepted and reads back
  (`nvrm-dpcd 0x200 test` steps 100 / 50 / 12 / 100 % and restores `00 00 00 00`). Whether the OLED visibly dims is the
  open observation (the test cannot see the panel).

## Fix

Fork [`thanhnndev/nvidia-macos-driver`](https://github.com/thanhnndev/nvidia-macos-driver), branch **`ga403wm`** (upstream v1.15.0 + the commits below; first developed as
`nvrm-edp-aux-backlight`, commit `3501a25`, based on 1.14.2):
`kexts/NVRM/nvrm_edpbl.cpp` does the DPCD writes on a private kernel RM client (pattern of `nvrm_fbinfo.cpp`) for panels
with AUX-only brightness; `nvkms_xnu_backlight()` asks it first and otherwise calls NVKMS as before. No ACPI tables
needed, so it also removes the reason for `nvrmacpibl=1` on such a panel. Boot-arg `nvrmedpbl=0|1|2`.

## Installed (2026-10-12 14:02, loaded at the next reboot)

NVRM can not be relinked here (the RM objects exist only in NullMoth's build tree), so the same code is packaged as a
kext of its own, on the fork branch after the NVRM commit:

| Commit (original numbers on the 1.14.2-based branch `nvrm-edp-aux-backlight`; cherry-picked onto `ga403wm`) | What |
|---|---|
| `3501a25` | `kexts/NVRM/nvrm_edpbl.cpp` + 9 lines in `os-nvkms-xnu.cpp`: the upstream PR |
| `2c07cf7` | machine-local packaging: `kexts/NVRMEdpBL` (own kext) + `nvrmBacklightCall()` in NVRMFB |
| ~~`c1bfb54`~~ | cherry-pick of the VRAM-clear patch; **dropped 2026-10-13** (see `VRAM-GRANT-STALL.md`), `ga403wm` has no NVRMFB change except the hook |

Author's worktree: `~/develop/projects/nvidia-macos-driver-ws-ga403` (branch `ga403wm`). Anyone else: clone the fork, branch
`ga403wm`, see [INSTALL.md §7](INSTALL.md#7-nvidia-driver-rtx-5060--the-oled). The commit that added `KMOD_EXPLICIT_DECL` (needed by
`kmutil`) was missing from the old branch and is part of `ga403wm`.

* `NVRMEdpBL.kext` publishes a service that answers `NVRMBacklight` like NVRM does and `kIOReturnNotFound` for a panel RM
  drives. It links against NVRM (`rm_kernel_rmapi_op`, `nv_xnu_gpu_state`), which needs `OSBundleCompatibleVersion` in
  NVRM's Info.plist (nobody declared one): the install script adds that one key and keeps the original.
* `NVRMFB` asks that service first, then NVRM; a machine without the kext behaves as before.
* Boot-arg `nvrmedpbl=0|1|2`: 0 off, 1 AUX-only panels (default), 2 any panel with the AUX capability.

## Status with upstream 1.15.0 (2026-10-13)

1.15.0 ("the last release for macOS 15") does not touch the backlight: `git grep -i -E 'dpcd|edpbl|aux.?backlight'` over its
`kexts/` is empty, and the `NVRMFB` diff against 1.14.7 is display power on wake, BAR1 accounting and ultrawide modes. The panel is
still AUX-only and RM's `SET_BACKLIGHT_BRIGHTNESS` is still a no-op for it, so the patch is still needed. `ga403wm` was rebased
onto v1.15.0 without conflicts and the same `NVRMEdpBL` (`433dfcbf...`) and a rebuilt `NVRMFB` (`ddabaa59...`) were installed on top
of the upstream package. Per-concern PR branch (without the VRAM clear and docs): `nvrm-edp-aux-backlight` on the fork. Not yet
verified on 1.15.0: see "Verify after the reboot".

## How to build, install, undo (all root steps through osascript, see HANDOFF "Hard-won rules")

```sh
bash scripts/macos-build-nullmoth-local.sh <fork checkout> # builds from the fork branch ga403wm, stages $BRIGHT_DIR/stage (~/efi-audit/brightness)
# root, osascript "with administrator privileges" (put the call in a wrapper file; quoting $? inside -e breaks AppleScript):
bash scripts/macos-aux-kc-dryrun.sh                        # builds an AuxKC in a scratch repository, installs nothing
bash scripts/macos-edpbl-install.sh                        # hash check, backup to /Library/NullMoth/edpbl-patch, rebuild AuxKC
bash scripts/macos-edpbl-install.sh --undo                 # NVRMFB and NVRM plist as they were, kext removed, AuxKC rebuilt
```

Undo: `macos-edpbl-install.sh --undo` puts the upstream NVRMFB back (and removes the kext). Installing a different overlay
build needs `--undo` first (the script accepts only upstream's NVRMFB, the staged build or the 1.14.2 VRAM-only build as "before").
Pitfalls hit: kmutil only accepts `root:wheel` kexts (run as root); a kext needs `KMOD_EXPLICIT_DECL` (`_kmod_info`);
`kmutil` reports "could not find version compatible with 0.1" until NVRM has `OSBundleCompatibleVersion`.

## Verify after the reboot

**Result 2026-10-12 (owner-confirmed): brightness works** through `NVRMEdpBL`. Measured on the same day on the reference unit
(macOS 15.8.1, NullMoth 1.14.2 + `NVRMEdpBL`, boot-arg `nvrmacpibl=1`); read-only DPCD reads with the prebuilt `nvrm-dpcd 0x200`,
brightness set through `DisplayServicesSetBrightness`:

| # | Item | Result |
|---|---|---|
| 1 | NVRM-edpbl log | ✅ both boots of the day: `display 0x200: eDP rev 0x05 caps 0x9b 0x86: brightness over AUX, 2 byte(s), 11 bits, max 2047`, then `first brightness write: 100% = level 2047 of 2047` ~2 s later |
| 2 | DPCD follows the slider | ✅ `0x720..0x723` after `set`: 0.5 -> `00 02 04 00`, 0.25 -> `00 02 02 00`, 0.1 -> `00 02 00 cd`, 0.6 -> `00 02 04 cc`, 1.0 -> `00 02 07 ff` (`0x721 = 02`, `0x722/3` = level). Readback through `DisplayServicesGetBrightness` equals the value set |
| 2b | Fn+F7 / Fn+F8 and "the panel itself gets dimmer" | 🟡 the keys and the **visible** dimming need a person: not measured here (the register path is proven, the eyes are not) |
| 3 | RogControl software dimmer | ✅ removed from the code (`Dimmer`, the `dim` setting and both toggles), so no overlay can stack on top of the real dimming. An older installed build keeps the overlay until it is replaced (`scripts/build-rogcontrol.sh --install`) |
| 4 | Display sleep / wake x3 at 0.6 | ✅ level `04 cc` and `DisplayServicesGetBrightness` = 0.6 after each wake (one DPCD read failed while the display was asleep, as expected) |
| 5 | **System** sleep / wake | ⚪ not measured (system sleep is not reliable yet: [ROADMAP](ROADMAP.md) workstream 22) |

Observed oddity, not explained: right after boot the first `set 1.0` left `0x721 = 01`, level `00 00` (the firmware's default path) and
only later writes of 1.0 gave `0x721 = 02`, level `07 ff`. Brightness at 100 % was correct in both cases.

The original checklist, for re-runs:

1. `log show --last 5m | grep NVRM-edpbl`: `display 0x200: eDP rev 0x05 caps 0x9b 0x86 ... brightness over AUX`, then
   `first brightness write`.
2. Slider and Fn+F7 / Fn+F8 dim the OLED itself; `tools/nvrm-dpcd.c` (`cc ... -framework IOKit`, no root) reads
   `0x721 = 02`, `0x722/3` = the level.
3. Make sure no RogControl build older than 2026-10-12 is running (those draw the software-dimming overlay on top of
   the real dimming); the current source has no `Dimmer`.
4. After display sleep / wake: does the level survive? (the code rewrites level and mode on every set, but nothing
   re-sends brightness if macOS does not.)
5. If the panel misbehaves: boot-arg `nvrmedpbl=0`, or the undo above. A panic at boot: OpenCore safe mode / the
   "Start once without NVIDIA driver" tool, then the undo.
