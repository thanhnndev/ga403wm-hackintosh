# Installing macOS 15 on the ASUS ROG Zephyrus G14 (GA403WM)

Tiếng Việt: [INSTALL.vi.md](INSTALL.vi.md).

> ⚠️ **Vibe-coded, one-laptop project.** Read the warning in the [README](../README.md). This guide is the path that worked on
> the reference unit (BIOS GA403WM.310, 2880x1800 OLED, RTX 5060). It is not a polished installer. If a step surprises you,
> stop and ask in an issue; do not improvise on the ESP.
>
> **macOS 15 (Sequoia) only.** macOS 26 is not supported and not tested; do not install it and do not accept a major update.

## 0. What you need

* A GA403WM (other GA403 variants: untested). Everything on the disk you install to will be reachable by experimental kexts:
  **back up first**. Keep a Windows/Linux recovery USB.
* A second computer, ideally a Mac, to make the installer and build the kexts. (A Mac is needed to build the kexts and the
  apps; CI builds the kexts for you if you have no Mac, but not the apps.)
* A USB stick (16 GB+) for OpenCore and, separately, a USB stick or disk (32 GB+) for the macOS installer.
* A way to get online while installing: **USB Ethernet** or **Android USB tethering** (`HoRNDIS.kext` is in the EFI). Our Wi-Fi
  works at full link speed but only through our own driver, which has no native Wi-Fi integration: for the 16 GB installer a wired / tethered link is still the safer choice.
* Time. The first boot takes minutes, and you will reboot a lot.

### Dual-booting

Windows and Linux can stay: macOS gets its **own** partition/disk and everything is started from the OpenCore picker. Read
[DUAL-BOOT.md](DUAL-BOOT.md) first (shrinking partitions is the risky step; UEFI entries can disappear after *Reset NVRAM*).
The reference machine runs OpenCore from the internal ESP, shared with Windows and Limine.

## 1. BIOS / firmware settings

| Setting | Value | Why |
|---|---|---|
| GPU mode (Armoury Crate in Windows, or BIOS) | **Ultimate** (MUX: dGPU only) | In Hybrid mode the OLED is wired to the AMD iGPU, macOS has no driver for it and the NVIDIA driver finds `0 displays`. Set it from Windows, once. |
| Above 4G Decoding | **ON** | the NVIDIA driver resizes the GPU BAR |
| CSM | **OFF** | |
| Secure Boot | **OFF** | OpenCore is not signed |
| Fast Boot | OFF | |

BIOS tested: `GA403WM.310`. Update or downgrade at your own risk; report what you tried.

## 2. Get the kexts and tools

You need two groups. Put them in a scratch folder, **not** on the ESP yet.

### 2a. Kexts from this repository

Pick one:

