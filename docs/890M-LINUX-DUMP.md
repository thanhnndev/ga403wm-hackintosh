# Radeon 890M on Linux: collected data

Host `ROG Zephyrus G14 GA403WM_GA403WM`, kernel `7.2.9-2-cachyos`, BIOS `GA403WM.310`, collected 2026-10-10T14:43:19Z, EUID 1000
GPU `0000:65:00.0` (`0x1002:0x150e rev 0xc1`), `card0`
ASUS gpu_mux_mode=0 dgpu_disable=0 (0 = Ultimate / dGPU drives the panel)

## PCI function and BARs

```
65:00.0 Display controller [0380]: Advanced Micro Devices, Inc. [AMD/ATI] Strix [Radeon 880M / 890M] [1002:150e] (rev c1)
```
```
	Interrupts: pin B disabled, MSI(X) routed to IRQ 87
	Region 0: Memory at 8210000000 (64-bit, prefetchable) [size=256M]
	Region 2: Memory at dc200000 (64-bit, prefetchable) [size=2M]
	Region 4: I/O ports at e000 [size=256]
	Region 5: Memory at dc600000 (32-bit, non-prefetchable) [size=512K]
	Capabilities: <access denied>
```
Sibling functions of the same device (power dependencies; the xHCI at .4 is one of the USB controllers of ItlXhciKick):

```
65:00.0 Display controller [0380]: Advanced Micro Devices, Inc. [AMD/ATI] Strix [Radeon 880M / 890M] [1002:150e] (rev c1)
65:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Radeon High Definition Audio Controller [1002:1640]
65:00.2 Encryption controller [1080]: Advanced Micro Devices, Inc. [AMD] Strix/Krackan/Strix Halo CCP/ASP [1022:17e0]
65:00.4 USB controller [0c03]: Advanced Micro Devices, Inc. [AMD] Device [1022:151e]
65:00.5 Multimedia controller [0480]: Advanced Micro Devices, Inc. [AMD] Audio Coprocessor [1022:15e2] (rev 70)
65:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Ryzen HD Audio Controller [1022:15e3]
```

## Memory

- mem_info_vram_total: 536870912
- mem_info_vis_vram_total: 536870912
- mem_info_gtt_total: 16351760384
- mem_info_vram_used: 501907456
- vbios_version: 113-STRIXEMU-001
- vbios_build: 00133300

## IP blocks (IP discovery table, sysfs)

