# GA403WM Hackintosh

**macOS 26 Tahoe trên ASUS ROG Zephyrus G14 2025 (GA403WM)**: Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop, OLED 2880x1800 120 Hz.

<p align="center">
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-window.png" alt="ROG Control trên macOS 26: số đo trực tiếp, chế độ hiệu năng, pin, giới hạn tùy chỉnh, đèn, chế độ GPU Eco" width="600">
  &nbsp;
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-popover.png" alt="Popover của ROG Control trên thanh menu" width="220">
</p>
<p align="center"><em><a href="https://github.com/thanhnndev/rog-control-macos">ROG Control</a> 0.6.0: cửa sổ và popover trên thanh menu (số liệu mẫu)</em></p>

<p align="center">
  <a href="https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v2"><b>Tải v2</b></a> ·
  <a href="docs/STATE-AND-ROADMAP.md">Tình trạng và roadmap</a> ·
  <a href="docs/FRESH-INSTALL.md">Ghi chú cài đặt</a> ·
  <a href="README.md">English</a>
</p>

> [!WARNING]
> **Thử nghiệm, do AI viết.** Gần như toàn bộ mã do AI (Claude) viết và chỉ test trên **một** máy GA403WM. Kext chạy trong
> kernel, có thể gây panic hoặc treo máy; SIP gần như tắt. Hãy backup và giữ Windows hoặc Linux boot được. Chưa có hướng
> dẫn từng bước đã test cho việc cài mới Tahoe. Không bảo hành.

## Những gì chạy được (macOS 26.7.2)

| | |
|---|---|
| ✅ Màn hình | OLED trong máy chạy trên Radeon 890M, 2880x1800 120 Hz, độ sáng, Metal cho mọi app, WebGL |
| ✅ Video | Giải mã phần cứng H.264, HEVC, VP9, AV1 (`VCNDec`) |
| ✅ Wi-Fi / Bluetooth | MediaTek MT7925 với menu Wi-Fi gốc; thiết bị BLE ([mt7925-macos](https://github.com/thanhnndev/mt7925-macos)) |
| ✅ Điều khiển ROG | Chế độ hiệu năng, quạt, giới hạn công suất, giới hạn sạc, chế độ GPU Eco, đèn bàn phím, Slash, phím Fn ([rog-control-macos](https://github.com/thanhnndev/rog-control-macos)) |
| ✅ Âm thanh | Cả bốn loa; cặp micro trong có lọc ồn (micro thứ ba chưa dùng được) |
| ✅ Nhập liệu, USB, webcam | Bàn phím, touchpad, USB, camera UVC |
| ✅ Công cụ lập trình | Docker Desktop và Android emulator (`RyzenHV`), iOS Simulator |
| ✅ Tắt máy | Tắt hẳn |
| ⚠️ Một phần | Ngủ / thức (đạt 2026-11-07, chưa test lại), RTX 5060 ở chế độ Standard, các cỡ HiDPI, điện năng và nhiệt khi tải nặng |
| ❌ Chưa kiểm chứng | HDR, cổng tai nghe, đầu đọc thẻ SD, AirDrop, mã hóa video phần cứng |

Từng mục kèm ngày và bằng chứng: [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md) (tiếng Anh).

## Các repo liên quan

| Repo | Là gì | Release mới nhất |
|---|---|---|
| [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) | App ROG Control, `AsusWmi`, `AmdCppc`, `rogkeyd`, `StrixDgpuGate` | [rogcontrol-v0.6.0](https://github.com/thanhnndev/rog-control-macos/releases/tag/rogcontrol-v0.6.0) |
| [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) | Kext Wi-Fi và Bluetooth cho MT7925 | [v2.0-beta.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/v2.0-beta.1), [bt-v1.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/bt-v1.1) |
| [nvidia-macos-driver](https://github.com/thanhnndev/nvidia-macos-driver) (fork của [nullmoth](https://github.com/nullmoth/nvidia-macos-driver)) | Driver màn hình và Metal cho Radeon 890M (`NMXGPU`), PolyForm Noncommercial | [ga403wm-890m-out50](https://github.com/thanhnndev/nvidia-macos-driver/releases/tag/ga403wm-890m-out50) (mã nguồn) |
| [ryzen-hypervisor.framework](https://github.com/thanhnndev/ryzen-hypervisor.framework) (fork của [OverlordDev](https://github.com/OverlordDev/ryzen-hypervisor.framework)) | Hypervisor AMD-V cho Docker và Android emulator | [v0.7.24-ga403wm](https://github.com/thanhnndev/ryzen-hypervisor.framework/releases/tag/v0.7.24-ga403wm) (mã nguồn) |
| [strix-890m-macos](https://github.com/thanhnndev/strix-890m-macos) | Nghiên cứu 890M trước đây, đã được thay thế | chưa có |

Repo này giữ EFI OpenCore tham khảo (`efi/`, serial là giá trị giả), tài liệu, công cụ cho 890M và các kext nhỏ
`ItlXhciKick` (sửa lag USB), `StrixS0ix` (ngủ S0), `StrixSbxMap` (WebGL trên Safari) và `TapGuard`.
macOS 15 Sequoia là cấu hình cũ: release [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1), hướng dẫn [docs/INSTALL.vi.md](docs/INSTALL.vi.md).

## Ghi công

Dựa trên OpenCore và các kext của acidanthera, driver NVIDIA và EFI của [nullmoth](https://github.com/nullmoth), các driver
amdgpu / mt76 / asus-wmi của Linux, Mesa RADV, FFmpeg và hypervisor của OverlordDev. Danh sách đầy đủ: [CREDITS.vi.md](CREDITS.vi.md).
Mã phần lớn do [Claude](https://www.anthropic.com/claude) (Anthropic) viết, [thanhnndev](https://github.com/thanhnndev) chỉ đạo và test.

## Giấy phép

[Clear BSD](LICENSE); ghi chú bên thứ ba trong [NOTICE.md](NOTICE.md). EFI dẫn xuất từ `nullmoth/1401` và fork NMX dùng
PolyForm Noncommercial 1.0.0: **chỉ dùng phi thương mại**. Không liên kết với ASUS, Apple, NVIDIA, MediaTek, AMD hay
NullMoth. Chủ máy GA403WM: gửi issue theo mẫu **Hardware report** ([CONTRIBUTING.md](CONTRIBUTING.md)).
