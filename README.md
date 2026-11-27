# GA403WM Hackintosh

**macOS 26 Tahoe on the ASUS ROG Zephyrus G14 2025 (GA403WM)**: Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop, 2880x1800 120 Hz OLED.

<p align="center">
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-window.png" alt="ROG Control on macOS 26: live readings, performance mode, battery, custom limits, lighting, GPU mode Eco" width="600">
  &nbsp;
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-popover.png" alt="ROG Control menu bar popover" width="220">
</p>
<p align="center"><em><a href="https://github.com/thanhnndev/rog-control-macos">ROG Control</a> 0.6.0: the window and the menu bar popover (sample values)</em></p>

<p align="center">
  <a href="https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v2"><b>Download v2</b></a> ·
  <a href="docs/STATE-AND-ROADMAP.md">State and roadmap</a> ·
  <a href="docs/FRESH-INSTALL.md">Install notes</a> ·
  <a href="README.vi.md">Tiếng Việt</a>
</p>

> [!WARNING]
> **Experimental and AI-written.** Almost all code was written by an AI (Claude) and tested on **one** GA403WM. Kexts run
> in the kernel and can panic or hang the machine; SIP is mostly off. Back up first and keep Windows or Linux bootable.
> There is no tested step-by-step guide for a fresh Tahoe install yet. No warranty.

## What works (macOS 26.7.2)

| | |
|---|---|
| ✅ Display | Internal OLED on the Radeon 890M, 2880x1800 at 120 Hz, brightness, Metal for all apps, WebGL |
| ✅ Video | Hardware decode of H.264, HEVC, VP9, AV1 (`VCNDec`) |
| ✅ Wi-Fi / Bluetooth | MediaTek MT7925 with the native Wi-Fi menu; BLE devices ([mt7925-macos](https://github.com/thanhnndev/mt7925-macos)) |
| ✅ ROG controls | Performance modes, fans, power limits, charge limit, GPU Eco mode, keyboard light, Slash, Fn keys ([rog-control-macos](https://github.com/thanhnndev/rog-control-macos)) |
| ✅ Audio | All four speakers; internal microphone pair with noise reduction (third mic not reachable) |
| ✅ Input, USB, webcam | Keyboard, touchpad, USB, UVC camera |
| ✅ Dev tools | Docker Desktop and the Android emulator (`RyzenHV`), iOS Simulator |
| ✅ Shut down | Stays off |
| ⚠️ Partly | Sleep / wake (passed 2026-11-07, not re-tested), RTX 5060 in Standard mode, HiDPI sizes, power and heat under heavy load |
| ❌ Not verified | HDR, headphone jack, SD card reader, AirDrop, hardware video encode |

Every item with its date and evidence: [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md).

## Related repositories

| Repository | What | Latest release |
|---|---|---|
| [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) | ROG Control app, `AsusWmi`, `AmdCppc`, `rogkeyd`, `StrixDgpuGate` | [rogcontrol-v0.6.0](https://github.com/thanhnndev/rog-control-macos/releases/tag/rogcontrol-v0.6.0) |
| [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) | MT7925 Wi-Fi and Bluetooth kexts | [v2.0-beta.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/v2.0-beta.1), [bt-v1.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/bt-v1.1) |
| [nvidia-macos-driver](https://github.com/thanhnndev/nvidia-macos-driver) (fork of [nullmoth's](https://github.com/nullmoth/nvidia-macos-driver)) | Radeon 890M display and Metal driver (`NMXGPU`), PolyForm Noncommercial | [ga403wm-890m-out50](https://github.com/thanhnndev/nvidia-macos-driver/releases/tag/ga403wm-890m-out50) (source) |
| [ryzen-hypervisor.framework](https://github.com/thanhnndev/ryzen-hypervisor.framework) (fork of [OverlordDev's](https://github.com/OverlordDev/ryzen-hypervisor.framework)) | AMD-V hypervisor for Docker and the Android emulator | [v0.7.24-ga403wm](https://github.com/thanhnndev/ryzen-hypervisor.framework/releases/tag/v0.7.24-ga403wm) (source) |
| [strix-890m-macos](https://github.com/thanhnndev/strix-890m-macos) | Earlier 890M research, superseded | none |

This repository holds the OpenCore EFI reference (`efi/`, with placeholder serials), the docs, the 890M tools and the
small kexts `ItlXhciKick` (USB lag fix), `StrixS0ix` (S0 sleep), `StrixSbxMap` (Safari WebGL) and `TapGuard`.
macOS 15 Sequoia is the older setup: release [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1), guide [docs/INSTALL.md](docs/INSTALL.md).

## Credits

Built on OpenCore and the acidanthera kexts, [nullmoth](https://github.com/nullmoth)'s NVIDIA driver and EFI, the Linux
amdgpu / mt76 / asus-wmi drivers, Mesa RADV, FFmpeg and OverlordDev's hypervisor. Full list: [CREDITS.md](CREDITS.md).
Code was written mostly by [Claude](https://www.anthropic.com/claude) (Anthropic), directed and tested by [thanhnndev](https://github.com/thanhnndev).

## License

[Clear BSD](LICENSE); third-party notes in [NOTICE.md](NOTICE.md). The EFI derives from `nullmoth/1401` and the NMX fork
is PolyForm Noncommercial 1.0.0: **noncommercial use only**. Not affiliated with ASUS, Apple, NVIDIA, MediaTek, AMD or
NullMoth. GA403WM owners: issues use the **Hardware report** template ([CONTRIBUTING.md](CONTRIBUTING.md)).