```
IP        inst hw_id  ver   base_addr
ACP       0    14     7.0.0 0x00480000 0x02403800 0x3C038000 
ATHUB     0    35     3.3.0 0x00000C00 0x00013300 0x02408C00 0x3C08C000 
CLKA      0    6      14.0.0 0x00016C00 0x02401800 0x3C018000 
CLKA      1    6      14.0.0 0x00016E00 0x02401C00 0x3C01C000 
CLKA      2    6      14.0.0 0x00017000 0x02402000 0x3C020000 
CLKA      3    6      14.0.0 0x00017200 0x02402400 0x3C024000 
CLKA      4    6      14.0.0 0x0001B000 0x0242D800 0x3C2D8000 
CLKA      5    6      14.0.0 0x0001B200 0x0242DC00 0x3C2DC000 
CLKA      6    6      14.0.0 0x0001B400 0x0242E000 0x3C2E0000 
CLKA      7    6      14.0.0 0x0001B600 0x0242E400 0x3C2E4000 
CLKA      8    6      14.0.0 0x0001B800 0x0242F000 0x3C2F0000 
DBGU_IO   0    45     2.0.2 0x000001E0 0x0240B400 0x3C0B4000 
DBGU_IO   1    45     2.0.2 0x00000260 0x02413C00 0x3C13C000 
DBGU_IO   2    45     2.0.2 0x00000280 0x02416000 0x3C160000 
DF        0    46     4.9.0 0x00007000 0x00C00000 0x0240B800 0x07C00000 0x12400000 0x3C0B8000 
DMU       0    271    3.5.0 0x00000012 0x000000C0 0x000034C0 0x00009000 0x02403C00 0x3C03C000 
FCH       0    48     8.7.0 0x000002C0 0x00B40000 0x0240C000 0x11000000 0x3C0C0000 
FUSE      0    5      14.0.0 0x00017400 0x02401400 0x3C014000 
GC        0    11     11.5.0 0x00001260 0x0000A000 0x02402C00 0x3C02C000 
HDP       0    41     6.1.0 0x00000F20 0x0240A400 0x3C0A4000 
ISP       0    44     4.1.0 0x00018000 0x0240B000 0x3C0B0000 
LSDMA     0    91     6.1.0 0x00011400 0x02456800 0x3C568000 
MMHUB     0    34     3.3.0 0x00013200 0x0001A000 0x02408800 0x3C088000 
MP0       0    255    14.0.0 0x00016000 0x00DC0000 0x00E00000 0x00E40000 0x0243FC00 0x3C3FC000 
MP1       0    1      14.0.0 0x00016000 0x00DC0000 0x00E00000 0x00E40000 0x0243FC00 0x3C3FC000 
MP2       0    2      14.0.0 0x00016000 0x00DC0000 0x00E00000 0x00E40000 0x0243FC00 0x3C3FC000 
NBIF      0    108    7.11.0 0x00000000 0x00000014 0x00000D20 0x00010400 0x0241B000 0x04040000 0x3C1B0000 
OSSSYS    0    40     6.1.0 0x000010A0 0x0240A000 0x3C0A0000 
PCIE      0    70     6.7.0 0x00000000 0x00000014 0x00000D20 0x00010400 0x0241B000 0x04040000 0x3C1B0000 
SDMA0     0    42     6.1.0 0x00001260 0x0000A000 0x02402C00 0x3C02C000 
SMUIO     0    4      14.0.0 0x00016800 0x00016A00 0x00440000 0x02401000 0x3C010000 
THM       0    3      14.0.0 0x00016600 0x02400C00 0x3C00C000 
UMC       0    150    11.6.0 0x00014000 0x00054000 0x02425800 0x02425C00 0x3C258000 0x3C25C000 
UMC       1    150    11.6.0 0x00094000 0x000D4000 0x02426000 0x02426400 0x3C260000 0x3C264000 
UVD       0    12     4.0.5 0x00007800 0x00007E00 0x3C030000 
VPE       0    21     6.1.0 0x00011800 0x02456C00 0x3C56C000 
```

## Kernel log of the amdgpu probe

