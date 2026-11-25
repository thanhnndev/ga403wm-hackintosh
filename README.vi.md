# GA403WM Hackintosh

<p align="center">
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-window.png" alt="RogControl 0.6.0 on macOS 26: live readings, performance mode, battery, custom limits, lighting, sound, GPU mode Eco and diagnostics" width="640">
  <img src="https://raw.githubusercontent.com/thanhnndev/rog-control-macos/rogcontrol-v0.6.0/docs/images/rogcontrol-popover.png" alt="RogControl 0.6.0 menu bar panel with the GPU row" width="200">
</p>
<p align="center"><em>RogControl 0.6.0: cửa sổ và bảng trên thanh menu (<a href="https://github.com/thanhnndev/rog-control-macos">rog-control-macos</a>). Ảnh render offscreen với số liệu mẫu.</em></p>

> **Bản release này (v2) dành cho macOS 26 Tahoe, màn hình trong máy chạy trên Radeon 890M.**
> macOS 15 Sequoia là bản trước: [v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1) và
> [kext-v1.1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/kext-v1.1). Đó là một cấu hình khác
> (màn hình chạy trên RTX 5060, 890M bị ẩn); hướng dẫn của nó là [docs/INSTALL.vi.md](docs/INSTALL.vi.md). Không trộn hai bản.

## Dự án vibe-code: đọc trước khi cài

Đây là dự án vibe-code, đang ở mức thử nghiệm. **Gần như toàn bộ mã và tài liệu do AI (Claude) viết**, được một người hướng dẫn và test trên **một chiếc máy**; chưa có audit độc lập. "Chạy" bên dưới nghĩa là "đã chạy trên chiếc máy đó vào ngày ghi trong [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md)".

- Kext chạy trong kernel; lỗi có thể gây panic, treo máy hoặc mất dữ liệu. `NMXGPU` điều khiển màn hình: lỗi ở đó có thể làm màn hình đen và phải tắt nóng. `AsusWmi` và `AmdCppc` ghi vào EC, BIOS và thanh ghi CPU; `RyzenHV` chạy máy ảo trong kernel; `StrixSbxMap` thêm một ngoại lệ vào Sandbox của macOS; `VCNDec` và một luật sandbox được cài lên system volume.
- SIP gần như tắt, AMFI nới lỏng, Secure Boot tắt.
- Log, bản dump `ioreg` và báo cáo panic chứa số serial, địa chỉ MAC và SSID/BSSID xung quanh; che trước khi đăng.
- Backup ổ đĩa và giữ Windows hoặc Linux boot được: trong quá trình phát triển đã phải dùng nhiều lần để hoàn tác thay đổi GPU. Không bảo hành; xem [LICENSE](LICENSE).

Repo chỉ chứa giá trị SMBIOS giả `CHANGE_ME_*`. CI kiểm tra `efi/OC/config.plist` để chặn định danh thật.

## Giới thiệu

macOS 26 Tahoe trên **ASUS ROG Zephyrus G14 (2025), GA403WM**: Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop.
EFI OpenCore tham khảo, tài liệu và trace, công cụ cho 890M và vài kext nhỏ cho chiếc máy này.

