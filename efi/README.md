# Reference EFI: ASUS ROG Zephyrus G14 (GA403WM), Ryzen AI 9 HX 370

The OpenCore configuration this project was developed and tested with. On the reference machine it boots **macOS 15.8.1 (24H32)**
from the internal disk (OpenCore 1.0.9 on the internal ESP; it was first brought up on the 15.6.1 Recovery image from a USB
stick). macOS 26 is not supported. Install steps: [../docs/INSTALL.md](../docs/INSTALL.md).

| | |
|---|---|
| Machine | ASUS ROG Zephyrus G14 GA403WM, Ryzen AI 9 HX 370 (Strix Point / Zen 5), Radeon 890M, RTX 5060 Laptop GPU |
| Wi-Fi | MediaTek MT7925, PCI `14c3:7925` (driver: `itlmt7925.kext`) |
| USB | four AMD xHCI controllers `1022:151e`, `151f`, `151a`, `151b` (fix: `ItlXhciKick.kext`) |
| Trackpad / keyboard | I2C-HID `093a:3011` via VoodooI2C; USB keyboard `0b05:19b6` |
| OpenCore | 1.0.9 built from `963025f1382eca619412d527ad82b6d19bee70d9` with `patches/opencore/fix-zen5-fsb.diff` |

## What is in this folder

```
efi/
  OC/config.plist       the configuration, PlatformInfo identifiers replaced by placeholders
  OC/ACPI/*.aml         the SSDTs referenced by config.plist
  kexts.json            third-party kexts used (bundle id, version, SHA-256); see KEXTS.md
  KEXTS.md              what each kext is for and where to get it
```

Not included, on purpose: OpenCore binaries, OpenCore drivers, third-party kexts, `Resources/`. Download them from their
projects; the versions are listed in `KEXTS.md`, the OpenCore patch is built by the `opencore` GitHub workflow.

## Before the first boot

1. **Generate your own SMBIOS.** `PlatformInfo > Generic` contains `CHANGE_ME_SN`, `CHANGE_ME_MLB_000`, an all-zero
   `SystemUUID` and an all-zero `ROM`. Replace them with values you generate (`macserial`, GenSMBIOS). Never publish them.
   The reference configuration uses `SystemProductName = MacBookPro16,2`, `UpdateSMBIOSMode = Custom`.
2. **CPU core count.** The four `Force cpuid_cores_per_package to constant` kernel patches contain the core count in their
   `Replace` bytes: `0x0c` = 12 cores (Ryzen AI 9 HX 370). Change it for another CPU.
3. **Assemble the folder.** `EFI/OC/` = this `config.plist` + `ACPI/` + the kexts of `KEXTS.md` in `Kexts/` + `Drivers/`
   (`HfsPlus.efi`, `OpenRuntime.efi`, `ResetNvramEntry.efi`) + the patched `OpenCore.efi`. Add the three kexts of this
   repository (`itlmt7925`, `ItlXhciKick`, optionally `ItlDiag`) from a release or from `scripts/build.sh`.
4. **Wi-Fi credentials** go into the personality of `itlmt7925.kext` (`docs/WIFI.md`). They are stored in plain text on the
   stick; do not share the stick or that plist.
5. Validate with `ocvalidate` from the same OpenCore release. It will complain about the placeholders until you replace them.

## What the configuration does

* **ACPI.** `SSDT-EC` (fake EC for macOS), `SSDT-PLUG-ALT` (`plugin-type` on the CPU objects), `SSDT-RMNE` (NullEthernet
  device), `SSDT-USB-Reset` (`_STA` of the four root hubs under Darwin), `SSDT-USBX` (USB power properties),
  `SSDT-XOSI` (+ the `_OSI` to `XOSI` rename: answers "Windows" when macOS asks).
  `SSDT-Disable_Network_GPP5` hides the Wi-Fi card from macOS; it is **disabled** here so that `itlmt7925.kext` can see it.
