# Third-party material

Author and maintainer of this repository: thanhnndev, <https://github.com/thanhnndev>.

Everything under `kexts/`, `macos/`, `scripts/`, `test/`, `tools/`, `docs/` is licensed under the [Clear BSD License](LICENSE).
The items below are not covered by that license, or carry attribution requirements of their own.

| Item | Where | Origin | License |
|---|---|---|---|
| MT7925 hardware layer (register map, WFDMA ring setup, MCU/UNI command framing, firmware download sequence, TXD/RXD layouts, STA_REC/BSS_INFO TLVs) | `kexts/itlmt7925/itlmt7925_m1.cpp`, `_m2.cpp`, `_m3.cpp`, `mt7925_regs.h` | Re-implemented from the Linux `mt76` driver (`drivers/net/wireless/mediatek/mt76/mt7925`, `mt76_connac_mcu.c`, `mt792x_*.c`), Copyright (C) 2020, 2023 MediaTek Inc. | BSD-3-Clause-Clear (SPDX header of each upstream file) |
| MT7925 firmware (`WIFI_MT7925_PATCH_MCU_1_1_hdr.bin`, `WIFI_RAM_CODE_MT7925_1_1.bin`) | `fw/`, embedded into `itlmt7925.kext` | `linux-firmware`, `mediatek/mt7925/` (see `fw/README.md` for version and SHA-256) | MediaTek firmware license, `fw/LICENCE.mediatek`. Redistribution is permitted for use with devices containing MediaTek chipsets. **These files are not under the Clear BSD License.** |
| OpenCore patch (`patches/opencore/fix-zen5-fsb.diff`) | applied to `OcCpuLib` at build time | Patch against acidanthera/OpenCorePkg | OpenCorePkg is BSD-3-Clause; the patch is offered under the same terms as this repository |
| Base OpenCore configuration (`efi/OC/config.plist`, `efi/OC/ACPI/*.aml`) | `efi/` | Derived from the configuration published at <https://github.com/nullmoth/1401>, adapted to this laptop | That repository is under the **PolyForm Noncommercial License 1.0.0**. `efi/` is **not** offered under the Clear BSD License; treat it as derived work with the origin's terms (noncommercial use, license notice passed on) until the author says otherwise. See `efi/README.md` |
| NVIDIA driver for macOS (not included; `efi/OC/config.plist` carries its boot-args and SIP value) | not in this repository | <https://github.com/nullmoth/nvidia-macos-driver>, installed inside macOS | PolyForm Noncommercial 1.0.0 (its `LICENSE`); includes NVIDIA, Mesa and other third-party parts under their own licenses |
| MT7925 Bluetooth firmware (`BT_RAM_CODE_MT7925_1_1_hdr.bin`) | `fw/`, embedded into `MtkBtFw.kext` | `linux-firmware`, `mediatek/mt7925/` | MediaTek firmware license, `fw/LICENCE.mediatek`. **Not under the Clear BSD License.** |
| Third-party kexts used by the EFI | **not included** | Listed with versions and upstream projects in `efi/KEXTS.md` | Each under its own license; download them from upstream |

## Design references (no code copied)

* **asusctl / rog-control-center** ([gitlab.com/asus-linux/asusctl](https://gitlab.com/asus-linux/asusctl), now
  [github.com/opengamingcollective/asusctl](https://github.com/opengamingcollective/asusctl); <https://asus-linux.org>), by
  Luke Jones and the asus-linux contributors, MPL-2.0: the feature set and the way it is organised (platform profile, PPT
  power limits, charge limit, per-board limits) that `kexts/AsusWmi`, the `macos/RogControl` app and `docs/ASUSCTL-MACOS.md` follow. No asusctl code is
  included; any later port of its files would keep them under MPL-2.0 with their notices.
* Linux **asus-wmi** (`drivers/platform/x86/asus-wmi.c`, `include/linux/platform_data/x86/asus-wmi.h`; Corentin Chary and
  contributors, GPL-2.0-or-later) and **asus-armoury** (`drivers/platform/x86/asus-armoury.[ch]`; Luke Jones, GPL-2.0): the
  WMI method and device ids, the DSTS/DEVS calling convention, the DSTS-vs-DCTS rule, the profile values and the GA403WM
  power-limit ranges used by `kexts/AsusWmi`. Interface values only; no code copied.
* Linux **btmtk** / **btusb** (`drivers/bluetooth/`, GPL-2.0): the MT79xx USB firmware download procedure that
  `kexts/MtkBtFw` re-implements (WMT command/event framing, section headers, register addresses). No code copied.
* Linux **k10temp** / **amd_nb** (GPL-2.0): the SMN address of Tctl (0x59800) and the host-bridge index/data registers used by
  `kexts/AmdCppc`. No code copied.
* [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) (GPL-2.0): `BlueToolFixup.kext`
  is used unmodified from its release (not included in this repository).

* [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm) (GPL-2.0): the idea of a kext that registers as a plain
  Ethernet-class network device and does its own 802.11 handling instead of going through `IO80211Family`. No itlwm code is
  included in this repository.
* [acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK): kernel headers and libraries used by `scripts/build.sh`
  (downloaded at build time, not redistributed).
* OpenCore documentation, Dortania guides, and the XNU / IOKit sources published by Apple (IOPCIFamily) were read while
  tracking down the USB problem described in `docs/USB-XHCI-LAG.md`.