```
amdgpu: vga_switcheroo: detected switching method \_SB_.PCI0.GPPA.VGA_.ATPX handle
amdgpu: ATPX version 1, functions 0x00000200
amdgpu: Virtual CRAT table created for CPU
amdgpu: Topology: Add CPU node
amdgpu 0000:65:00.0: enabling device (0006 -> 0007)
amdgpu 0000:65:00.0: initializing kernel modesetting (IP DISCOVERY 0x1002:0x150E 0x1043:0x3998 0xC1).
amdgpu 0000:65:00.0: register mmio base: 0xDC600000
amdgpu 0000:65:00.0: register mmio size: 524288
amdgpu 0000:65:00.0: detected ip block number 0 <common_v1_0_0> (soc21_common)
amdgpu 0000:65:00.0: detected ip block number 1 <gmc_v11_0_0> (gmc_v11_0)
amdgpu 0000:65:00.0: detected ip block number 2 <ih_v6_1_0> (ih_v6_1)
amdgpu 0000:65:00.0: detected ip block number 3 <psp_v13_0_0> (psp)
amdgpu 0000:65:00.0: detected ip block number 4 <smu_v14_0_0> (smu)
amdgpu 0000:65:00.0: detected ip block number 5 <dce_v1_0_0> (dm)
amdgpu 0000:65:00.0: detected ip block number 6 <gfx_v11_0_0> (gfx_v11_0)
amdgpu 0000:65:00.0: detected ip block number 7 <sdma_v6_0_0> (sdma_v6_0)
amdgpu 0000:65:00.0: detected ip block number 8 <vcn_v4_0_5> (vcn_v4_0_5)
amdgpu 0000:65:00.0: detected ip block number 9 <jpeg_v4_0_5> (jpeg_v4_0_5)
amdgpu 0000:65:00.0: detected ip block number 10 <mes_v11_0_0> (mes_v11_0)
amdgpu 0000:65:00.0: detected ip block number 11 <vpe_v6_1_0> (vpe_v6_1)
amdgpu 0000:65:00.0: detected ip block number 12 <isp_v4_1_0> (isp_ip)
amdgpu 0000:65:00.0: Fetched VBIOS from VFCT
amdgpu 0000:65:00.0: [drm] ATOM BIOS: 113-STRIXEMU-001, build: 00133300, ver: 023.010.001.022.000001, 2024/12/19
amdgpu 0000:65:00.0: VPE: collaborate mode false
amdgpu 0000:65:00.0: [drm] Optional firmware "amdgpu/isp_4_1_0.bin" was not found
amdgpu 0000:65:00.0: Trusted Memory Zone (TMZ) feature disabled as experimental (default)
amdgpu 0000:65:00.0: vm size is 262144 GB, 4 levels, block size is 9-bit, fragment size is 9-bit
amdgpu 0000:65:00.0: VRAM: 512M 0x0000008000000000 - 0x000000801FFFFFFF (512M used)
amdgpu 0000:65:00.0: GART: 512M 0x00007FFF00000000 - 0x00007FFF1FFFFFFF
amdgpu 0000:65:00.0: [drm] Detected VRAM RAM=512M, BAR=512M
amdgpu 0000:65:00.0: [drm] RAM width 128bits LPDDR5
amdgpu 0000:65:00.0:  512M of VRAM memory ready
amdgpu 0000:65:00.0:  15594M of GTT memory ready.
amdgpu 0000:65:00.0: [drm] GART: num cpu pages 131072, num gpu pages 131072
amdgpu 0000:65:00.0: [drm] PCIE GART of 512M enabled (table at 0x000000801FB00000).
amdgpu 0000:65:00.0: [drm] USB controller 0000:65:00.4 D0 power state depends on 0000:65:00.0
amdgpu 0000:65:00.0: [drm] Loading DMUB firmware via PSP: version=0x09005300
amdgpu 0000:65:00.0: [VCN instance 0] Found VCN firmware Version ENC: 1.24 DEC: 9 VEP: 0 Revision: 34
amdgpu 0000:65:00.0: MES: vmid_mask_mmhub 0x0000ff00, vmid_mask_gfxhub 0x0000ff00
amdgpu 0000:65:00.0: MES: gfx_hqd_mask 0x00000002, compute_hqd_mask 0x0000000c, sdma_hqd_mask 0x000000fc
amdgpu 0000:65:00.0: reserve 0x8900000 from 0x8000000000 for PSP TMR
amdgpu 0000:65:00.0: RAS: optional ras ta ucode is not available
amdgpu 0000:65:00.0: RAP: optional rap ta ucode is not available
amdgpu 0000:65:00.0: SECUREDISPLAY: optional securedisplay ta ucode is not available
amdgpu 0000:65:00.0: smu driver if version = 0x00000007, smu fw if version = 0x00000007, smu fw program = 11, smu fw version = 0x0b5d0b00 (93.11.0)
amdgpu 0000:65:00.0: SMU is initialized successfully!
amdgpu 0000:65:00.0: [drm] Display Core v3.2.384 initialized on DCN 3.5
amdgpu 0000:65:00.0: [drm] DP-HDMI FRL PCON supported
amdgpu 0000:65:00.0: [drm] DMUB hardware initialized: version=0x09005300
amdgpu: Virtual CRAT table created for GPU
amdgpu: Topology: Add GPU node [0x1002:0x150e]
amdgpu 0000:65:00.0: SE 1, SH per SE 2, CU per SH 8, active_cu_number 16
amdgpu 0000:65:00.0: ring gfx_0.0.0 uses VM inv eng 0 on hub 0
amdgpu 0000:65:00.0: ring comp_1.0.0 uses VM inv eng 1 on hub 0
amdgpu 0000:65:00.0: ring comp_1.1.0 uses VM inv eng 4 on hub 0
amdgpu 0000:65:00.0: ring comp_1.2.0 uses VM inv eng 6 on hub 0
amdgpu 0000:65:00.0: ring comp_1.3.0 uses VM inv eng 7 on hub 0
amdgpu 0000:65:00.0: ring comp_1.0.1 uses VM inv eng 8 on hub 0
amdgpu 0000:65:00.0: ring comp_1.1.1 uses VM inv eng 9 on hub 0
amdgpu 0000:65:00.0: ring comp_1.2.1 uses VM inv eng 10 on hub 0
amdgpu 0000:65:00.0: ring comp_1.3.1 uses VM inv eng 11 on hub 0
amdgpu 0000:65:00.0: ring sdma0 uses VM inv eng 12 on hub 0
amdgpu 0000:65:00.0: ring vcn_unified_0 uses VM inv eng 0 on hub 8
amdgpu 0000:65:00.0: ring jpeg_dec_0 uses VM inv eng 1 on hub 8
amdgpu 0000:65:00.0: ring mes_kiq_3.1.0 uses VM inv eng 13 on hub 0
amdgpu 0000:65:00.0: ring vpe uses VM inv eng 4 on hub 8
amdgpu 0000:65:00.0: Runtime PM not available
amdgpu 0000:65:00.0: [drm] Registered 4 planes with drm panic
amdgpu 0000:65:00.0: [drm] Cannot find any crtc or sizes
```