* **Kernel.** AMD vanilla kernel patches (cpuid, `rdmsr`, PAT, non-monotonic time panic) as shipped by the base
  configuration, plus the two IOPCIFamily `probeBusGated` "disable 10 bit tags" patches. `ProvideCurrentCpuInfo`,
  `DummyPowerManagement` and `ForgedInvariant.kext` handle CPU info/TSC on AMD.
* **Booter.** `RebuildAppleMemoryMap`, `SyncRuntimePermissions`, `DevirtualiseMmio`, `EnableSafeModeSlide`,
  `ProvideCustomSlide`, `AvoidRuntimeDefrag`, `AllowRelocationBlock`.
* **Security.** `SecureBootModel = Disabled`, `Vault = Optional`, `DmgLoading = Signed`, `ScanPolicy = 0` (everything is
  shown by the picker). Test configuration, not a hardened one.
* **Debug.** `Misc > Debug` is off in the released reference (`Target 0`, `AppleDebug`, `ApplePanic`, `SysReport` false); `ItlDiag.kext` is disabled.

### boot-args (reference machine)

```
-vi2c-force-polling nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 -nvrmnobootscreen nvrmacpibl=1
itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6
```

Bring-up extras (not in the config): `-v debug=0x100 keepsyms=1 msgbuf=1048576`, `itldiag=90 itlxr=2`.

| Argument | Meaning |
|---|---|
| `-v`, `debug=0x100`, `keepsyms=1` | (bring-up only) verbose boot; keep panic text on screen; keep kernel symbols in panic logs |
| `-vi2c-force-polling` | VoodooI2C polls the trackpad instead of using GPIO interrupts |
| `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth` | NullMoth NVIDIA driver: framebuffer, accelerator, 4 display heads (see below) |
| `amfi_get_out_of_my_way=0x1 amfi=0x80` | disables AMFI so WindowServer can load the NVIDIA driver bundle (NullMoth driver requirement; AMFIPass.kext must also be on) |
| `ipc_control_port_options=0` | with AMFI relaxed, hardened apps such as Firefox crash at launch on their task control port; NullMoth setup 1.11 adds it |
| `-nvrmnobootscreen` | NullMoth driver: skip the 15-19 s boot-screen copy (`docs/NULLMOTH.md`) |
| `nvrmacpibl=1` | NullMoth driver: use the ACPI/NBCI backlight tables (opt-in since 1.14.1) |
| `itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6` | legacy `itlmt7925.kext`: start at once, scan, connect, fast path (`docs/WIFI.md`) |
| `itldiag=90 itlxr=2` | (bring-up only) ItlDiag diagnostics and xHCI event-ring sampler (`docs/DEBUGGING.md`) |
| `msgbuf=1048576` | (bring-up only) larger kernel message buffer, so the kext logs are not truncated |
| `itlkick=<us>` (not set) | ItlXhciKick period; default 1000 µs, `0` disables (`docs/USB-XHCI-LAG.md`) |

### Display resolution

`UEFI > Output > Resolution` is `2880x1800@32`, the native mode of the GA403WM's 2.8K panel (GOP mode 0; the firmware also
offers 1920x1200, 1920x1080 and a dozen 4:3/16:9 modes). While there was no NVIDIA driver the picker and Recovery were
sluggish at that size because the firmware framebuffer is mapped uncached, and the stick used `1280x720@32` and then
`1920x1200@32` as a workaround. With the NullMoth driver installed the native mode is the right one. A different panel
option needs a different value: set `Max` to let OpenCore pick the largest mode. `UIScale` stays `0` (automatic).

### Known leftovers (harmless, not removed because the configuration is published exactly as tested)

* `DeviceProperties > Add` has `IOPCIMSIMode = false` on the four xHCI controllers. It does nothing: IOPCIFamily *sets*
  that property when it enables MSI and never reads it back (`docs/USB-XHCI-LAG.md`). It can be deleted.
* `ItlDiag.kext` and the `itldiag` / `itlxr` boot-args are debugging tools.