* **Release v1** (recommended): download the `.kext.zip` files, `SHA256SUMS.txt` and the rest from [Releases](https://github.com/thanhnndev/ga403wm-hackintosh/releases);
  unzip instructions, apps and the CPU daemon are in [SCRIPTS.md §1](SCRIPTS.md#1-use-the-prebuilt-release-v1). The release also has the patched OpenCore and
  `EFI-reference.zip`, so 2c below is already done for you.
* **CI artifact:** Actions → `build-kexts` → latest run → artifact `kexts`.
* **Build on a Mac** (Xcode command line tools):
  ```bash
  git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
  bash scripts/build.sh            # builds every kext into build/*.kext
  ```

Which kexts: `itlmt7925` (Wi-Fi), `ItlXhciKick` (USB, **mandatory**), `AsusWmi`, `AmdCppc`, `MtkBtFw`, `BtLeDlFix`, optionally
`ItlDiag`. What each does: [COMPONENTS.md](COMPONENTS.md).

### 2b. Third-party kexts

Download each from upstream; the list with versions and hashes is [../efi/KEXTS.md](../efi/KEXTS.md) and
[../efi/kexts.json](../efi/kexts.json) (Lilu, VirtualSMC, AppleALC, VoodooI2C, USBToolBox, HoRNDIS, AMFIPass, BlueToolFixup,
...). Newer releases are usually fine; the hashes are there to reproduce the exact setup.

### 2c. Patched OpenCore

Stock OpenCore 1.0.9 computes the wrong bus frequency on Zen 5 (timers fire ~10x early). Get the patched build from the
`opencore` workflow (Actions → `opencore` → run it manually → artifact `opencore-zen5-fsb`) or build OpenCore yourself with
[`patches/opencore/fix-zen5-fsb.diff`](../patches/opencore/fix-zen5-fsb.diff). Also download the OpenCore 1.0.9 drivers
(`HfsPlus.efi`, `OpenRuntime.efi`, `ResetNvramEntry.efi`).

## 3. Assemble the EFI

> 📦 The author's tested **standard EFI** will be uploaded to the release later (this guide will be updated). Until then, assemble your own from
> the sanitized reference below.

Layout on the OpenCore USB stick (FAT32/GPT, ESP):

```
EFI/
  BOOT/BOOTx64.efi
  OC/
    OpenCore.efi          <- the patched one
    config.plist          <- from efi/OC/config.plist, edited below
    ACPI/*.aml            <- from efi/OC/ACPI/
    Drivers/              <- HfsPlus.efi OpenRuntime.efi ResetNvramEntry.efi
    Kexts/                <- everything listed in config.plist > Kernel > Add
```

Then edit `config.plist` (with `tools/occonfig.py`, ProperTree or OpenCore Configurator; run `ocvalidate` from the same
OpenCore release afterwards):

1. **SMBIOS: generate your own** `PlatformInfo > Generic`: `SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM`
   (`macserial`/GenSMBIOS, model `MacBookPro16,2`). The repo has `CHANGE_ME_*` placeholders. Never publish yours.
2. **Core count:** the four "Force cpuid_cores_per_package" patches carry `0x0c` (12 cores = HX 370). Keep it on a GA403WM
   with that CPU.
3. **Boot-args** (reference, trimmed for daily use):
   ```
   -vi2c-force-polling nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
   amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 -nvrmnobootscreen nvrmacpibl=1
   itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6
   ```
   Add `-v debug=0x100 keepsyms=1` while installing / bringing up; drop them later (boot is faster without verbose output; Cmd+V in the picker gives verbose once).
   Meaning of each: [../efi/README.md](../efi/README.md#boot-args-reference-machine).
4. **USB map:** `Kexts/UTBMap.kext` (in the release's `EFI-reference.zip`) is the author's map for this laptop (four AMD xHCI
   controllers, enabled in `config.plist`); `UTBDefault.kext` stays disabled. It only fits the same model: on a different
   machine, map your ports with the USBToolBox tool instead. The internal keyboard `0b05:19b6` must stay mapped as internal.
5. `SSDT-Disable_Network_GPP5.aml` must stay **disabled** (otherwise macOS cannot see the Wi-Fi card).

Do **not** run NullMoth's "1401 Build" on a config you edited by hand: it overwrites `config.plist`.

## 4. Wi-Fi: inject your network

> **Two modes exist.** The default (this section) is the legacy mode of `itlmt7925.kext`: Wi-Fi appears as Ethernet and the
> network is injected below. The optional native mode (`itlmt7925Native.kext` + boot-args `itlmt_native=1 itlmt_native_if=1
> itlmt_native_dp=1 itlmt_fast=6`) gives a real Wi-Fi interface and needs no injection; it works but is still being tested.
> What to set, how to check and how to go back: [WIFI-DRIVERS.md](WIFI-DRIVERS.md).

In legacy mode `itlmt7925.kext` has to be told the network (native mode joins from the Wi-Fi menu instead,
[WIFI-DRIVERS.md](WIFI-DRIVERS.md)). In legacy mode the SSID and password live in the kext's `Info.plist`, **in plain text**, and the driver
connects by itself after boot (boot-args `itlmt_m2=1 itlmt_m3=1`). Up to **4 networks**, in priority order.

**Windows (reads the profiles saved on the PC, elevated PowerShell):**

```powershell
.\scripts\inject-creds.ps1 -Kext 'E:\EFI\OC\Kexts\itlmt7925.kext' -Ssid 'HomeWifi','Phone-hotspot'
```

**macOS (PlistBuddy) or any editor:** the keys `itl_ssid`, `itl_psk`, `itl_ssid2`, `itl_psk2`, ..., `itl_ssid4`, `itl_psk4` sit in
the `itlmt7925` personality of `itlmt7925.kext/Contents/Info.plist`:

```bash
P=itlmt7925.kext/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :IOKitPersonalities:itlmt7925:itl_ssid 'HomeWifi'" \
                        -c "Set :IOKitPersonalities:itlmt7925:itl_psk  'my password'" "$P"
```

Rules and limits:

* WPA2-PSK only (WPA2/WPA3 mixed networks work through the WPA2 side). No open networks, WPA3-only, enterprise or 6 GHz.
  A phone hotspot set to WPA2, 2.4 or 5 GHz, is the easiest first network.
* Never commit or share a kext you injected into. `*.kext` is in `.gitignore` for that reason.
* The Wi-Fi shows up in System Settings → Network as **Ethernet**, not Wi-Fi. That is expected.
* After macOS is installed you can use the **ItlWiFi** menu bar app to scan and join further networks
  ([COMPONENTS.md](COMPONENTS.md#itlwifi-itlwifiapp-the-stop-gap-wi-fi-menu)); the first connection still comes from the
  injected credentials.
* The link runs at full speed (see [WIFI.md](WIFI.md)). For the 16 GB macOS installer prefer an offline installer or USB Ethernet / tethering anyway.

## 5. First boot and installing macOS

1. Copy the EFI to the OpenCore USB stick, boot it (ASUS: `Esc`/`F8` at the logo → the stick, UEFI entry).
2. In the OpenCore picker choose the macOS installer (or **Recovery**).
3. **Offline installer recommended.** On any Mac:
   `sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia --volume /Volumes/INSTALLER`
   (download the 15.x installer from the Mac App Store or `softwareupdate --fetch-full-installer --full-installer-version 15.x`).
   The online Recovery installer works too but downloads ~16 GB: use Ethernet/tethering.
4. In the installer's Disk Utility: erase the **target disk/partition** to APFS (GUID). Do not touch the shared ESP, the Windows
   or the Linux partitions.
5. Install. The machine reboots several times: each time pick the macOS installer / "macOS Installer" entry, then finally the
   new macOS volume. If it hangs at `-v`, photograph the last lines and open an issue (hint: `Cmd+V` for verbose in the picker).
6. Finish the Setup Assistant (an Apple ID is not required; iMessage/FaceTime/Continuity are untested).

## 6. After the first boot: put OpenCore on the internal disk (optional but recommended)

The USB stick is only needed to start the installer. For daily use the reference machine boots OpenCore from the internal
ESP:

1. Back up the current ESP (`diskutil mount` it, copy the whole `EFI` folder).
2. Copy your finished `EFI/OC` and `EFI/BOOT` next to the existing `EFI/Microsoft` and `EFI/limine`. Do not delete them.
3. Add an entry (or make OpenCore the default) in the firmware boot menu; keep a way back (the previous entries and the
   backup). If an entry disappears: [DUAL-BOOT.md](DUAL-BOOT.md).
4. Windows and Linux are then started from the OpenCore picker (press `Space` for hidden/auxiliary entries).
   Beware: OpenCore ACPI patches also apply to Windows.

## 7. NVIDIA driver (RTX 5060 + the OLED)

Without it macOS has **no framebuffer** on this laptop (black screen after the boot logo).

* The driver is [NullMoth's NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) (third-party, PolyForm
  Noncommercial: read its README and licence). **Use our fork for this laptop:**
  [`thanhnndev/nvidia-macos-driver`](https://github.com/thanhnndev/nvidia-macos-driver), branch **`ga403wm`** = upstream `v1.15.0` + the OLED brightness driver
  (`NVRMEdpBL`, AUX-only panel; nothing else) ([patch list](https://github.com/thanhnndev/nvidia-macos-driver/blob/ga403wm/docs/GA403WM-PATCHES.md)).
  The fork carries source only, no binaries, so the install has two parts:
  1. **Upstream release first**, *inside* macOS 15, with its own `install.sh` / the 1401 Mac app (NVRM, NVAccel, the
     WindowServer plugin, the OpenCore changes and its own `uninstall.sh` come from it).
  2. **Then the fork's two pieces** (`NVRMEdpBL.kext` and the `NVRMFB` that asks it first) on top:
     ```sh
     # run from a clone of this repository (the scripts are in its scripts/)
     git clone --depth 1 --branch 610.57.04 https://github.com/NVIDIA/open-gpu-kernel-modules ~/ogkm610   # headers
     git clone --branch ga403wm https://github.com/thanhnndev/nvidia-macos-driver.git ~/nvidia-macos-driver-ga403wm
     BRIGHT_DIR=~/efi-audit/brightness bash scripts/macos-build-nullmoth-local.sh ~/nvidia-macos-driver-ga403wm   # needs Xcode CLT
     # root (osascript "with administrator privileges" or sudo), hash-checked, backups in /Library/NullMoth/edpbl-patch:
     sudo env BRIGHT_DIR=~/efi-audit/brightness bash scripts/macos-aux-kc-dryrun.sh    # builds a scratch collection, installs nothing
     sudo env BRIGHT_DIR=~/efi-audit/brightness UPSTREAM_NVRMFB=<pkgroot>/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB \
          bash scripts/macos-edpbl-install.sh            # reboot loads it;  --undo puts the upstream NVRMFB back
     ```
     Details, evidence and the boot-arg `nvrmedpbl=0|1|2` off switch: [OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md).
* Status: the reference machine had upstream **1.14.2** + a VRAM-clear patch and the brightness patch, then **1.14.7**, and got
  **1.15.0 + the brightness overlay installed on 2026-10-13** (loaded at the next boot; not yet confirmed booted). The VRAM-clear
  patch is dropped: the stutter was the OpenCore PAT slot, not the driver ([VRAM-GRANT-STALL.md](VRAM-GRANT-STALL.md); the PAT
  fix is in the EFI of this repository). Upstream changed no backlight code, so the brightness patch is still needed. Plain
  upstream also works on this laptop, but OLED brightness is only confirmed with the patch ([NULLMOTH.md](NULLMOTH.md)). The EFI already carries the driver's prerequisites (`csr-active-config` =
  `43 0A 00 00`, boot-args, `SecureBootModel = Disabled`); see [../efi/README.md](../efi/README.md#nvidia-dgpu-nullmoth-driver).
  AMFIPass must be loaded.
* Do **not** copy BAR values (`ResizeGpuBars`, `ResizeAppleGpuBars`) or the `IONDRVSupport` block from another board: the
  `EFI-reference.zip` is in the installer-safe state and the driver's installer switches them (upstream README: "Do not replace a
  working configuration with fixed BAR values from another board"). Since 1.14.3 it also turns `DisableVariableWrite` on for Ryzen
  EFIs with `OpenRuntime.efi`: macOS can then no longer change the startup disk itself.
* Safety net: the 1401/NullMoth tools add a *"Start once without NVIDIA driver"* entry to the picker. Use it if the screen
  stays black.

## 8. Apps and daemons (on the installed macOS)

Without Xcode: use the prebuilt apps and daemon from the release ([SCRIPTS.md §1](SCRIPTS.md#1-use-the-prebuilt-release-v1)). To build them yourself
(Xcode Command Line Tools):

```bash
xcode-select --install
git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
bash scripts/build-rogcontrol.sh --install     # ROG Control: profiles, fans, charge limit, lighting
bash scripts/build-itlwifi.sh    --install     # Wi-Fi menu
bash scripts/build-tapguard.sh   --install     # touchpad tap guard (needs Accessibility permission)
```

Every script, its root needs and its undo: [SCRIPTS.md](SCRIPTS.md). Install the other kexts to the ESP with `scripts/macos-install-kext.sh <name>` (it backs up the old one and keeps your injected
Wi-Fi credentials). CPU boost daemon (administrator rights needed):

```bash
bash scripts/build-amdcppc-policy.sh
sudo bash scripts/macos-amdcppc-policy-install.sh        # --undo removes it
```

Check it works:

```bash
sysctl debug.asuswmi.status            # profile, charge limit, MUX ... (AsusWmi)
sysctl debug.amdcppc.freq              # clock of every CPU (AmdCppc)
ioreg -rc itlmt7925 -d1 | grep wifi-  # Wi-Fi state, SSID, signal
ioreg -rc MtkBtFw -l | grep -E '"bt-state"|"bt-log"'    # Bluetooth firmware loader
/Applications/RogControl.app/Contents/MacOS/RogControl --bench 20   # runs the profiles under load
```

## 8b. Optional: HiDPI ("looks like 1440 x 900")

The OLED runs at 2880x1800 / 120 Hz; a display override plus one preference gives a 2x desktop at 1440x900 points. Only that size works.
Follow [SCRIPTS.md §4](SCRIPTS.md#4-hidpi-looks-like-1440-x-900-step-by-step) (it has the safety net and the undo); do not pick other scaled sizes in
System Settings.

## 9. Updating, and what not to do

* **Do not update macOS** beyond the 15.x you installed without checking the issues first. Turn off automatic updates.
  **macOS 26 will break this setup**; there is no support for it.
* Do not re-run NullMoth's "1401 Build" on the ESP; do not use *Reset NVRAM* if you depend on firmware boot entries.
* Before changing the ESP: copy `config.plist` to `config.plist.<name>`; before swapping a kext: `macos-install-kext.sh` does
  the backup, `--undo` puts it back.

## 10. If it goes wrong

| Symptom | First thing to try |
|---|---|
| Black screen after the logo | picker → *Start once without NVIDIA driver*; confirm MUX = Ultimate; see [NULLMOTH.md](NULLMOTH.md) |
| Kernel panic at boot | boot with `-v`, photograph the panic, remove the most recently changed kext from `config.plist` |
| Keys repeat / release late | `ItlXhciKick.kext` missing or disabled ([USB-XHCI-LAG.md](USB-XHCI-LAG.md)) |
| No Wi-Fi | credentials injected? `itlmt_m1/m2/m3` boot-args? `ioreg -rc itlmt7925 -d1 \| grep wifi-` |
| Touchpad dead | it died once on the reference unit (2026-10-10) and works again since 2026-10-12; the cause is not documented yet. Try a full power drain (unplug AC, hold the power button 40 s) and open an issue ([HANDOFF](HANDOFF.md)) |
| Linux/Windows entry gone | [DUAL-BOOT.md](DUAL-BOOT.md) |
| Need logs | [DEBUGGING.md](DEBUGGING.md), `scripts/linux-collect-logs.sh`; redact serials, MACs, SSIDs before posting |

When you open an issue, use the **Hardware report** template and attach redacted logs.
