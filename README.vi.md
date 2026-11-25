# GA403WM Hackintosh

> **Bản release này (v2) dành cho macOS 26 Tahoe, màn hình trong máy chạy trên Radeon 890M.**
> macOS 15 Sequoia là bản trước: [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1) và
> [kext-v1.1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/kext-v1.1). Đó là một cấu hình khác
> (màn hình chạy trên RTX 5060, 890M bị ẩn); hướng dẫn của nó là [docs/INSTALL.vi.md](docs/INSTALL.vi.md). Không trộn hai bản.

## Dự án vibe-code: đọc trước khi cài

Đây là dự án vibe-code, đang ở mức thử nghiệm. **Gần như toàn bộ mã và tài liệu do AI (Claude) viết**, được một người hướng dẫn và test trên **một chiếc máy**; chưa có audit độc lập.

- Kext chạy trong kernel; lỗi có thể gây panic, treo máy hoặc mất dữ liệu. `NMXGPU` điều khiển màn hình: lỗi ở đó có thể làm màn hình đen và phải tắt nóng. `AsusWmi` và `AmdCppc` ghi vào EC, BIOS và thanh ghi CPU; `RyzenHV` chạy máy ảo trong kernel; `StrixSbxMap` thêm một ngoại lệ vào Sandbox của macOS; `VCNDec` và một luật sandbox được cài lên system volume.
- SIP gần như tắt, AMFI nới lỏng, Secure Boot tắt.
- Log, bản dump `ioreg` và báo cáo panic chứa số serial, địa chỉ MAC và SSID/BSSID xung quanh; che trước khi đăng.
- Backup ổ đĩa và giữ Windows hoặc Linux boot được: trong quá trình phát triển đã phải dùng nhiều lần để hoàn tác thay đổi GPU. Không bảo hành; xem [LICENSE](LICENSE).

## Giới thiệu

macOS 26 Tahoe trên **ASUS ROG Zephyrus G14 (2025), GA403WM**: Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop.

[English](README.md) · [**Tình trạng và roadmap (tiếng Anh)**](docs/STATE-AND-ROADMAP.md) · [Ghi chú release v2 (tiếng Anh)](.github/release-notes/v2.md) · [Release](https://github.com/thanhnndev/ga403wm-hackintosh/releases) · [Cài macOS 15 (v1)](docs/INSTALL.vi.md)

## Tình trạng

Bản tiếng Việt này **không giữ bảng tình trạng riêng**, để tránh lệch với bản tiếng Anh. Xem:

- [README.md](README.md): bảng "Machine" và "What works" của bản Tahoe;
- [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md): từng mục kèm ngày test, bằng chứng, phiên bản từng thành phần, lỗi đã biết và roadmap.

Tóm tắt ngắn (ngày 2026-11-25, chỉ trên máy tham chiếu, macOS 26.7.2 build 25G332): màn hình OLED 2880×1800 120 Hz, WindowServer và mọi app chạy trên Radeon 890M; giải mã video bằng phần cứng (H.264, HEVC, VP9, AV1); Wi-Fi, Bluetooth, loa, điều khiển ROG, Docker và iOS Simulator hoạt động; RTX 5060 thường được tắt lúc boot (chế độ Eco). Chưa xong hoặc chưa kiểm chứng: Android emulator (đã tìm ra nguyên nhân, bản sửa chưa được chạy thử trên máy), sleep/wake trên stack hiện tại, nhiệt khi chạy máy ảo nặng, HDR, cổng tai nghe, đầu đọc thẻ SD, thời lượng pin. EFI tham khảo trong `efi/` vẫn là cấu hình macOS 15.

## Các repo

Repo này giữ EFI tham khảo, tài liệu và trace, công cụ cho 890M và vài kext nhỏ. Các driver lớn nằm ở repo riêng; mã nguồn của chúng đã được gỡ khỏi repo này (lịch sử vẫn còn):

| Repo | Nội dung |
|---|---|
| repo này | `efi/`, tài liệu, `tools/890m` (VCNDec, bộ test video, công cụ đo), các kext `ItlXhciKick`, `StrixS0ix`, `StrixSbxMap`, `ItlDiag`, app `TapGuard` |
| [nvidia-macos-driver](https://github.com/thanhnndev/nvidia-macos-driver) (fork của NullMoth, PolyForm Noncommercial) | `NMXGPU`, `NMXAccel`, `NMXAGDC`, plugin Metal và trình dịch shader cho 890M |
| [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) | Wi-Fi MT7925 (`itlmt7925`, `itlmt7925Native`) và Bluetooth (`MtkBtFw`, `BtLeDlFix`) |
| [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) | `AsusWmi`, `AmdCppc`, `StrixDgpuGate`, app RogControl, `rogkeyd`, daemon chính sách CPU |
| [ryzen-hypervisor.framework](https://github.com/thanhnndev/ryzen-hypervisor.framework) (fork của OverlordDev) | `RyzenHV` |

## Cài đặt

**Chưa có hướng dẫn từng bước đã test cho việc cài mới Tahoe.** Thứ tự cài đã dùng, cách hoàn tác và khôi phục nằm trong [ghi chú release v2](.github/release-notes/v2.md) và [docs/FRESH-INSTALL.md](docs/FRESH-INSTALL.md) (tiếng Anh).

Với **macOS 15**: làm theo [docs/INSTALL.vi.md](docs/INSTALL.vi.md) và [docs/SCRIPTS.vi.md](docs/SCRIPTS.vi.md) với bản [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1). Hai tài liệu đó mô tả cấu hình macOS 15, không phải Tahoe.

## Đóng góp và giấy phép

Tác giả và người duy trì: [thanhnndev](https://github.com/thanhnndev). Chủ máy GA403WM có thể gửi issue theo mẫu **Hardware report**; đọc [CONTRIBUTING.md](CONTRIBUTING.md).

Ghi công và giấy phép đầy đủ: [NOTICE.md](NOTICE.md). Mã trong repo này dùng [Clear BSD License](LICENSE). **EFI dẫn xuất từ `nullmoth/1401`, và mọi thứ từ fork nvidia-macos-driver dùng PolyForm Noncommercial 1.0.0: chỉ sử dụng phi thương mại.**

Không liên kết với ASUS, Apple, NVIDIA, MediaTek, AMD hay NullMoth. Nhãn hiệu thuộc chủ sở hữu tương ứng; người dùng tự chịu trách nhiệm tuân thủ giấy phép macOS của Apple.