## NVIDIA dGPU (NullMoth driver)

The RTX 5060 is driven by [NullMoth's NVIDIA driver for macOS 15](https://github.com/nullmoth/nvidia-macos-driver)
(installed with its `install.sh` or the 1401 Mac app, **inside** macOS: kexts go to `/Library/Extensions` and load from the
Auxiliary Kernel Collection, so nothing NVIDIA is in `EFI/OC/Kexts`). This repository does not contain or modify it. The EFI
only carries what that driver asks of OpenCore:

| Setting | Value here | Driver's installed-system value |
|---|---|---|
| `NVRAM > csr-active-config` | `43 0A 00 00` (0x0A43) | same |
| boot-args `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0` | set | same |
| `Misc > Security > SecureBootModel` | `Disabled` | same |
| `Booter > Quirks > ResizeAppleGpuBars` | `0` | `-1` |
| `UEFI > Quirks > ResizeGpuBars` | `-1` | `13` (8 GB BAR) |
| `Kernel > Block` `com.apple.iokit.IONDRVSupport` (Exclude) | absent | present |
| `DeviceProperties` for the card | none | none |

The two BAR values and the missing `Block` entry are the driver's *installer-phase* settings; its Mac app switches them when it
installs the driver. The 890M is hidden with `disable-gpu`, WhateverGreen is disabled, and BIOS needs Above 4G Decoding ON and
CSM OFF. On the reference machine it works (RTX 5060 + the OLED at 2880x1800 @ 120 Hz; upstream 1.14.2 plus two local patches,
[docs/NULLMOTH.md](../docs/NULLMOTH.md); install the driver from [our fork](https://github.com/thanhnndev/nvidia-macos-driver/tree/ga403wm), [docs/INSTALL.md §7](../docs/INSTALL.md#7-nvidia-driver-rtx-5060--the-oled)). Read the driver's own README and licence before relying on it. The configuration in this
folder is in the **installer-safe** state (the "Value here" column; the driver's installer switches the BAR values and the `Block`
entry and adds its own "1401: ..." tool entries), so do not paste BAR values from another board.

## The OpenCore patch (`patches/opencore/fix-zen5-fsb.diff`)

Stock OpenCore 1.0.9 computes the wrong `FSBFrequency` on Zen 5 (family 1Ah): the 12-bit FID from `PStateDef0` (400 =
2000 MHz on the HX 370) was narrowed to `UINT8` before being scaled, wrapped to 208 and gave an FSB of 9.6 MHz instead of
100 MHz. XNU derives its LAPIC timer conversions from that value, so timers fired about ten times too early. The patch keeps
the FID at 12 bits and derives the bus ratio from the measured TSC, as the 17h/19h path does. The `opencore` workflow
builds OpenCore from the exact upstream commit with the patch applied (manual trigger, artifact `opencore-zen5-fsb`).
`ItlDiag`'s `itlt1` variable shows the effect: `ratio=995/1000` between mach time and wall clock (see `docs/DEBUGGING.md`).

## Open items

* **USB port map:** `OC/Kexts/UTBMap.kext` (release `EFI-reference.zip`) is the author's map for this laptop and is enabled;
  `UTBDefault.kext` is disabled; `XhciPortLimit` is off. It only fits the same model: elsewhere map your ports with the
  USBToolBox tool. The internal keyboard (`0b05:19b6`) must stay mapped as an internal port.
* Status of sleep/wake, audio, SD reader and battery readout: see the README status table and `docs/ROADMAP.md`.

## Provenance

The configuration and the SSDTs started from <https://github.com/nullmoth/1401> and were adapted. That repository is under the
**PolyForm Noncommercial License 1.0.0**, so the files in this directory are **not** under the Clear BSD License of the rest
of the repository: use them for noncommercial purposes and keep this attribution. They keep their origin visible (OEM table
id `ZPSS`, patch comments by their authors). If you are the author and want them removed or attributed differently, open an issue.
