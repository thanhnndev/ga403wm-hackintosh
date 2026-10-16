# Scripts and tools: what to run, where, and how to undo it

Tiếng Việt: [SCRIPTS.vi.md](SCRIPTS.vi.md).

> ⚠️ Vibe-coded, one-laptop project (see the [README](../README.md)). Many scripts changed files as **root** on the author's
> machine. Read a script before you run it; most print their undo command. Scripts marked **author-specific** have paths or
> device IDs of the reference unit hard-coded and will not work, or will do the wrong thing, on yours.

Legend. **Where:** 🍎 macOS · 🐧 Linux · 🪟 Windows · 🖥 any. **Root:** `sudo` needed. **Safe:** read-only or has `--undo`.
"Run through osascript" means the author's agent ran them with `osascript -e 'do shell script "<file>" with administrator privileges'`;
in a normal terminal use `sudo bash <script>`.

Contents: [1. Get the prebuilt release](#1-use-the-prebuilt-release-v1) · [2. Build and install](#2-build-and-install) ·
[3. Wi-Fi credentials](#3-wi-fi-credentials) · **[4. HiDPI](#4-hidpi-looks-like-1440-x-900-step-by-step)** ·
[5. NVIDIA driver patches](#5-nullmoth-nvidia-driver-patches) · [6. EFI and OpenCore tooling](#6-efi-and-opencore-tooling) ·
[7. ESP and dual boot](#7-esp-and-dual-boot) · [8. Diagnostics and logs](#8-diagnostics-and-logs) ·
[9. One-shot session scripts (historical)](#9-one-shot-session-scripts-historical)

## 1. Use the prebuilt release (v1)

The [release](https://github.com/thanhnndev/ga403wm-hackintosh/releases) contains the kexts, apps and the CPU policy daemon, already
built (x86_64; the apps and the daemon are ad-hoc signed, the kexts are unsigned: OpenCore injects the kexts, no signature is needed), so you do not need Xcode for them. **You still need a clone of the repo** for the install scripts.

```bash
git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
(cd ~/Downloads && shasum -a 256 -c SHA256SUMS.txt)    # files you did not download are reported as missing; that is fine
mkdir -p build && for z in ~/Downloads/*.kext.zip; do ditto -x -k "$z" build/; done      # build/itlmt7925.kext ...
ditto -x -k ~/Downloads/AmdCppcPolicy.zip build/ && chmod +x build/AmdCppcPolicy
for a in RogControl ItlWiFi TapGuard; do
  ditto -x -k ~/Downloads/$a.app.zip /Applications/
  xattr -dr com.apple.quarantine /Applications/$a.app       # ad-hoc signed, not notarised: Gatekeeper blocks it otherwise
done
```

Then use the same scripts as for a local build: `scripts/macos-install-kext.sh <name>` (kexts), `scripts/macos-amdcppc-policy-install.sh`
(daemon). Wi-Fi credentials must be injected into `itlmt7925.kext` **before** installing it ([section 3](#3-wi-fi-credentials)).
Apps unzipped into `/Applications` do not start at login by themselves: RogControl and ItlWiFi have "Open at login" in their
settings; TapGuard only gets a login item through `scripts/build-tapguard.sh --install` from a source build.

## 2. Build and install

| Script | Where | Root | What it does | Undo |
|---|---|---|---|---|
| `scripts/build.sh [kext...]` | 🍎 | no | builds `itlmt7925`, `ItlXhciKick`, `ItlDiag`, `AmdCppc`, `MtkBtFw`, `AsusWmi`, `BtLeDlFix` into `build/*.kext` (Xcode CLT; clones MacKernelSDK and, for `BtLeDlFix`, Lilu into `build/`) | delete `build/` |
| `scripts/macos-install-kext.sh <name>` | 🍎 | sudo (asks) | copies `build/<name>.kext` into the booted ESP's `EFI/OC/Kexts`, old one to `EFI/OC/Kexts-backup/`; keeps Wi-Fi credentials for `itlmt7925`. `config.plist` is not touched: the kext must already be listed | `--undo <name>` |
| `scripts/build-rogcontrol.sh [--install]` | 🍎 | no | builds `RogControl.app`; `--install` copies to `/Applications` and starts it at login | quit app, delete it, `~/Library/LaunchAgents/com.itlmt7925.RogControl.plist` |
| `scripts/build-itlwifi.sh [--install]` | 🍎 | no | same for `ItlWiFi.app` | same pattern |
| `scripts/build-tapguard.sh [--install]` | 🍎 | no | same for `TapGuard.app` (Accessibility permission) | same pattern |
| `scripts/build-amdcppc-policy.sh` | 🍎 | no | builds the `AmdCppcPolicy` daemon into `build/` | |
| `scripts/macos-amdcppc-policy-install.sh [--undo]` | 🍎 | **root** (osascript / sudo) | installs `/Library/PrivilegedHelperTools/com.itlmt7925.AmdCppcPolicy` and its LaunchDaemon; keeps a backup of the old binary | `--undo` (CPPC stays enabled until reboot) |
| `scripts/test-rogcontrol.sh` | 🍎 | no | fan-curve decoder test with real firmware samples; never writes hardware | |
| `scripts/linux-install-kext.sh <name>` | 🐧 | no (after `setup-linux-access.sh`) | installs a kext built on macOS into the ESP from Linux (needed while an old `ItlDiag` held the ESP open). **Author-specific paths** (`/mnt/macos-vol0`) | `--undo <name>` |

Check after installing: `sysctl debug.asuswmi.status`, `sysctl debug.amdcppc.freq`, `ioreg -rc itlmt7925 -d1 | grep wifi-`.

## 3. Wi-Fi credentials

There is no native Wi-Fi yet, so the SSID and password are written into the kext ([INSTALL.md §4](INSTALL.md#4-wi-fi-inject-your-network)).

| Script | Where | What | Notes |
|---|---|---|---|
| `scripts/inject-creds.ps1 -Kext <path> [-Ssid a,b]` | 🪟 elevated PowerShell | reads the saved Wi-Fi profiles of the PC (`netsh wlan ... key=clear`) and fills `itl_ssid`/`itl_psk` (up to 4 networks) in the kext's `Info.plist` | passwords are never printed, but end up in **plain text** in the kext. Without `-Ssid` it uses the connected profile |
| PlistBuddy one-liner | 🍎 | same keys by hand, see INSTALL.md | |
| `ItlWiFi.app` | 🍎 | scan/join after boot; saved networks in `~/Library/Application Support/ItlWiFi/networks.json` (0600) | the first connection still needs injected credentials |

To remove credentials: re-install the clean kext from the release/CI artifact (empty keys).

## 4. HiDPI ("looks like 1440 x 900"), step by step

**What you get.** True **2x HiDPI, the same as 200 % scaling on Windows**: the 2880x1800 OLED stays at its native 120 Hz raster and macOS renders a
1440x900-point desktop with every pixel doubled ("looks like 1440 x 900"). 2x is the supported scale. Fractional scales (1680x1050, 1280x800, ...) are
not supported: the NullMoth driver cannot do scaled modes (below). Works from System Settings → Displays after the steps below (owner-confirmed
2026-10-11/12, NullMoth 1.13/1.14, [HANDOFF](HANDOFF.md) notes 7 and 9). Not verified on any other unit.

**Why it needs a trick.** macOS builds HiDPI modes on top of the native mode, but the NVIDIA framebuffer (NVRMFB) never marks its
modes "valid for HiRes", so WindowServer refuses the density-2 copy of the native mode (`Mode 65792 not available`). A display
override adds one scaled mode that has the HiRes flag and the **same size as the raster** (`2880 1800 1 0x800000`), so no scaled
NVKMS mode set is needed. Asking for any mode that *is* scaled (1680x1050, 1280x800, and the "low resolution" 1440x900 that is
a 1440x900 surface scaled by the GPU) makes the mode set fail and the screen goes **black**.

### Before you start

* NullMoth driver installed and the desktop works at 2880x1800 @ 120 Hz. Keep **2880 x 1800** selected in System Settings until the end.
* The installer only runs for the reference panel, vendor/product `4c83:419c`. Check yours:
  ```bash
  ioreg -l -w0 | grep -E '"DisplayVendorID" = |"DisplayProductID" = ' | sort -u
  # reference panel: DisplayVendorID = 19587 (0x4c83), DisplayProductID = 16796 (0x419c)
  ```
  Other IDs: the script stops. You may edit `VID=` and `PID=` (and the `case` check) at your own risk; the entry assumes a
  2880x1800 native mode.
* Know the way back (undo below) and have a second way to reach the machine (SSH or Recovery).

### Install

```bash
cd ga403wm-hackintosh
# 1. let WindowServer build HiDPI modes at all (this is what one-key-hidpi sets; there is no HiDPI kext)
sudo defaults write /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled -bool true
# 2. install the display override for the built-in panel (no EDID change, no prefs deleted)
bash scripts/macos-install-hidpi.sh            # asks for sudo; writes /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c
# 3. reboot
sudo shutdown -r now
```

### Switch (with a safety net first)

```bash
swiftc -O tools/hidpi-try.swift -o /tmp/hidpi-try
/tmp/hidpi-try list               # modes; HiDPI rows are marked; `list --all` also shows hidden ones and their flags
/tmp/hidpi-try 1440               # switches to "looks like 1440 x 900"; press Return within 15 s to keep it
/tmp/hidpi-try 1440 --keep        # same, and save it as the permanent setting once confirmed
```

* If you do not press Return within 15 s (black screen, nothing typed) the tool switches back by itself. It only accepts a
  mode whose pixel size equals the native 2880x1800, so it never triggers a scaled mode set.
* `list` first prints `current: ... looks like 1440x900  pixels 2880x1800  120 Hz  flags 0x00800003  HiDPI` (the mode in use), and in the
  table the same mode appears as `id 0x80001001 ... pixels 2880x1800 ... flags 0x00800003` (checked on the reference unit, 2026-10-12, after
  a reboot; `system_profiler` then says `UI Looks like: 1440 x 900 @ 120.00Hz`). The HiDPI row is the one with flag `0x00800000`. If it only says
  `no HiDPI mode is offered`, the pref (step 1) or the override (step 2) is missing, or you did not reboot.
* After a confirmed `--keep` (or once you have seen it work) **System Settings → Displays → "1440 x 900"** also works on the
  reference unit and the refresh rate stays 120 Hz. Do not pick 1680x1050 or 1280x800, and do not pick a "1440 x 900" that is
  a low-resolution mode (mode id `0x80001000` in `list --all`; the working one is HiDPI with 2880x1800 pixels).
* Verify: `system_profiler SPDisplaysDataType | grep -i -E 'resolution|looks like'`.

### Undo

```bash
bash scripts/macos-install-hidpi.sh --undo                                                     # removes the override
sudo defaults delete /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled
sudo shutdown -r now
```

### If the screen stays black

1. If `hidpi-try` was used it reverts by itself after 15 s without Return. Otherwise SSH in (if enabled) or go to step 2 and run the
   undo; removing the override only takes effect after a reboot.
2. Otherwise boot **macOS Recovery** from the OpenCore picker, open Terminal, mount your Data volume in Disk Utility, and:
   ```bash
   ls /Volumes                                  # find the Data volume, e.g. "Macintosh HD - Data"
   D="/Volumes/Macintosh HD - Data"
   rm -f "$D/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c"
   ```
   Reboot. If the saved mode is still wrong, also remove the WindowServer display prefs
   (`$D/Library/Preferences/com.apple.windowserver.plist` and `$D/Library/Preferences/ByHost/com.apple.windowserver.*.plist`);
   macOS rebuilds them. Back them up first.
3. Last resort: the OpenCore picker entry *"Start once without NVIDIA driver"* (added by the NullMoth setup) gets you a
   desktop without the driver. **Do not** use *"1401: Remove NVIDIA driver"* for this: it restores the pre-NullMoth
   `config.plist` and you lose your USB map, ACPI patch and boot-args.
4. From Linux, `scripts/remove-display-override.sh` deletes the override directory on the APFS volume. It uses the experimental
   `linux-apfs-rw` driver, hard-codes `/dev/nvme0n1p4` and `/mnt/macos-vol0` (**author-specific**) and should be your last choice.

### What is known to fail (so you do not repeat it)

| Attempt | Result |
|---|---|
| Scale-resolutions entries `w h 1 0x200000` | `0x200000` = *valid for mirroring* only: mirror-only modes, CoreGraphics drops them |
| Apple's own format `w h 9 0xa00000` | still mirror-only; the 2880x1800 entry is dropped as a duplicate of the native mode |
| Selecting the density-2 copy of the native mode | refused: flag `0x80000000`, `Mode 65792 not available` (code 1007) |
| 1680x1050 / 1280x800 / low-resolution 1440x900 | NVKMS test commit fails, **black screen** with flips still running |
| Replacing the EDID with a 120 Hz base timing | not needed any more (driver offers the DisplayID 120 Hz mode itself); tooling was removed |

Details and evidence: [HANDOFF.md](HANDOFF.md) item 7, [NULLMOTH.md](NULLMOTH.md).

| Script / tool | Where | Root | What |
|---|---|---|---|
| `scripts/macos-install-hidpi.sh [--undo]` | 🍎 | sudo (inside) | the override above; **panel-specific (`4c83:419c`)** |
| `tools/hidpi-try.swift` | 🍎 | no | list modes (CoreGraphics and WindowServer's private table), switch with 15 s auto-revert, `--keep` |
| `scripts/macos-apply-2026-10-11c.sh` | 🍎 | sudo | historical one-shot that did the pref + override + other things; use the steps above instead |
| `scripts/remove-display-override.sh` | 🐧 | root | remove the override from Linux (experimental APFS write) |

## 5. NullMoth (NVIDIA driver) patches

These layer **local patches on top of the upstream NullMoth driver** (installed with its own `install.sh`). They need root, rebuild the
auxiliary kernel collection and take effect after a reboot. They are for the reference setup (NullMoth **1.14.2**): each checks hashes
and refuses other versions. See [NULLMOTH.md](NULLMOTH.md). Do not run them blind.

| Script | Where | Root | What | Undo |
|---|---|---|---|---|
| `scripts/macos-nvrmfb-vramclear-patch.sh` | 🍎 | root | legacy, 1.14.2 only: installs the VRAM-clear-only NVRMFB (`movnti`); superseded by `macos-edpbl-install.sh`, which installs the combined build from the fork branch `ga403wm`. **Author-specific paths** (`~/efi-audit/upgrade-1.14.2`) | `--undo` |
| `scripts/macos-nvrmfb-vramclear-ab.sh` | 🍎 | root | **legacy**: A/B of the clear modes (needs the VRAM-clear NVRMFB, dropped 2026-10-13, tag `ga403wm-with-vramclear`) | |
| `scripts/macos-vramtest.sh` | 🍎 | sudo | times an 8 MB VRAM grant 5x via `debug.nvrmfb_vramtest` | |
| `scripts/macos-build-nullmoth-local.sh` | 🍎 | no | builds NVRMFB + `NVRMEdpBL.kext` from the fork worktree, stages them with `SHA256SUMS`. **Author-specific** (needs the fork checkout and open-gpu-kernel-modules headers) | |
| `scripts/macos-aux-kc-dryrun.sh` | 🍎 | root | builds a scratch auxiliary kernel collection and lists it; installs nothing. **Author-specific paths** | |
| `scripts/macos-edpbl-install.sh` | 🍎 | root | installs `NVRMEdpBL` (OLED brightness over DPCD AUX) + the NVRMFB that calls it. **Author-specific paths** ([OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md)) | `--undo`; boot-arg `nvrmedpbl=0` disables at runtime |
| `scripts/macos-nullmoth-vramclear.sh` | 🍎 | sudo | **obsolete**: byte patch for NullMoth **1.13.0** only (refuses anything else) | `--undo` |
| `scripts/macos-ws-upload-install.sh` | 🍎 | root | **dropped** experiment (NullMoth PR #139 candidate); kept for the record | `--undo` |
| `scripts/zshrc-nullmoth.sh` | 🍎 | no | `source` it from `~/.zshrc`: drops an unwritable `MESA_SHADER_CACHE_DIR` inherited from root so Metal programs keep their shader cache | remove the line |

## 6. EFI and OpenCore tooling

| Script | Where | What |
|---|---|---|
| `scripts/export-efi.py` | 🖥 | writes `efi/OC` from a working EFI with every machine identifier replaced by placeholders (for publishing); empties `Misc.Entries` too, because its device paths carry the SSD's NVMe EUI-64 and partition GUID |
| `scripts/check-efi-privacy.py [plist...]` | 🖥 | fails if `config.plist` carries anything but the placeholders, or an NVMe EUI-64 / GPT GUID device path; also runs in CI |
| `tools/occonfig.py` | 🖥 | typed `get`/`set`/`add`/`del`/`args`/`check`/`diff` for `config.plist` (always keep a backup copy; use `--dry` first) |
| `scripts/build-ocvalidate.sh` | 🐧 | builds `ocvalidate` for the exact OpenCore commit (needs git, make, gcc, ~120 MB download) |
| `.github/workflows/opencore.yml` | CI | builds OpenCore 1.0.9 with `patches/opencore/fix-zen5-fsb.diff`; also attached to releases |

## 7. ESP and dual boot

| Script | Where | Root | What | Notes |
|---|---|---|---|---|
| `scripts/restore-limine-entry.ps1` | 🪟 elevated | no | re-creates the UEFI entry of Limine/another Linux loader that lost its `Boot####` variable | prints the undo (`bcdedit /delete {guid}`) |
| `scripts/esp-automount.sh [--install\|--uninstall]` | 🍎 | password dialog | mounts the internal ESP at `/Volumes/ESP` at login, owned by you | |
| `scripts/esp-cleanup.sh [--apply]` | 🐧 | no | lists, then **moves** (never deletes) leftovers from the ESP into `~/ga403-esp-trash/` | dry run by default; author-specific `/boot` |
| `scripts/setup-linux-access.sh [--undo]` | 🐧 | root | one-time `/etc/fstab` change so the ESP and the macOS volume can be read without sudo | `--undo` restores fstab |
| `scripts/clear-nvram.ps1` | 🪟 elevated | no | deletes the `itl*` diagnostic NVRAM variables so firmware NVRAM has room again | |

More on losing boot entries: [DUAL-BOOT.md](DUAL-BOOT.md).

## 8. Diagnostics and logs

All are read-only unless stated. **Redact before posting:** logs contain MAC addresses, SSIDs and sometimes serials. The `macos-*`
probes mask the obvious ones; check anyway.

| Script | Where | Root | What |
|---|---|---|---|
| `scripts/macos-nullmoth-probe.sh [--window]` | 🍎 | no | snapshot of NVIDIA driver and display state into `~/efi-audit/probe-<time>/` |
| `scripts/macos-ws-system-collect.sh` | 🍎 | sudo for spindump/sample | system-wide stacks and counters (WindowServer CPU) |
| `scripts/macos-ws-frame-sample.sh` | 🍎 | sudo for `sample` | samples WindowServer while `tools/framepace.swift` drives a known load |
| `scripts/macos-ws-cpu.py` | 🍎 | no | WindowServer CPU/flip counters, labelled runs |
| `scripts/macos-ws-pat-check.sh` | 🍎 | root | per-CPU PAT check (needs `AmdCppc` 0.2.1), clear A/B, desktop CPU. See [WINDOWSERVER-RESEARCH.md](WINDOWSERVER-RESEARCH.md) |
| `scripts/linux-collect-logs.sh [--unified]` | 🐧 | no (after setup) | copies OpenCore logs, `ITLLOG.BIN`, whitelisted NVRAM vars, panic reports from the Linux side into `~/ga403-logs/` |
| `scripts/decode-unified-log.sh <archive> "<UTC since>"` | 🐧 | no | decodes a macOS unified log without macOS (builds mandiant/macos-unifiedlogs once, needs cargo) |
| `scripts/recovery-dump.sh` | 🍎 Recovery | no | ioreg/system_profiler/kextstat/dmesg plus a typing trace to a USB stick (USB lag work) |
| `scripts/usblog.ps1` | 🪟 elevated | no | prepare/read `ITLLOG.BIN` written by `ItlDiag` on the ESP or a stick |
| `scripts/read-nvram.ps1` | 🪟 elevated | no | prints `boot-args` and the `itl*` NVRAM variables (see [DEBUGGING.md](DEBUGGING.md)) |
| `tools/cpuclock.c`, `tools/framepace.swift` | 🍎 | no | single-thread clock probe; frame pacing probe |

## 9. One-shot session scripts (historical)

`scripts/macos-apply-2026-10-11.sh`, `...b.sh`, `...c.sh`, `...d.sh` and `scripts/linux-apply-2026-10-11.sh` are the author's
sudo batches from one day of bring-up (VRAM clear, HiDPI, ESP config clean-up, boot-time fixes, `AmdCppc` install...). They are kept
as a record of what was changed and with which undo command, **not** as installers: they edit the author's ESP `config.plist`, use
author-specific paths and assume NullMoth 1.12-1.13. Use the numbered sections above instead.

## Conventions the scripts follow (and where they do not yet)

* back up before replacing (`*.bak-<time>`, `Kexts-backup/`, `config.plist.<name>`), print the undo, never print secrets;
* root only for the step that needs it;
* author-specific paths are on the standardisation list in the [roadmap](ROADMAP.md#codebase-standardisation).
