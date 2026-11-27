# Ghi công

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

[English](CREDITS.md)
