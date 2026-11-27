# Reference EFI: ASUS ROG Zephyrus G14 (GA403WM), Ryzen AI 9 HX 370

The OpenCore configuration of the reference machine, exported from its live ESP on **2026-11-25** with
`scripts/export-efi.py`. On that machine the original boots **macOS 26.7.2 Tahoe (25G332)** from the internal disk under
OpenCore 1.0.9.

**This is a reference for this one machine, not a ready-to-boot EFI.** The export removes the machine's identifiers and
the vendor firmware, kexts are not included, and the exported copy with its placeholders was never booted. What you must
fill in is listed under "What you must supply". State of the whole setup, with dates:
[../docs/STATE-AND-ROADMAP.md](../docs/STATE-AND-ROADMAP.md). There is no tested step-by-step Tahoe guide; the design is
[../docs/FRESH-INSTALL.md](../docs/FRESH-INSTALL.md).

The macOS 15 configuration (v1, last changed 2026-10-13) is in the git history before commit 3901d1d; its guide is
[../docs/INSTALL.md](../docs/INSTALL.md). The two do not mix.

| | |
|---|---|
| Machine | ASUS ROG Zephyrus G14 GA403WM, Ryzen AI 9 HX 370 (Strix Point / Zen 5), Radeon 890M, RTX 5060 Laptop GPU |
| Wi-Fi | MediaTek MT7925, PCI `14c3:7925` (drivers: `itlmt7925.kext` + `itlmt7925Native.kext`) |
| USB | four AMD xHCI controllers `1022:151e`, `151f`, `151a`, `151b` (fix: `ItlXhciKick.kext`) |
| Trackpad / keyboard | I2C-HID `093a:3011` via VoodooI2C; USB keyboard `0b05:19b6` |
| OpenCore | 1.0.9 built from `963025f1382eca619412d527ad82b6d19bee70d9` with `patches/opencore/fix-zen5-fsb.diff` |

## What is in this folder

```
efi/
  OC/config.plist       the configuration as exported, identifiers and firmware removed (see below)
  OC/ACPI/*.aml         the SSDTs referenced by config.plist (.dsl sources for SSDT-XOSI and SSDT-ECRAM)
  OC/Kexts/UTBMap.kext  the USB port map (codeless); not rewritten by the export, see "Open items"
  kexts.json            32 third-party kexts found on the ESP (bundle id, version, SHA-256 of the executable)
  KEXTS.md              what each kext is for and where to get it
```

Not included, on purpose: every kext binary, OpenCore binaries and drivers, `NullMothSafe.efi` (the tool behind the two
"1401: ..." entries in `Misc > Tools`), `Resources/`. Download them from their projects; the OpenCore patch is built by
the `opencore` GitHub workflow.

`KEXTS.md` was written for the macOS 15 set. It does not yet describe SimpleHDA, RyzenHV, StrixVFCT and the NullMoth
entries that `kexts.json` now lists.

## What the export changed

`scripts/export-efi.py` copies the file byte for byte except for these values:

| Value | In the exported file |
|---|---|
| `PlatformInfo > Generic > SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM` | `CHANGE_ME_SN`, `CHANGE_ME_MLB_000`, all-zero UUID, all-zero ROM |
| `NVRAM > Add > 7C436110-... > bluetoothInternalControllerInfo` | zeroed (it carries the Bluetooth controller's address) |
| `DeviceProperties > Add > PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0) > vbios` | **empty**. It held the Radeon 890M's VBIOS image; vendor firmware is not redistributed |
| `SSDT-RMNE.aml`, the MAC address in `Name` | NullEthernet's default `11:22:33:44:55:66`, table checksum fixed |
| `Misc > Entries` | emptied (its device paths carry the disk's identifiers) |

`scripts/check-efi-privacy.py efi/OC/config.plist` checks that only placeholders are left; CI runs it.

## What you must supply

1. **Your own SMBIOS**: serial, MLB, UUID and ROM, generated with `macserial` or GenSMBIOS. Never publish them. The
   reference uses `SystemProductName = MacBookPro16,2`, `UpdateSMBIOSMode = Custom`.
2. **Your own card's VBIOS image** in the `vbios` property of `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)`. Left empty, the
   property is useless. `StrixVFCT.kext` (enabled in `Kernel > Add`, listed in `kexts.json` without a hash) is in the
   same position: it carries the firmware's VFCT table and has to be built from a dump of your own machine
   ([../docs/FRESH-INSTALL.md](../docs/FRESH-INSTALL.md)).
3. **Every kext.** Third-party ones from their upstream projects, checked against `kexts.json` if you want the exact
   set. `ItlXhciKick`, `ItlDiag` and `StrixSbxMap` from this repository's release or `scripts/build.sh`; Wi-Fi and
   Bluetooth from [mt7925-macos](https://github.com/thanhnndev/mt7925-macos/releases); `AsusWmi`, `AmdCppc` and
   `StrixDgpuGate` from [rog-control-macos](https://github.com/thanhnndev/rog-control-macos/releases); `RyzenHV` from
   the [ryzen-hypervisor.framework fork](https://github.com/thanhnndev/ryzen-hypervisor.framework). `StrixAmp` exists
   only on branch `research/audio-rog-dolby`. Disable the `Kernel > Add` entries you do not install.
4. **A MAC address for the NullEthernet device** if you do not want the default in `SSDT-RMNE`.
5. **The Bluetooth NVRAM values.** Under `7C436110-AB2A-4BBB-A880-FE41995C9F82`, in both `NVRAM > Add` and
   `NVRAM > Delete`: `bluetoothExternalDongleFailed` = Data `00` and `bluetoothInternalControllerInfo` = exactly 14 zero
   bytes (the export zeroes it; BlueToolFixup 2.7.x needs 14, with 16 `bluetoothd` falls back to a UART placeholder). The
   zero value fixed an HP MT7925 card in [#10](https://github.com/thanhnndev/ga403wm-hackintosh/issues/10) (diagnosis by
   watchthelight); the reference machine itself was not booted with the zeroed export.
6. **CPU core count.** The four `Force cpuid_cores_per_package to constant` kernel patches contain the core count in
   their `Replace` bytes: `0x0c` = 12 cores (Ryzen AI 9 HX 370). Change it for another CPU.
7. **OpenCore itself**: the patched `OpenCore.efi`, `Drivers/` (`HfsPlus.efi`, `OpenRuntime.efi`,
   `ResetNvramEntry.efi`), and your own `Misc > Entries` if you need any.

The GPU stack is not on the ESP at all: `NMXGPU`, `NMXAccel`, `NMXAGDC` and `StrixS0ix` load from the Auxiliary Kernel
Collection (`/Library/Extensions`), the Metal plugin, translator and RADV live in `/Library/GPUBundles`. The order that
worked once is in the [v2 release notes](../.github/release-notes/v2.md).

Validate with `ocvalidate` from the same OpenCore release. It will complain about the placeholders until you replace
them.

## What the configuration does

* **ACPI.** `SSDT-EC` (fake EC for macOS), `SSDT-PLUG-ALT` (`plugin-type` on the CPU objects), `SSDT-RMNE` (NullEthernet
  device), `SSDT-USB-Reset` (`_STA` of the four root hubs under Darwin), `SSDT-USBX` (USB power properties),
  `SSDT-XOSI` (+ the `_OSI` to `XOSI` rename: answers "Windows" when macOS asks). New with Tahoe: `SSDT-ECRAM` (EC RAM
  access for `AsusWmi`), `SSDT-S0IDLE` (S0 idle sleep, used by `StrixS0ix`), `SSDT-PTS5` with the `_PTS` to `ZPTS`
  rename (Shut Down stays off), `SSDT-LIDFIX` with the `_LID` to `XLID` rename, and an `ACAD._PSR` patch (AC detection).
  Each rename must be enabled or disabled together with its table. `SSDT-Disable_Network_GPP5` hides the Wi-Fi card from
  macOS; it is **disabled** so that the Wi-Fi driver can see the card.
* **Kernel.** AMD vanilla kernel patches (cpuid, `rdmsr`, PAT, non-monotonic time panic, including the 26.4+ variant) as
  shipped by the base configuration, the two IOPCIFamily `probeBusGated` "disable 10 bit tags" patches (12.0-15.x and
  26.0+), and one local patch that clamps a non-monotonic `fq_codel` enqueue time instead of panicking (HoRNDIS
  tethering on 26.x). `ProvideCurrentCpuInfo`, `DummyPowerManagement` and `ForgedInvariant.kext` handle CPU info/TSC on
  AMD.
* **Kernel > Add.** 48 entries. Disabled on the reference machine: the five NullMoth NVIDIA entries (`NVRM`, `NVRMFB`,
  `NVRMAGDC`, `NVRMEdpBL`, `NVAccel`; the NVIDIA stack loads from the Auxiliary Kernel Collection), `StrixGOP`,
  `StrixAccel`, `WhateverGreen`, `SMCLightSensor`, `UTBDefault`, `ItlDiag`. `SimpleHDA`, `StrixSbxMap`, `RyzenHV` and
  `StrixDgpuGate` carry `MaxKernel 25.99.99`: they are gated on Darwin 25.x as a whole.
* **Booter.** `RebuildAppleMemoryMap`, `SyncRuntimePermissions`, `DevirtualiseMmio`, `EnableSafeModeSlide`,
  `ProvideCustomSlide`, `AvoidRuntimeDefrag`, `AllowRelocationBlock`, `FixupAppleEfiImages`.
* **DeviceProperties.** The 890M at `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)` gets `model`, `VRAM,totalMB`,
  `VRAM,totalsize`, `name` / `IOName` = `#display` and `vbios` (emptied here). `layout-id` 33 on the HD-audio
  controller. It is no longer hidden with `disable-gpu`.
* **Security.** `SecureBootModel = Disabled`, `Vault = Optional`, `DmgLoading = Signed`, `ScanPolicy = 0` (everything is
  shown by the picker), `csr-active-config = 43 0A 00 00`. Test configuration, not a hardened one.
* **Picker.** Shown, 2 s timeout.
* **Debug.** `Misc > Debug` has `Target 0`, `AppleDebug` and `SysReport` false, `ApplePanic` true. The boot-args still
  carry debug and trace flags, as on the live machine (below).

### boot-args (reference machine, as exported)

```
debug=0x100 keepsyms=1 -vi2c-force-polling nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
amfi_get_out_of_my_way=0x1 amfi=0x80 msgbuf=1048576 ipc_control_port_options=0 itlmt_m1=0
-nvrmnobootscreen nvrmacpibl=1 itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_native_nvtrace=1
itlmt_fast=6 itlmt_stat=1 alcverbs=1 strixhdr=1 -strixgopoff -strixaccoff -strixmetalgateoff itlmt_awdl=1
nmxamd=1 rhv_enable_svm=1 rhv_selftest=1 rhv_hv=1 rhv_allow_users=1 rhv_loglevel=4 shda-lang=en -FIOff
```

| Argument | Meaning |
|---|---|
| `debug=0x100`, `keepsyms=1`, `msgbuf=1048576` | keep panic text on screen; keep kernel symbols in panic logs; larger kernel message buffer. Debug aids, not needed for normal use |
| `-vi2c-force-polling` | VoodooI2C polls the trackpad instead of using GPIO interrupts |
| `nmxamd=1` | NMXGPU: drive the Radeon 890M |
| `-strixgopoff -strixaccoff -strixmetalgateoff` | switch off the earlier boot-display research kexts (StrixGOP, StrixAccel, StrixMetalGate); NMXGPU replaced them |
| `strixhdr=1` | StrixGOP HDR override; a leftover, StrixGOP is switched off |
| `amfi_get_out_of_my_way=0x1 amfi=0x80` | relaxes AMFI so WindowServer can load the ad hoc signed driver bundles (AMFIPass.kext must also be on) |
| `ipc_control_port_options=0` | with AMFI relaxed, hardened apps such as Firefox crash at launch on their task control port; NullMoth setup 1.11 adds it |
| `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth`, `-nvrmnobootscreen`, `nvrmacpibl=1` | NullMoth NVIDIA driver (Standard mode only): framebuffer, accelerator, 4 display heads, no boot-screen copy, ACPI backlight tables. Do **not** add `-nvoff`: it also parks NMXGPU |
| `itlmt_m1=0 itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_fast=6` | Wi-Fi in native mode ([mt7925-macos guide](https://github.com/thanhnndev/mt7925-macos/blob/main/docs/GUIDE.md#12-boot-arg-reference)) |
| `itlmt_native_nvtrace=1`, `itlmt_stat=1` | Wi-Fi trace flags |
| `itlmt_awdl=1` | AWDL work in progress; no working AirDrop result is recorded |
| `alcverbs=1` | AppleALC option used by the audio setup |
| `shda-lang=en` | SimpleHDA: device names in English |
| `rhv_enable_svm=1 rhv_hv=1 rhv_allow_users=1` | RyzenHV settings (see the fork's documentation) |
| `rhv_selftest=1`, `rhv_loglevel=4` | RyzenHV trace flags |
| `-FIOff` | present on the live machine; not documented in this repository |
| `itlkick=<us>` (not set) | ItlXhciKick period; default 1000 µs, `0` disables (`docs/USB-XHCI-LAG.md`) |

More switches (undo boot-args for single pieces) are in the [v2 release notes](../.github/release-notes/v2.md).

### Display resolution

`UEFI > Output > Resolution` is `2880x1800@32`, the native mode of the GA403WM's 2.8K panel (GOP mode 0; the firmware also
offers 1920x1200, 1920x1080 and a dozen 4:3/16:9 modes). A different panel option needs a different value: set `Max` to
let OpenCore pick the largest mode. `UIScale` stays `0` (automatic).

### Known leftovers (harmless, not removed because the configuration is published as it runs)

* `DeviceProperties > Add` has `IOPCIMSIMode = false` on four devices. It does nothing: IOPCIFamily *sets* that property
  when it enables MSI and never reads it back (`docs/USB-XHCI-LAG.md`). It can be deleted.
* `ItlDiag.kext` (disabled) and the debug and trace boot-args are debugging tools.
* `strixhdr=1` and the disabled `StrixGOP` / `StrixAccel` entries belong to the earlier boot-display research.

## NVIDIA dGPU (NullMoth driver, Standard mode only)

On Tahoe the internal display runs on the Radeon 890M. The RTX 5060 is normally powered off and taken off the PCI bus at
boot (Eco mode, `StrixDgpuGate`). In Standard mode it is driven by
[NullMoth's NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) 2.7.1, installed **inside** macOS by
`scripts/macos-install-nvidia-2.7.1.sh`: its kexts load from the Auxiliary Kernel Collection, and the NVIDIA entries in
`Kernel > Add` are disabled. This repository does not contain the driver. The EFI carries what that driver asks of
OpenCore, in the driver's installed-system state:

| Setting | Value here |
|---|---|
| `NVRAM > csr-active-config` | `43 0A 00 00` (0x0A43) |
| boot-args `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0` | set |
| `Misc > Security > SecureBootModel` | `Disabled` |
| `Booter > Quirks > ResizeAppleGpuBars` | `-1` |
| `UEFI > Quirks > ResizeGpuBars` | `13` (8 GB BAR) |
| `Kernel > Block` `com.apple.iokit.IONDRVSupport` | present, enabled |
| `Misc > Tools` | two "1401: ..." entries (`NullMothSafe.efi`): remove the NVIDIA driver, start once without it |
| `DeviceProperties` for the RTX | none |

BIOS needs Above 4G Decoding ON and CSM OFF. The BAR values fit this board; do not paste them into the configuration of
another one. Read the driver's own README and licence before relying on it. State of Standard mode (apps get no Metal
device from the RTX, HDMI not re-tested): [../docs/STATE-AND-ROADMAP.md](../docs/STATE-AND-ROADMAP.md).

## The OpenCore patch (`patches/opencore/fix-zen5-fsb.diff`)

Stock OpenCore 1.0.9 computes the wrong `FSBFrequency` on Zen 5 (family 1Ah): the 12-bit FID from `PStateDef0` (400 =
2000 MHz on the HX 370) was narrowed to `UINT8` before being scaled, wrapped to 208 and gave an FSB of 9.6 MHz instead of
100 MHz. XNU derives its LAPIC timer conversions from that value, so timers fired about ten times too early. The patch keeps
the FID at 12 bits and derives the bus ratio from the measured TSC, as the 17h/19h path does. The `opencore` workflow
builds OpenCore from the exact upstream commit with the patch applied (manual trigger, artifact `opencore-zen5-fsb`).
`ItlDiag`'s `itlt1` variable shows the effect: `ratio=995/1000` between mach time and wall clock (see `docs/DEBUGGING.md`).

## Open items

* **USB port map:** `OC/Kexts/UTBMap.kext` is the author's map for this laptop and is enabled; `UTBDefault.kext` is
  disabled; `XhciPortLimit` is off. The export does not copy kexts, so the file in the tree is the map as it was on
  2026-10-13; it was not compared with the one on the live ESP. It only fits the same model: elsewhere map your ports
  with the USBToolBox tool. The internal keyboard (`0b05:19b6`) must stay mapped as an internal port.
* The exported copy was not booted, and `KEXTS.md` does not cover the Tahoe additions yet.
* Status of sleep/wake, audio, SD reader and battery readout: [../docs/STATE-AND-ROADMAP.md](../docs/STATE-AND-ROADMAP.md).

## Provenance

The configuration and the SSDTs started from <https://github.com/nullmoth/1401> and were adapted. That repository is under the
**PolyForm Noncommercial License 1.0.0**, so the files in this directory are **not** under the Clear BSD License of the rest
of the repository: use them for noncommercial purposes and keep this attribution. They keep their origin visible (OEM table
id `ZPSS`, patch comments by their authors). If you are the author and want them removed or attributed differently, open an issue.