## Firmware files this ASIC loads (linux-firmware)

```
amdgpu/dcn_3_5_dmcub.bin
amdgpu/gc_11_5_0_imu.bin
amdgpu/gc_11_5_0_me.bin
amdgpu/gc_11_5_0_mec.bin
amdgpu/gc_11_5_0_mes1.bin
amdgpu/gc_11_5_0_mes_2.bin
amdgpu/gc_11_5_0_pfp.bin
amdgpu/gc_11_5_0_rlc.bin
amdgpu/isp_4_1_1.bin
amdgpu/psp_14_0_0_ta.bin
amdgpu/psp_14_0_0_toc.bin
amdgpu/sdma_6_1_0.bin
amdgpu/vcn_4_0_5.bin
```

## Connectors

- card0-DP-2: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-3: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-4: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-5: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-6: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-7: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-8: disconnected, enabled=disabled, edid=0 bytes
- card0-DP-9: disconnected, enabled=disabled, edid=0 bytes
- card0-eDP-2: disconnected, enabled=disabled, edid=0 bytes
- card0-Writeback-1: unknown, enabled=disabled, edid=0 bytes

## Power and clocks

- power_dpm_state: performance
- power_dpm_force_performance_level: auto
- pp_dpm_sclk: 0: 600Mhz  1: 1042Mhz * 2: 2900Mhz
- pp_dpm_fclk: 0: 400Mhz  1: 1050Mhz  2: 1200Mhz  3: 1400Mhz  4: 1500Mhz  5: 1600Mhz  6: 1800Mhz  7: 1960Mhz
- pp_dpm_socclk: 0: 600Mhz  1: 736Mhz  2: 883Mhz  3: 981Mhz  4: 1104Mhz  5: 1261Mhz  6: 1261Mhz  7: 1472Mhz
- power/runtime_status: active
- power/control: on
- current_link_speed: 16.0 GT/s PCIe
- current_link_width: 16

## Vulkan (RADV)

```
	apiVersion         = 1.4.354
	deviceID           = 0x150e
	deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
	deviceName         = AMD Radeon 890M Graphics (RADV STRIX1)
	driverInfo         = Mesa 26.2.4-arch3.1
	apiVersion         = 1.4.351
	deviceID           = 0x2d59
	deviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
	deviceName         = NVIDIA GeForce RTX 5060 Laptop GPU
	driverInfo         = 615.78.08
```

## Privileged data

Not run as root: PCI config space, amdgpu debugfs and the ACPI VFCT table are skipped. Re-run with sudo.
