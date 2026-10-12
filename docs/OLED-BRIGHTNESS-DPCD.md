# OLED brightness: the panel is AUX-only, RM's backlight call does nothing (2026-10-12)

Machine: GA403WM, RTX 5060 Laptop, built-in 2880x1800 OLED (eDP, `displayId 0x200`), NullMoth 1.14.0 loaded / 1.14.2 installed.
RogControl's `Dimmer` (black click-through window) is a workaround; this page is the cause.

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

Fork `thanhnndev/nvidia-macos-driver`, branch `nvrm-edp-aux-backlight`, commit `3501a25` (based on 1.14.2):
`kexts/NVRM/nvrm_edpbl.cpp` does the DPCD writes on a private kernel RM client (pattern of `nvrm_fbinfo.cpp`) for panels
with AUX-only brightness; `nvkms_xnu_backlight()` asks it first and otherwise calls NVKMS as before. No ACPI tables
needed, so it also removes the reason for `nvrmacpibl=1` on such a panel. Boot-arg `nvrmedpbl=0|1|2`.

## Installed (2026-10-12 14:02, loaded at the next reboot)

NVRM can not be relinked here (the RM objects exist only in NullMoth's build tree), so the same code is packaged as a
kext of its own, on the fork branch after the NVRM commit:

| Commit (fork `thanhnndev/nvidia-macos-driver`, branch `nvrm-edp-aux-backlight`) | What |
|---|---|
| `3501a25` | `kexts/NVRM/nvrm_edpbl.cpp` + 9 lines in `os-nvkms-xnu.cpp`: the upstream PR |
| `2c07cf7` | machine-local packaging: `kexts/NVRMEdpBL` (own kext) + `nvrmBacklightCall()` in NVRMFB |
| `c1bfb54` | cherry-pick of the VRAM-clear patch (see `VRAM-GRANT-STALL.md`), so one NVRMFB carries both |

Worktree: `~/develop/projects/nvidia-macos-driver-ws-edpbl` (the main checkout `nvidia-macos-driver-ws` stays on
`nvrmfb-vram-clear-nontemporal`; do not switch branches there, other sessions use it).

* `NVRMEdpBL.kext` publishes a service that answers `NVRMBacklight` like NVRM does and `kIOReturnNotFound` for a panel RM
  drives. It links against NVRM (`rm_kernel_rmapi_op`, `nv_xnu_gpu_state`), which needs `OSBundleCompatibleVersion` in
  NVRM's Info.plist (nobody declared one): the install script adds that one key and keeps the original.
* `NVRMFB` asks that service first, then NVRM; a machine without the kext behaves as before.
* Boot-arg `nvrmedpbl=0|1|2`: 0 off, 1 AUX-only panels (default), 2 any panel with the AUX capability.

## How to build, install, undo (all root steps through osascript, see HANDOFF "Hard-won rules")

```sh
bash scripts/macos-build-nullmoth-local.sh                 # builds from the worktree, stages ~/efi-audit/brightness/stage
# root, osascript "with administrator privileges" (put the call in a wrapper file; quoting $? inside -e breaks AppleScript):
bash scripts/macos-aux-kc-dryrun.sh                        # builds an AuxKC in a scratch repository, installs nothing
bash scripts/macos-edpbl-install.sh                        # hash check, backup to /Library/NullMoth/edpbl-patch, rebuild AuxKC
bash scripts/macos-edpbl-install.sh --undo                 # NVRMFB and NVRM plist as they were, kext removed, AuxKC rebuilt
```

Order of undo: `macos-edpbl-install.sh --undo` first (back to the VRAM-clear-only NVRMFB), then
`macos-nvrmfb-vramclear-patch.sh --undo` (upstream 1.14.2). The VRAM-only script refuses the combined hash on purpose.
Pitfalls hit: kmutil only accepts `root:wheel` kexts (run as root); a kext needs `KMOD_EXPLICIT_DECL` (`_kmod_info`);
`kmutil` reports "could not find version compatible with 0.1" until NVRM has `OSBundleCompatibleVersion`.

## Verify after the reboot (not done yet: update this section with the result)

1. `log show --last 5m | grep NVRM-edpbl`: `display 0x200: eDP rev 0x05 caps 0x9b 0x86 ... brightness over AUX`, then
   `first brightness write`.
2. Slider and Fn+F7 / Fn+F8 dim the OLED itself; `tools/nvrm-dpcd.c` (`cc ... -framework IOKit`, no root) reads
   `0x721 = 02`, `0x722/3` = the level.
3. Turn RogControl's software dimming off (`dim` default, "Dim the built-in OLED in software"), otherwise the overlay
   dims on top. If the real brightness works, remove the `Dimmer` from RogControl or default it to off.
4. After display sleep / wake: does the level survive? (the code rewrites level and mode on every set, but nothing
   re-sends brightness if macOS does not.)
5. If the panel misbehaves: boot-arg `nvrmedpbl=0`, or the undo above. A panic at boot: OpenCore safe mode / the
   "Start once without NVIDIA driver" tool, then the undo.
