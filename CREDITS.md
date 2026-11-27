# Credits

[Tiếng Việt](CREDITS.vi.md)

This setup stands on other people's work. The list covers what the reference machine really uses (checked against
`efi/kexts.json`, `efi/OC/config.plist`, `NOTICE.md` and the build scripts) and the code the drivers were derived from.
Third-party binaries are not redistributed here; licences are in [NOTICE.md](NOTICE.md) and in each project.

**Boot and kernel patches**

| Project | Used for |
|---|---|
| [OpenCore](https://github.com/acidanthera/OpenCorePkg) (acidanthera) | the boot loader; `patches/opencore/fix-zen5-fsb.diff` is a patch against its `OcCpuLib` |
| [nullmoth/1401](https://github.com/nullmoth/1401) (NullMoth) | the base OpenCore configuration and SSDTs that `efi/` derives from |
| [AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) kernel patches (AMD-OSX; patch comments name algrey, XLNC, Shaneee, Zormeister, Goldfish64, Visual, laobamac) and CaseySJ's IOPCIFamily patches | the `Kernel > Patch` entries that let XNU run on an AMD CPU, as shipped by the base configuration |
| [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) guides | read during the bring-up; source of `AppleMCEReporterDisabler` |
| [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) (acidanthera) | kernel headers and libraries for `scripts/build.sh` |

**Kexts on the ESP (third-party)**

| Project | Used for |
|---|---|
| [Lilu](https://github.com/acidanthera/Lilu) (acidanthera) | patching framework for the plug-ins below and for `StrixSbxMap`, `BtLeDlFix` |
| [VirtualSMC](https://github.com/acidanthera/VirtualSMC) with SMCBatteryManager and SMCLightSensor (acidanthera) | SMC emulation, battery status; the light-sensor plug-in is on the ESP but disabled |
| [AppleALC](https://github.com/acidanthera/AppleALC) (acidanthera) | ALC285 codec (a local build with a GA403WM layout) |
| [SimpleHDA](https://github.com/laobamac/SimpleHDA) (laobamac) | brings AppleHDA back on macOS 26 |
| [WhateverGreen](https://github.com/acidanthera/WhateverGreen) (acidanthera) | on the ESP, disabled in this configuration |
| [NVMeFix](https://github.com/acidanthera/NVMeFix) (acidanthera) | NVMe power management |
| [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) (acidanthera) | brightness hot keys |
| [RestrictEvents](https://github.com/acidanthera/RestrictEvents) (acidanthera) | CPU name and the `sbvmm` patch |
| [BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM) (acidanthera, BrcmPatchRAM) | lets `bluetoothd` accept a non-Apple controller |
| [AMFIPass](https://github.com/dortania/OpenCore-Legacy-Patcher) (dhinakg, shipped with OpenCore Legacy Patcher) | lets platform binaries load the ad hoc signed driver bundles |
| [USBToolBox](https://github.com/USBToolBox/kext) (dhinakg) | USB port map |
| [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [VoodooI2CHID](https://github.com/VoodooI2C/VoodooI2CHID), VoodooGPIO, VoodooInput | the I2C-HID touchpad |
| [NullEthernet](https://github.com/RehabMan/OS-X-Null-Ethernet) (RehabMan) | the fake `en0` |
| [ForgedInvariant](https://github.com/ChefKissInc/ForgedInvariant) (ChefKiss) | TSC synchronisation on AMD |
| [Sinetek-rtsx](https://github.com/sinetek/Sinetek-rtsx) | Realtek SD-card reader driver (loaded; function not verified) |
| [HoRNDIS](https://github.com/jwise/HoRNDIS) (Joshua Wise) | USB tethering from an Android phone while installing |
| AppleMCEReporterDisabler | stops the AppleIntelMCEReporter panic on AMD |

**GPU, video and virtualization**

| Project | Used for |
|---|---|
| [NullMoth's NVIDIA driver for macOS](https://github.com/nullmoth/nvidia-macos-driver) (NullMoth) | the RTX 5060 driver in Standard mode, and the NMX stack (`NMXGPU`, `NMXAccel`, the Metal plugin and translator) that the 890M work is a [fork](https://github.com/thanhnndev/nvidia-macos-driver) of |
| The Linux kernel's [amdgpu and DRM](https://gitlab.freedesktop.org/drm/kernel) (AMD and the DRM maintainers) | the driver source `NMXGPU` is a port of (display core included), and the reference flow the documents compare against |
| FreeBSD [drm-kmod](https://github.com/freebsd/drm-kmod) and LinuxKPI ([freebsd-src](https://github.com/freebsd/freebsd-src)) | the copy of amdgpu that is built, and the compatibility layer the port's "xkpi" layer comes from |
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) / RADV, with libdrm and glslang | the Vulkan driver under the Metal plugin and the VCN video decode (built with `scripts/radv`) |
| [FFmpeg](https://ffmpeg.org/) (libavcodec, LGPL build) and the Khronos Vulkan headers | `VCNDec`: Vulkan video decode of H.264, HEVC, VP9 and AV1 (`tools/890m/vcndec/ff-build.sh`) |
| [ryzen-hypervisor.framework](https://github.com/OverlordDev/ryzen-hypervisor.framework) (OverlordDev) | `RyzenHV`, the SVM hypervisor Docker and the Android emulator run on; the machine runs a [fork](https://github.com/thanhnndev/ryzen-hypervisor.framework) |

**Wi-Fi, Bluetooth and ASUS controls (through the sibling repositories)**

| Project | Used for |
|---|---|
| The Linux kernel's `mt76` / `mt7925` and `btmtk` drivers, and MediaTek's MT7925 firmware | hardware layer, reference and firmware of [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) |
| [asusctl](https://gitlab.com/asus-linux/asusctl) / [asus-linux.org](https://asus-linux.org/) and the Linux `asus-wmi` / `asus-armoury` drivers | reference for the ASUS WMI and EC interface in [rog-control-macos](https://github.com/thanhnndev/rog-control-macos) |
| [G-Helper](https://github.com/seerge/g-helper), Linux `k10temp` | the keyboard-light and Slash HID sequences and the Tctl register address used in rog-control-macos (see its `NOTICE.md`). No `itlwm` code is used anywhere |

**Authoring**

| | |
|---|---|
| [Claude](https://www.anthropic.com/claude) (Anthropic) | wrote almost all of the code and documents of this project, directed and tested by the maintainer |
