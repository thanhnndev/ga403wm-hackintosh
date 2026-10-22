# Radeon 890M / Cobalt64: portability research

Ngày nghiên cứu: 2026-10-13. Nhánh: `research/890m-cobalt64`.

## Kết luận

890M là một target bring-up mới. Có thể tái sử dụng kiến trúc IOKit/user-client,
BO/VA/sync và phần Metal-over-Vulkan của Cobalt64, nhưng chưa có bằng chứng chạy
được trên máy này. Đổi PCI ID hoặc firmware filenames không đủ: hardware init,
GPU identity của RADV, memory model và display implementation đều khác.

Hướng ưu tiên: probe riêng → framebuffer kế thừa GOP nếu khả thi → bring-up
memory/SDMA/GFX → RADV headless → Metal → desktop. Native DCN 3.5/eDP modesetting
là một nhánh công việc sau khi đã có baseline; không nhất thiết phải xong trước
khi chứng minh compute. Không dùng xlat12 làm đường đầu tiên.

## Nguồn và phạm vi kiểm chứng

- [Cobalt64](https://github.com/Almosst-DEV/Cobalt64/blob/d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65/README.md), commit `d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65`; source clone tại `ref/Cobalt64`.
- [RDNA4FB](https://github.com/somestupidgirl/RDNA4FB/blob/5ff69aade9a7feb18bb665040661de33ccfe68ba/README.md), commit `5ff69aade9a7feb18bb665040661de33ccfe68ba`; `ref/RDNA4FB`.
- Linux upstream commit `24a19b953e2a3d0ea5a8c4951a0ab8f32720c907`; file chọn lọc tại `ref/linux-890m`, manifest `FETCH.json`.
  Đây là source tham chiếu, không phải source chính xác của kernel CachyOS
  `7.2.9-2-cachyos` đang chạy; cần kiểm tra backport/delta trước khi port register logic.
- Mesa base của 9 patch Cobalt64: `f5cb8ee032adabef599ae892ec4e42d796b84da9`,
  `26.3.0-devel`, theo [mesa-patches/README.txt](https://github.com/Almosst-DEV/Cobalt64/blob/d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65/mesa-patches/README.txt).
  Chưa build hay apply toàn bộ patchset Mesa trong nghiên cứu này.
- Dump root: `out/890m-root.md`, timestamp `2026-10-13T07:20:53Z`.
- EDID bổ sung: `out/890m-user/card2-eDP-2.edid` (256 bytes), decoded trong
  `out/890m-hybrid-user.md`. `docs/890M-LINUX-DUMP.md` là lần thu thập cũ,
  không thay thế bằng root dump mới.
- Host parser output: `out/890m-atomdump.txt`. Binaries và source tham chiếu nằm
  trong đường dẫn đã gitignore. Chưa thay EFI, load kext hay ghi GPU registers.

## Những gì phần cứng thực sự cho biết

| Mục | Đo được | Hệ quả |
|---|---|---|
| PCI | 1002:150e, rev c1, subsystem 1043:3998 | Match Strix riêng, không giả 7550 |
| GC | 11.5.0, 16 CU | GFX11.5 shader/PM4/MQD; GFX12 binaries không dùng lại trực tiếp |
| Display | DCN 3.5.0 | DCN41 register allowlist/timing/DMUB integration cần backend riêng |
| SDMA | 6.1.0 | Linux dùng sdma_v6_0, không sdma_v7_0 |
| PSP | MP0 14.0.0 | Linux dùng psp_v13_0, khác Navi48 14.0.3 |
| SMU | MP1 14.0.0, 93.11.0, interface 7 | Cần Strix message/table mapping |
| NBIO | 7.11.0 | Doorbell routing/backend khác NBIF 6.3.1 |
| Memory | 512 MiB UMA, GTT budget 15594 MiB | GTT budget không phải kích thước GART window |
| GART | 512 MiB window trong log | Cần page tables/IOMMU/cache policy đúng |
| BAR0 | 256 MiB PCI aperture | Không đồng nhất với visible UMA 512 MiB |
| BAR2/BAR5 | 2 MiB doorbell / 512 KiB MMIO | Địa chỉ từ OS, không hardcode địa chỉ Linux |
| TMR | 0x8010000000, size 0x08900000 | Offset 256 MiB, size 137 MiB, ends at offset 393 MiB |
| VBIOS | VFCT, 21504-byte debugfs image | Không có ROM BAR; cần VFCT transport |
| USB | 65:00.4 D0 depends on 65:00.0 | Tránh power-off GPU function trong bring-up |

TMR trên là allocation của Linux lần boot này, không phải địa chỉ bắt buộc của
macOS. Port phải lấy requirements/ownership từ firmware flow và reserved ranges;
không hardcode Linux allocation như layout cố định của macOS. GOP console,
DMUB windows, firmware reservations, page tables và scratch buffers đều cần
được bảo vệ trước mọi allocator/test write.

### Panel

Hybrid (`gpu_mux_mode=1`), `card2-eDP-2` connected/enabled. EDID SDC model 16796,
`ATNA40CU05-0`, RGB 10 bpc, 2880×1800. Base DTD 60.000699 Hz / 652.270 MHz;
DisplayID type-7 preferred timing 120.000294 Hz / 652.264 MHz. Hai timing có
vertical blank khác nhau; không tạo 60 Hz bằng cách chỉ chia pixel clock của 120 Hz.

Debugfs: 4 lanes, rate code 0x1e (HBR3 / 8.1 Gb/s mỗi lane), DSC clock/slice width
0; sink DSC/FEC flags đều no. PSR capability yes, raw state 6; không diễn giải
raw state thành một trạng thái hoạt động cụ thể ở đây. `output_bpc Maximum:10`
không chứng minh stream hiện chạy 10 bpc. EDID HDR/VRR cũng không chứng minh
macOS có thể dùng các tính năng này.

Script cũ dùng `stat` và `-s` trên sysfs EDID nên báo 0 và bỏ qua nội dung.
Đã sửa bằng đọc byte count và copy trước khi kiểm tra kích thước, bỏ truncation
EDID decode, thêm `GPU_OUT` cho lần chạy user không ghi vào thư mục root-owned.

## Ma trận source: dùng lại gì, thay gì

| Tầng | Bằng chứng source | Quyết định |
|---|---|---|
| IP discovery | Cobalt `amd/amdgpu_discovery.cpp` lấy base/version từ bảng | Dùng lại parser có kiểm tra bounds; dispatch funcs theo IP version, không chỉ thay bases |
| Init orchestration | Cobalt `amd/amdgpu_init.cpp` gọi nbif_v6_3_1 trực tiếp; các hàm linked là GFX12/GMC12/SDMA7/MES12 | Dùng ý tưởng staged bring-up/logging; triển khai Strix funcs và dependencies riêng |
| UMA/GMC | Linux `gmc_v11_0_mc_init`: APU native x86 dùng MMHUB MC FB offset làm aperture base, real_vram_size làm aperture size | Phải phân biệt CPU physical, MC, GPU VA và BAR0; xác minh map trên macOS trước writes |
| PSP | Linux discovery chọn psp_v13_0 cho 14.0.0; init_microcode chọn TOC/TA | Không replay SOS14.0.3 path; xác minh firmware already alive và APU TOC requirements |
| SMU | Linux `smu_v14_0_0_ppt.c` | Port Strix-specific messages/tables/power ordering; không dùng dGPU SMU tables |
| IH/HDP/NBIO | Dump IH/HDP6.1, NBIO7.11; Cobalt ih_v7_0/nbif_v6_3_1 | Port IRQ decode, flush và doorbell routing theo version |
| CP/GFX/IMU/RLC | Linux gfx_v11_0 có case 11.5.0; Cobalt gfx_v12_0/cp_v12_0 | Port register/packet/firmware/MQD path; kernel test shader phải compile GFX11.5 |
| SDMA/MES | Linux sdma_v6_0 và mes_v11_0; Strix mes_2 + mes1 | Dùng đúng firmware và ABI ring/MQD; chỉ bật engine cần cho milestone |
| Display | Cobalt src/dcn41; Linux dcn35_resource | Dùng backend DCN35; eDP AUX/training/panel/backlight cần kiểm chứng riêng |
| AtomBIOS/EDID | RDNA4FB atombios/edid parsers | Atom tables đọc được một phần; thêm eDP connector và DisplayID type-7 |
| N48N ABI | Navi48NativeABI.h, native client, Mesa patches | Dùng patterns BO/VA/fence/validation; version ABI và mở rộng real device info |
| RADV Darwin | Patch0001 find_canned("gfx1201"), fake device 0x7550; patch0002 có addr-config guard | Thay canned identity bằng thông tin Strix thực, audit cả 9 patches; không bypass guard bằng env var |
| Metal bundle | tools/native/navi48metal/Navi48Device.m có limits lấy từ gfx1201 | Dùng lại phần API translation sau Vulkan; query limits/formats/extensions đúng target |
| xlat12 | Chuyển Apple GFX10.3 stream thành GFX12 | Không phải backend GFX11.5; để ngoài MVP |

Source liên quan:

- [Init ladder](https://github.com/Almosst-DEV/Cobalt64/blob/d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65/src/navi48-bringup/src/amd/amdgpu_init.cpp)
- [Firmware table](https://github.com/Almosst-DEV/Cobalt64/blob/d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65/src/navi48-bringup/src/amd/fw_table.cpp)
- [Linux IP selection](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/amdgpu/amdgpu_discovery.c)
- [Linux UMA mapping](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/amdgpu/gmc_v11_0.c)
- [PSP13 / TOC](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/amdgpu/psp_v13_0.c)
- [SMU Strix](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/pm/swsmu/smu14/smu_v14_0_0_ppt.c)
- [NBIO7.11](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/amdgpu/nbio_v7_11.c)
- [VFCT BIOS transport](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/amdgpu/amdgpu_bios.c)
- [DCN35 resource construction](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/drivers/gpu/drm/amd/display/dc/resource/dcn35/dcn35_resource.c)

## Host experiment với VBIOS thật

`make -C ref/RDNA4FB atomdump` build được host executable trên Linux; Makefile
in warning thiếu xcrun ở phần SDK discovery nhưng không chặn host target.
`atomdump out/890m/vbios.bin` exit 1, vì fixture harness yêu cầu IP discovery
trong ROM. Đây không phải lỗi checksum/AtomBIOS: parser báo checksum OK,
config STRIX.bin, firmwareinfo3.4, displayobjectinfo1.5, GPIO LUT và 5 paths.

Path0 objid 0x3114, encoder 0x211e, devtag0x0002 hiện in Unknown; đây là ứng viên
panel cần đối chiếu connector IDs/Atom definitions, chưa coi là mapping đã xác minh.
Các path khác: DP và 3 USB-C. Không suy ra cả 5 ports vật lý đều được nối trên máy.

IP discovery không nằm trong VBIOS sample theo parser. Cần acquisition riêng
qua firmware memory/discovery transport đã xác minh; không biến failure này
thành requirement có ROM BAR. Nhiều legacy display command functions absent;
không dựa vào Atom interpreter legacy để điều khiển panel. EDID parser hiện có
CTA handling nhưng không thấy implementation DisplayID type-7 trong edid.cpp,
trong khi preferred 120 Hz của panel nằm ở block đó.

## So sánh hướng triển khai

| Hướng | Lợi ích | Trở ngại | Chọn |
|---|---|---|---|
| Port Cobalt64 per-IP + RADV | Giữ user-space/Metal architecture, kiểm chứng compute độc lập | Kernel bring-up mới, UMA và real device info | Hướng chính |
| GOP framebuffer adoption | Có thể giữ hình boot, giảm scope display ban đầu | Phải xác minh GOP ở Hybrid trên macOS; bỏ mọi DCN41-specific access | Thử sớm, có điều kiện |
| Full DCN35/eDP trước compute | Native modesetting độc lập acceleration | DMCUB, AUX/training, timing, power/backlight phức tạp | Đường fallback hoặc milestone riêng |
| Apple PM4 → GFX11.5 translation | Có thể tận dụng một phần integration Apple | xlat12 không tương thích target; thêm shader/descriptor/ABI work | Hoãn |
| GPU spoof / NootedRed trực tiếp | Thay config ít | Không có bằng chứng source đã kiểm chứng cho GC11.5/DCN3.5 trong audit này | Không dùng làm kế hoạch port |

Đã clone NootedRed để nhận diện phương án thay thế nhưng chưa audit implementation;
không coi đây là source chứng minh hỗ trợ hoặc nguồn code cho port. Báo cáo chính
chỉ dựa trên Cobalt64, RDNA4FB, Linux và dump phần cứng.

## Milestones và điều kiện qua bước

1. **Offline fixtures:** VFCT extraction có length/checksum/PCI identity validation;
   AtomBIOS paths và EDID 60/120 timings được decode; malformed/truncated inputs
   bị từ chối. Không phụ thuộc IP discovery embedded trong VBIOS.
2. **macOS probe riêng:** match1002:150e, đọc PCI config/BAR census, console geometry,
   VFCT và IP versions nếu transport khả dụng; không tự chạy Cobalt start/init ladder.
   Pass: identities đúng, log acquisition failures rõ, không đổi register/power/link.
   MM_INDEX/MM_DATA access và firmware mailbox queries có writes ở mức transport;
   không gọi chúng là probe không ghi, phải tách thành bước được kiểm soát sau.
3. **GOP adoption feasibility:** Hybrid GOP có console scanout trên iGPU, memory range,
   stride/pixel format đúng. Pass: framebuffer fixed boot mode hoạt động, không
   reset display. Nếu không có GOP usable, triển khai DCN35 sớm hơn.
4. **UMA + firmware foundations:** xác minh CPU/MC/GPUVA translations, ownership
   ranges, cache coherency, PSP TOC/TMR, SMU power sequencing, IRQ và NBIO.
   Pass: allocate/map/unmap/reuse không chạm console/firmware; faults được log.
5. **SDMA:** copy một page có source/destination canaries và fence readback,
   timeout hữu hạn; kiểm tra VRAM và GART riêng. Pass: byte compare đúng, không
   VM faults và USB vẫn hoạt động. Không mặc định toàn bộ MES phải chạy trước test này.
6. **GFX11.5 headless:** shader store known value, rồi triangle vào offscreen BO.
   Pass: results đúng qua nhiều submissions; compiler target, MQD và PM4 đúng IP.
7. **RADV Darwin:** expose real device info (family, GC, CU mask, clocks, tiling,
   heap budgets, VA bounds), handshake ABI; apply patches trên đúng Mesa base.
   Pass: enumeration đúng890M, transfer/compute/offscreen render, fence lifetime,
   BO imports và cleanup không lỗi; chạy giới hạn cases phù hợp Vulkan CTS.
8. **Metal/desktop:** query real Vulkan limits, test Metal compute/triangle/texture
   upload; mới nối compositor/scanout. Các Apple-private hooks phụ thuộc macOS build.
9. **Native eDP:** DCN35 read/capture trước writes, 60Hz SDR fixed mode bằng timing
   chính xác; rồi 120Hz, brightness, display sleep, PSR/VRR/HDR và resume.
   Không thay tất cả tính năng trong một lượt thử.
10. **Power/battery:** khảo sát ACPI _OFF/_PR3/ATPX paths của dGPU trước SSDT;
    không giả định một _OFF call đã đủ. Đo pin và kiểm chứng USB/audio/sleep.

EFI hiện che iGPU ở `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)` bằng class-code,
name/IOName và disable-gpu. Config thử phải mở đúng các properties này và có
đường quay lại config hiện tại; chưa chỉnh EFI trong nghiên cứu này.

## Bước tiếp theo cụ thể

Làm milestone1 trước: host parser VFCT/Atom/EDID trên fixtures hiện có, bổ sung
DisplayID type7 và eDP connector labels. Song song về thiết kế, chốt contract
StrixProbe cho milestone2 (đầu vào/IORegistry output và danh sách reads cho phép).
Chưa cần thêm root dump tổng quát hoặc load Cobalt64 nguyên bản.

Còn thiếu trước hardware bring-up: VFCT byte-for-byte extraction đối chiếu vbios.bin;
raw IP discovery acquisition; firmware filenames/hashes thực tế (modinfo liệt kê
candidates, không chứng minh mọi file được nạp); Linux driver source đúng bản
CachyOS; console/GOP memory trên macOS Hybrid; register schemas cho từng IP;
state DMCUB/GOP lúc macOS boot và nguồn backlight/eDP power sequencing.
