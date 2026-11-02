# Third-party material

Author and maintainer of this repository: thanhnndev, <https://github.com/thanhnndev>.

Everything under `kexts/`, `macos/`, `scripts/`, `test/`, `tools/`, `docs/` is licensed under the [Clear BSD License](LICENSE).
The items below are not covered by that license, or carry attribution requirements of their own.
The MT7925 Wi-Fi driver (with its `mt76`-derived hardware layer and the Wi-Fi firmware) moved to
[mt7925-macos](https://github.com/thanhnndev/mt7925-macos); its notices are in that repository's `NOTICE.md`.

| Item | Where | Origin | License |
|---|---|---|---|
| OpenCore patch (`patches/opencore/fix-zen5-fsb.diff`) | applied to `OcCpuLib` at build time | Patch against acidanthera/OpenCorePkg | OpenCorePkg is BSD-3-Clause; the patch is offered under the same terms as this repository |
| Base OpenCore configuration (`efi/OC/config.plist`, `efi/OC/ACPI/*.aml`) | `efi/` | Derived from the configuration published at <https://github.com/nullmoth/1401>, adapted to this laptop | That repository is under the **PolyForm Noncommercial License 1.0.0**. `efi/` is **not** offered under the Clear BSD License; treat it as derived work with the origin's terms (noncommercial use, license notice passed on) until the author says otherwise. See `efi/README.md` |
| NVIDIA driver for macOS (not included; `efi/OC/config.plist` carries its boot-args and SIP value) | not in this repository | <https://github.com/nullmoth/nvidia-macos-driver>, installed inside macOS | PolyForm Noncommercial 1.0.0 (its `LICENSE`); includes NVIDIA, Mesa and other third-party parts under their own licenses |
| Third-party kexts used by the EFI | **not included** | Listed with versions and upstream projects in `efi/KEXTS.md` | Each under its own license; download them from upstream |

## Design references (no code copied)

* The design references for the moved components (asusctl, Linux `asus-wmi` / `asus-armoury` / `k10temp` / `btmtk`, G-Helper, itlwm, BrcmPatchRAM) are listed in the `NOTICE.md` of
  [rog-control-macos](https://github.com/thanhnndev/rog-control-macos/blob/main/NOTICE.md) and [mt7925-macos](https://github.com/thanhnndev/mt7925-macos/blob/main/NOTICE.md).
* [acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK): kernel headers and libraries used by `scripts/build.sh`
  (downloaded at build time, not redistributed).
* OpenCore documentation, Dortania guides, and the XNU / IOKit sources published by Apple (IOPCIFamily) were read while
  tracking down the USB problem described in `docs/USB-XHCI-LAG.md`.