[English](README.md) · [**Tình trạng và roadmap (tiếng Anh)**](docs/STATE-AND-ROADMAP.md) · [Ghi chú release v2 (tiếng Anh)](.github/release-notes/v2.md) · [Release](https://github.com/thanhnndev/ga403wm-hackintosh/releases) · [Cài macOS 15 (v1)](docs/INSTALL.vi.md)

Repo chưa có ảnh "About This Mac" trên Tahoe; [docs/images/hero.jpg](docs/images/hero.jpg) và
[docs/images/about-this-mac.png](docs/images/about-this-mac.png) là cấu hình macOS 15 tháng 10/2026 (v1).

## Các repo liên quan

Tất cả thuộc cùng một dự án: macOS trên một máy ASUS ROG Zephyrus G14 **GA403WM**.

| Repo | Là gì | Release mới nhất |
|---|---|---|
| [ga403wm-hackintosh](https://github.com/thanhnndev/ga403wm-hackintosh) | Repo chính: EFI OpenCore, ACPI, ghi chú cài đặt, tình trạng và roadmap, các kext phụ | [v2 (macOS 26 Tahoe)](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v2) |
| [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) | Wi-Fi (`itlmt7925`, `itlmt7925Native`) và Bluetooth (`MtkBtFw`, `BtLeDlFix`) cho MediaTek MT7925 | Wi-Fi [v2.0-beta.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/v2.0-beta.1), Bluetooth [bt-v1.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/bt-v1.1) |
| [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) | App RogControl, `AsusWmi`, `AmdCppc`, `rogkeyd`, `StrixDgpuGate` | [rogcontrol-v0.6.0](https://github.com/thanhnndev/rog-control-macos/releases/tag/rogcontrol-v0.6.0) |
| [nvidia-macos-driver](https://github.com/thanhnndev/nvidia-macos-driver) (fork của [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)) | Driver màn hình và Metal cho Radeon 890M của máy này (`NMXGPU` và Metal plugin), giấy phép PolyForm Noncommercial | tag mã nguồn [ga403wm-890m-out50](https://github.com/thanhnndev/nvidia-macos-driver/releases/tag/ga403wm-890m-out50), [ga403wm-890m-plugin-a6cec1b](https://github.com/thanhnndev/nvidia-macos-driver/releases/tag/ga403wm-890m-plugin-a6cec1b) |
| [ryzen-hypervisor.framework](https://github.com/thanhnndev/ryzen-hypervisor.framework) (fork của [OverlordDev/ryzen-hypervisor.framework](https://github.com/OverlordDev/ryzen-hypervisor.framework)) | Hypervisor AMD-V cho Docker và Android emulator trên Ryzen, kèm các bản sửa cho máy này | tag mã nguồn [v0.7.24-ga403wm](https://github.com/thanhnndev/ryzen-hypervisor.framework/releases/tag/v0.7.24-ga403wm) |
| [strix-890m-macos](https://github.com/thanhnndev/strix-890m-macos) | Nghiên cứu Radeon 890M trước đây. Đã được driver ở trên thay thế | chưa có |

## Máy

| | |
|---|---|
| Máy | ASUS ROG Zephyrus G14 2025, model GA403WM |
| macOS | 26 Tahoe, 26.7.2 (25G332, Darwin 25.6), cài trên ổ trong |
| Bootloader | OpenCore 1.0.9 với bản vá timer Zen 5 ([patches/opencore](patches/opencore)) |
| CPU | AMD Ryzen AI 9 HX 370 ("Strix Point": 4 Zen 5 + 8 Zen 5c cores, 24 threads) |
| iGPU | Radeon 890M. **Chạy màn hình trong máy, WindowServer và mọi app** qua `NMXGPU` (port mã nguồn amdgpu của Linux) và plugin Metal-trên-Vulkan chạy trên RADV, từ [nvidia-macos-driver fork](https://github.com/thanhnndev/nvidia-macos-driver) |
| dGPU | NVIDIA GeForce RTX 5060 Laptop. Tắt nguồn lúc boot ở chế độ Eco (`StrixDgpuGate`), hoặc chạy bằng [NullMoth's NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) 2.7.1 ở chế độ Standard. Cổng HDMI nối vào card này |
| Màn hình | 2880x1800 OLED, 120 Hz |
| RAM | 32 GB |
| Wi-Fi / Bluetooth | MediaTek MT7925: PCI `14c3:7925` (Wi-Fi), USB `0489:e11e` (Bluetooth) |
| Audio | Realtek ALC285 codec + two Cirrus CS35L56 amplifiers on I2C |
| USB | four AMD xHCI controllers `1022:151e`, `151f`, `151a`, `151b` |
| Nhập liệu | I2C-HID touchpad `093a:3011`, USB keyboard `0b05:19b6` |
| Lưu trữ | NVMe SSD, Realtek SD-card reader |
| Trạng thái ngủ | S0 idle, S4, S5 (firmware không có S3) |

## Những gì chạy được

| Hạng mục | Trạng thái | Ghi chú | Ở đâu |
|---|---|---|---|
| Boot macOS 26.7.2 từ ổ trong | chạy | Boot ở chế độ Eco tới màn hình đăng nhập sau 14-33 s kể từ lúc kernel chạy | [docs/BOOT-TIMELINE.md](docs/BOOT-TIMELINE.md) |
| Timer / tính FSB cho Zen 5 | chạy | sửa bằng bản vá OpenCore | [patches/opencore](patches/opencore) |
| Màn hình trong máy chạy trên 890M | chạy | 2880x1800 ở 120 Hz, lật trang zero-copy | [docs/FRAME-PATH.md](docs/FRAME-PATH.md) |
| Độ sáng (thanh trượt và phím) | chạy | xử lý trong NMXGPU | [docs/890M-ROADMAP.md](docs/890M-ROADMAP.md) |
| HiDPI | một phần | chỉ "looks like 1440x900" và độ phân giải gốc; chưa có cỡ scale khác | [docs/890M-TRACE.md](docs/890M-TRACE.md) |
| HDR | **chưa kiểm chứng** | | |
| WindowServer và Metal của app trên 890M | chạy | khoảng 7 ms CPU mỗi khung hình trong WindowServer (Mac thật: khoảng 1 ms) | [docs/WS-CPU.md](docs/WS-CPU.md) |
| WebGL: Chrome, Edge, Safari | chạy | Safari cần `StrixSbxMap`, một ngoại lệ Sandbox cố định | [docs/MAPS-WEBGL.md](docs/MAPS-WEBGL.md), [docs/890M-ROADMAP.md](docs/890M-ROADMAP.md) |
| Giải mã video phần cứng (H.264, HEVC, VP9, AV1; 8 và 10 bit) | chạy | `VCNDec` trên VCN của 890M; 58/59 ô của ma trận trong Chrome, Safari và QuickTime (đo trên 0.2.0; 0.2.1 đang chạy, mới test trong tiến trình). Mã hóa phần cứng: chưa kiểm chứng | [docs/VIDEO-CODEC-MATRIX.md](docs/VIDEO-CODEC-MATRIX.md) |
| RTX 5060, chế độ Eco | chạy | card tắt và rời bus PCI; không có HDMI ở chế độ này; chưa test với ngủ và cắm/rút sạc | [docs/BOOT-TIMELINE.md](docs/BOOT-TIMELINE.md) |
| RTX 5060, chế độ Standard | một phần | stack kernel NVIDIA boot được; app không có thiết bị Metal từ RTX; HDMI chưa test lại; đổi chế độ cần khởi động lại | [docs/890M-ROADMAP.md](docs/890M-ROADMAP.md) |
| Wi-Fi | chạy | menu Wi-Fi gốc, WPA2-PSK trên 2.4/5 GHz, HE 160 MHz; đã dùng một mạng mở ngày 2026-11-11. Chưa có WPA3, 802.1X, 6 GHz; AirDrop chưa kiểm chứng. Release [v2.0-beta.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/v2.0-beta.1) | [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) |
| Bluetooth | chạy | `MtkBtFw` 0.3.1 + `BtLeDlFix` 1.4.0 (release [bt-v1.1](https://github.com/thanhnndev/mt7925-macos/releases/tag/bt-v1.1)); chuột BLE dùng hằng ngày; ghép bàn phím chưa được ghi lại | [mt7925-macos](https://github.com/thanhnndev/mt7925-macos/blob/main/docs/BLUETOOTH.md) |
| Loa | chạy | cả bốn loa; cần `StrixAmp` và driver RogAudio | [docs/AUDIO-TAHOE.md](docs/AUDIO-TAHOE.md) |
| Micro | một phần | cặp micro trong và lọc ồn chạy; micro thứ ba chưa dùng được; gain đôi khi bị về mức thấp nhất | docs/AUDIO-ROG.md (nhánh `research/audio-rog-dolby`) |
| Cổng tai nghe | **chưa kiểm chứng** trên Tahoe | | |
| Bàn phím, thiết bị USB | chạy | `ItlXhciKick` sửa độ trễ 2 s khi nhả phím | [docs/USB-XHCI-LAG.md](docs/USB-XHCI-LAG.md) |
| Phím Fn | một phần | tắt tiếng và âm lượng là phím gốc; phần còn lại qua `rogkeyd`; Fn+F6 và Fn+F10 chưa gán | [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) |
| Touchpad | chạy | VoodooI2C ở chế độ polling bắt buộc | [efi/KEXTS.md](efi/KEXTS.md) |
| Webcam | chạy | UVC | |
| Đầu đọc thẻ SD | **chưa kiểm chứng** | driver đã nạp | |
| Profile ASUS, đường cong quạt, giới hạn công suất, giới hạn sạc, đèn bàn phím | chạy | `AsusWmi` + RogControl | [docs/PLATFORM-LIMITS.md](docs/PLATFORM-LIMITS.md), [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) |
| Ngủ / thức | một phần | ngủ S0 idle, đánh thức bằng nắp và nút nguồn đạt ngày 2026-11-07; **chưa test lại trên stack hiện tại**; chưa đạt S0i3 | [docs/890M-TRACE.md](docs/890M-TRACE.md) |
| Tắt máy | chạy | tắt hẳn | [docs/SHUTDOWN-TIMELINE.md](docs/SHUTDOWN-TIMELINE.md) |
| Điện năng và nhiệt | một phần | việc nhẹ 17 W / 57 C (2026-11-23); tải Docker + emulator 62 W / 95 C (2026-11-16, chưa đo lại); công suất GPU theo tốc độ compositing (màn hình tĩnh 0.09 W trên rail GFX và 6.2 W socket, 81-91 lần lật/s 12.4-19.3 W; đọc ngày 2026-11-25); chưa đo mức nền khi rảnh có kiểm soát; thời lượng pin ở Eco chưa đo | [docs/POWER-UNDER-LOAD.md](docs/POWER-UNDER-LOAD.md), [docs/POWER-FEATURES.md](docs/POWER-FEATURES.md), [docs/POWER-FLOOR.md](docs/POWER-FLOOR.md) |
| Docker Desktop | chạy | trên `RyzenHV` (kext hypervisor AMD SVM) | [docs/RYZENHV-GUEST-MEM.md](docs/RYZENHV-GUEST-MEM.md) |
| Android emulator | chạy | boot được từ RyzenHV 0.7.24 (kiểm chứng 2026-11-25; cold boot 24-32 s trên AVD thử). Lần chạy đầu sau khi cập nhật phải là cold boot (Device Manager > Cold Boot Now): snapshot lưu từ máy ảo bị treo sẽ khôi phục luôn trạng thái treo. Khôi phục snapshot từ lần boot tốt và render bằng GPU host **chưa kiểm chứng** (test với GPU phần mềm mặc định) | [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md) |
| iOS Simulator | chạy | render trên 890M, 60 fps trong bench | [docs/SIMULATOR-PERF.md](docs/SIMULATOR-PERF.md) |
| EFI tham khảo trong `efi/` | một phần | `config.plist` và SSDT xuất từ ESP Tahoe đang chạy ngày 2026-11-25. **Chỉ để tham khảo cho đúng chiếc máy này, không boot được ngay**: serial, MLB, UUID và ROM là giá trị giả, thuộc tính `vbios` của 890M để trống (tự đưa ảnh VBIOS của card mình vào), không kèm kext (32 kext bên thứ ba được liệt kê kèm hash) | [efi/README.md](efi/README.md) |
| Cài mới lên ổ trống | một phần | đã làm một lần bằng tay; chưa có hướng dẫn hay trình cài đã test | [docs/FRESH-INSTALL.md](docs/FRESH-INSTALL.md) |

Ngày, bằng chứng, phiên bản chính xác và lỗi đã biết: [docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md).

## Repo này có gì

Repo này giữ EFI tham khảo, tài liệu và trace, công cụ cho 890M và vài kext nhỏ. Các driver lớn nằm ở repo riêng (xem
[Các repo liên quan](#các-repo-liên-quan)); mã nguồn của chúng đã được gỡ khỏi repo này (lịch sử vẫn còn). `strix-890m-macos`
giữ một bản sao các kext màn hình lúc boot và trace trước đây (push cuối 2026-11-02); các file đó vẫn còn ở đây và chưa
quyết định repo nào là nhà của chúng.

```
efi/                 config.plist + SSDT của OpenCore xuất từ ESP Tahoe đang chạy ngày 2026-11-25 (serial/MLB/UUID/ROM là
                     giá trị giả, thuộc tính vbios để trống) và danh sách kext bên thứ ba. Để tham khảo, không boot được ngay
kexts/ItlXhciKick    giữ ring sự kiện xHCI thứ hai được phục vụ trên controller AMD một vector (sửa lag USB)
kexts/StrixS0ix      ngủ S0 idle: gợi ý PMC, đỗ CPU, đánh thức bằng nắp và nút nguồn
kexts/StrixSbxMap    plugin Lilu: cho tiến trình GPU của WebKit map các file plugin Metal 890M đã ghim (WebGL trên Safari)
kexts/ItlDiag        chẩn đoán lúc boot, ghi vào NVRAM; công cụ debug
kexts/StrixGOP, StrixAccel, StrixMetalGate, StrixHeadroom, StrixProbe
                     nghiên cứu màn hình lúc boot trước đây; đã được NMXGPU thay thế và tắt trên máy tham chiếu
macos/TapGuard       bỏ qua chạm touchpad khi đang gõ phím
tools/890m/vcndec    VCNDec: bộ giải mã VideoToolbox trên VCN của 890M (H.264, HEVC, VP9, AV1)
tools/890m/video-suite  bộ test video cục bộ, không quảng cáo, và kết quả ma trận codec
tools/890m/          probe Metal, Vulkan và DRM, repro WebGL, script đọc frame-path và điện năng
tools/               trình sửa config OpenCore, đọc kernel collection, probe sức khỏe và idle, bench simulator
scripts/             script build, cài và hoàn tác cho từng phần, build RADV, xuất EFI và kiểm tra riêng tư, khôi phục từ
                     Linux và Windows. Nhiều script cài từng bước gắn với lịch sử của máy tham chiếu, giữ lại làm hồ sơ
patches/opencore/    bản vá OpenCorePkg cho Zen 5
patches/nmx, patches/power-floor  bản vá cho cây mã NMXGPU (fork là nguồn chính)
abi/, include/, acpi/  dump ACPI, ghi chú ABI và header dùng cho nghiên cứu
test/                test chạy trên máy host cho config và công cụ Strix
docs/                tình trạng và roadmap, trace 890M, frame path, video, điện năng, boot và tắt máy, thiết kế cài đặt
```

`scripts/build.sh` mặc định build `ItlXhciKick` và `ItlDiag`, các kext `Strix*` khi gọi tên. Không build được từ nhánh này:
`StrixAmp` và driver RogAudio (nhánh `research/audio-rog-dolby`), và mọi thứ trong các repo liên quan.

## Cài đặt

**Chưa có hướng dẫn từng bước đã test cho việc cài mới Tahoe.** Toàn bộ stack được cài mới một lần, bằng tay, ngày
2026-11-07. Những gì đang có (tiếng Anh):

- thứ tự cài đã chạy được, cách hoàn tác và khôi phục: [ghi chú release v2](.github/release-notes/v2.md);
- thiết kế rút ra từ lần cài đó và bài học: [docs/FRESH-INSTALL.md](docs/FRESH-INSTALL.md),
  [docs/FRESH-INSTALL-LESSONS-2026-11-07.md](docs/FRESH-INSTALL-LESSONS-2026-11-07.md);
- ghi chú chuyển từ macOS 15: [docs/TAHOE-MIGRATION.md](docs/TAHOE-MIGRATION.md).

Nhiều script trong `scripts/` chỉ nhận đúng các binary trong lịch sử của máy tham chiếu. Đọc script trước khi chạy.

Với **macOS 15**: làm theo [docs/INSTALL.vi.md](docs/INSTALL.vi.md) và [docs/SCRIPTS.vi.md](docs/SCRIPTS.vi.md) với bản
[v1](https://github.com/thanhnndev/ga403wm-hackintosh/releases/tag/v1). Hai tài liệu đó mô tả cấu hình macOS 15, không phải Tahoe.
Chủ máy ASUS khác (GA403UV, ...): xem [docs/OTHER-MODELS.md](docs/OTHER-MODELS.md).

## Bước tiếp theo

[docs/STATE-AND-ROADMAP.md](docs/STATE-AND-ROADMAP.md), mục 5, là roadmap của bản này: pipeline màu bằng phần cứng (bỏ bước
tô màu mỗi khung hình trên GPU), con trỏ bằng plane phần cứng, ai điều khiển việc lật khung hình dưới tải hằng ngày và
composition theo vùng thay đổi, việc import surface lúc rảnh của WindowServer, các việc tiếp theo của RyzenHV, và các mục
chưa kiểm chứng (ngủ trên stack hiện tại, HDR, mã hóa video phần cứng).

## Ghi công

Cấu hình này dựa trên công sức của nhiều người. Danh sách gồm những gì máy tham chiếu thật sự dùng (đối chiếu với
`efi/kexts.json`, `efi/OC/config.plist`, `NOTICE.md` và script build) và mã nguồn mà các driver được phát triển từ đó.
Binary của bên thứ ba không được phân phối lại ở đây; giấy phép nằm trong [NOTICE.md](NOTICE.md) và trong từng dự án.

**Boot và bản vá kernel**

| Dự án | Dùng cho |
|---|---|
| [OpenCore](https://github.com/acidanthera/OpenCorePkg) (acidanthera) | boot loader; `patches/opencore/fix-zen5-fsb.diff` là bản vá cho `OcCpuLib` của nó |
| [nullmoth/1401](https://github.com/nullmoth/1401) (NullMoth) | cấu hình OpenCore và SSDT gốc mà `efi/` dẫn xuất từ đó |
| [AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) kernel patches (AMD-OSX; patch comments name algrey, XLNC, Shaneee, Zormeister, Goldfish64, Visual, laobamac) and CaseySJ's IOPCIFamily patches | các mục `Kernel > Patch` cho XNU chạy trên CPU AMD, theo cấu hình gốc |
| [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) guides | đọc trong lúc dựng máy; nguồn của `AppleMCEReporterDisabler` |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) (acidanthera) | header và thư viện kernel cho `scripts/build.sh` |

**Kext trên ESP (bên thứ ba)**

| Dự án | Dùng cho |
|---|---|
| [Lilu](https://github.com/acidanthera/Lilu) (acidanthera) | framework vá cho các plug-in bên dưới và cho `StrixSbxMap`, `BtLeDlFix` |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) with SMCBatteryManager and SMCLightSensor (acidanthera) | giả lập SMC, trạng thái pin; plug-in cảm biến ánh sáng có trên ESP nhưng tắt |
| [AppleALC](https://github.com/acidanthera/AppleALC) (acidanthera) | codec ALC285 (bản build riêng có layout GA403WM) |
| [SimpleHDA](https://github.com/laobamac/SimpleHDA) (laobamac) | đưa AppleHDA trở lại trên macOS 26 |
| [WhateverGreen](https://github.com/acidanthera/WhateverGreen) (acidanthera) | có trên ESP, tắt trong cấu hình này |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) (acidanthera) | quản lý điện NVMe |
| [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) (acidanthera) | phím tắt độ sáng |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) (acidanthera) | tên CPU và bản vá `sbvmm` |
| [BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM) (acidanthera, BrcmPatchRAM) | cho `bluetoothd` nhận controller không phải của Apple |
| [AMFIPass](https://github.com/dortania/OpenCore-Legacy-Patcher) (dhinakg, shipped with OpenCore Legacy Patcher) | cho binary hệ thống nạp các bundle driver ký ad hoc |
| [USBToolBox](https://github.com/USBToolBox/kext) (dhinakg) | bản đồ cổng USB |
| [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [VoodooI2CHID](https://github.com/VoodooI2C/VoodooI2CHID), VoodooGPIO, VoodooInput | touchpad I2C-HID |
| [NullEthernet](https://github.com/RehabMan/OS-X-Null-Ethernet) (RehabMan) | `en0` giả |
| [ForgedInvariant](https://github.com/ChefKissInc/ForgedInvariant) (ChefKiss) | đồng bộ TSC trên AMD |
| [Sinetek-rtsx](https://github.com/sinetek/Sinetek-rtsx) | driver đầu đọc thẻ SD Realtek (đã nạp; chức năng chưa kiểm chứng) |
| [HoRNDIS](https://github.com/jwise/HoRNDIS) (Joshua Wise) | chia sẻ mạng USB từ điện thoại Android lúc cài |
| AppleMCEReporterDisabler | chặn panic AppleIntelMCEReporter trên AMD |

**GPU, video và ảo hóa**

| Dự án | Dùng cho |
|---|---|
| [NullMoth's NVIDIA driver for macOS](https://github.com/nullmoth/nvidia-macos-driver) (NullMoth) | driver RTX 5060 ở chế độ Standard, và stack NMX (`NMXGPU`, `NMXAccel`, plugin Metal và trình dịch) mà phần 890M là một [fork](https://github.com/thanhnndev/nvidia-macos-driver) của nó |
| The Linux kernel's [amdgpu and DRM](https://gitlab.freedesktop.org/drm/kernel) (AMD and the DRM maintainers) | mã driver mà `NMXGPU` port từ đó (gồm cả display core), và luồng tham chiếu để tài liệu so sánh |
| FreeBSD [drm-kmod](https://github.com/freebsd/drm-kmod) and LinuxKPI ([freebsd-src](https://github.com/freebsd/freebsd-src)) | bản amdgpu được build, và lớp tương thích mà lớp "xkpi" của port lấy từ đó |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) / RADV, with libdrm and glslang | driver Vulkan dưới plugin Metal và giải mã video VCN (build bằng `scripts/radv`) |
| [FFmpeg](https://ffmpeg.org/) (libavcodec, LGPL build) and the Khronos Vulkan headers | `VCNDec`: giải mã video Vulkan cho H.264, HEVC, VP9 và AV1 (`tools/890m/vcndec/ff-build.sh`) |
| [ryzen-hypervisor.framework](https://github.com/OverlordDev/ryzen-hypervisor.framework) (OverlordDev) | `RyzenHV`, hypervisor SVM mà Docker và Android emulator chạy trên đó; máy chạy một [fork](https://github.com/thanhnndev/ryzen-hypervisor.framework) |

**Wi-Fi, Bluetooth và điều khiển ASUS (qua các repo anh em)**

| Dự án | Dùng cho |
|---|---|
| The Linux kernel's `mt76` / `mt7925` and `btmtk` drivers, and MediaTek's MT7925 firmware | lớp phần cứng, tham chiếu và firmware của [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) |
| [asusctl](https://gitlab.com/asus-linux/asusctl) / [asus-linux.org](https://asus-linux.org/) and the Linux `asus-wmi` / `asus-armoury` drivers | tham chiếu cho giao diện ASUS WMI và EC trong [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) |
| [G-Helper](https://github.com/seerge/g-helper), Linux `k10temp` | chuỗi HID cho đèn bàn phím và Slash, và địa chỉ thanh ghi Tctl dùng trong rog-control-macos (xem `NOTICE.md` của nó). Không dùng mã `itlwm` ở đâu cả |

**Tác giả**

| | |
|---|---|
| [Claude](https://www.anthropic.com/claude) (Anthropic) | viết gần như toàn bộ mã và tài liệu của dự án, do người duy trì chỉ đạo và test |

## Đóng góp và giấy phép

Người duy trì: [thanhnndev](https://github.com/thanhnndev). Chủ máy GA403WM: dùng mẫu issue **Hardware report** và đọc [CONTRIBUTING.md](CONTRIBUTING.md).

Mã trong repo này dùng [Clear BSD License](LICENSE). Giấy phép bên thứ ba: [NOTICE.md](NOTICE.md). **EFI dẫn xuất từ `nullmoth/1401`, và mọi thứ từ fork nvidia-macos-driver (NMXGPU, NMXAccel, plugin Metal, trình dịch) dùng PolyForm Noncommercial 1.0.0: chỉ sử dụng phi thương mại**; không có mã nào của fork trong tài sản release của repo này.

Không liên kết với ASUS, Apple, NVIDIA, MediaTek, AMD hay NullMoth. Nhãn hiệu thuộc chủ sở hữu tương ứng; người dùng tự chịu trách nhiệm tuân thủ giấy phép macOS của Apple.
