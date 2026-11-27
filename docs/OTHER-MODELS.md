# Other G14 models

This repository is tested on **one** GA403WM only. This page collects reports from owners of other models who
started from this EFI. Their results are theirs; nothing here was tested on those machines by this project.

## GA403UV (RTX 4060, MT7922), reported by [hbyonly1](https://github.com/hbyonly1)

Source: [issue #8](https://github.com/thanhnndev/ga403wm-hackintosh/issues/8) (2026-10-17, English and Chinese).
macOS Sequoia 15.8.1 (24H32), BIOS 306, GPU mode Ultimate (dGPU only), NullMoth NVIDIA driver 2.2.0,
SMBIOS `MacBookPro16,2`, started from commit
[`0b620b9`](https://github.com/thanhnndev/ga403wm-hackintosh/commit/0b620b9c47e321adf73d1e0765c835b0095f7fb1)
(the macOS 15 setup, before v2).

Hardware that differs from the GA403WM: 8-core Ryzen, RTX 4060 Laptop, MediaTek MT7922 / RZ616
(Wi-Fi `14c3:0616`, Bluetooth USB `0489:e0f6`), Realtek ALC285 (layout 33).

### Changes they needed

| Change | Their verdict |
|---|---|
| BIOS: IOMMU off | required |
| Remove `nvrmacpibl=1` from boot-args (hangs while loading) | required |
| `Booter > Quirks > SetupVirtualMap` = `True` | required |
| `Kernel > Block`: `com.apple.iokit.IONDRVSupport`, `Strategy=Exclude` | required |
| CPU core-count patches: 12 → 8 cores (all four) | required |
| `UTBMap.kext` with their own USB map | required |
| Own SMBIOS serial, MLB, UUID, ROM | required |
| `Booter > Quirks > DisableVariableWrite` = `True` (with `OpenRuntime.efi`) | recommended |
| Remove `revcpu` / `revcpuname` | recommended |

ACPI files and the rest of the config were left as in the reference EFI.

### What they saw

| | |
|---|---|
| ✅ Works | RTX 4060 display and acceleration (still being checked), battery, USB, keyboard and touchpad, SD card reader |
| ✅ Wi-Fi | MT7922 through their own port (`ItlWiFi7922`, Ethernet backend, WPA2, HT/VHT); not published |
| ⚠️ Bluetooth | Mouse works; AirPods Pro 2 connect but playback often fails. Their MT7922 Bluetooth work is in [mt7925-macos#4](https://github.com/thanhnndev/mt7925-macos/pull/4) (not merged yet) |
| ⚠️ Speakers | Very quiet, wrong soundstage |
| ❌ Brightness | Not working |
| ❓ Not verified | Fn keys, sleep / wake, external displays, microphone |

USB lag in Recovery and the installer (keyboard and mouse delayed, installer image taking hours) was fixed on their
machine by their own `USBXHCIWakeup` patch, which is evaluated in
[issue #9](https://github.com/thanhnndev/ga403wm-hackintosh/issues/9). This repository's answer to the same symptom
is `ItlXhciKick` ([USB-XHCI-LAG.md](USB-XHCI-LAG.md)).

### Since then

The GA403WM moved to macOS 26 Tahoe in [v2](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v2), with
the internal display on the Radeon 890M. A GA403UV has a Radeon 780M (RDNA 3), which the GA403WM driver does not
support; the RTX path in Ultimate mode is the one that applies there. Related repositories:
[mt7925-macos](https://github.com/thanhnndev/mt7925-macos) (MT7925 Wi-Fi and Bluetooth, MT7922 Bluetooth pending),
[rog-control-macos](https://github.com/thanhnndev/rog-control-macos) (performance modes, fans, charge limit; see
[rog-control-macos#11](https://github.com/thanhnndev/rog-control-macos/issues/11) for a GA403UV report).

## Add your model

Open an issue with the **Hardware report** template ([CONTRIBUTING.md](../CONTRIBUTING.md)). Please never post your
serial number, MLB, ROM, MAC addresses or Wi-Fi passwords.
