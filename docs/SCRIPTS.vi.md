# Script và công cụ: chạy gì, ở đâu, hoàn tác thế nào

English (đầy đủ hơn, có bảng chi tiết từng script): [SCRIPTS.md](SCRIPTS.md).

> ⚠️ Dự án vibe-code, chỉ test trên một máy (xem [README.vi.md](../README.vi.md)). Nhiều script đã sửa file bằng quyền **root** trên
> máy của tác giả. Đọc script trước khi chạy; hầu hết đều in lệnh hoàn tác. Script đánh dấu **riêng-máy-tác-giả** có đường dẫn hoặc
> ID thiết bị của máy tham chiếu viết cứng, trên máy bạn sẽ không chạy hoặc làm sai.

Ký hiệu: 🍎 macOS · 🐧 Linux · 🪟 Windows · 🖥 bất kỳ. "Root" = cần `sudo`.

## 1. Dùng bản build sẵn (release v1)

[Release](https://github.com/thanhnndev/ga403wm-hackintosh/releases) chứa kext, app và daemon CPU đã build sẵn (x86_64; app và daemon ký ad-hoc, kext không ký: OpenCore nạp kext nên không cần chữ ký), không cần
Xcode cho phần này. **Vẫn cần clone repo** để dùng các script cài.

```bash
git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
(cd ~/Downloads && shasum -a 256 -c SHA256SUMS.txt)      # file chưa tải sẽ báo thiếu, bỏ qua được
mkdir -p build && for z in ~/Downloads/*.kext.zip; do ditto -x -k "$z" build/; done
ditto -x -k ~/Downloads/AmdCppcPolicy.zip build/ && chmod +x build/AmdCppcPolicy
for a in RogControl ItlWiFi TapGuard; do
  ditto -x -k ~/Downloads/$a.app.zip /Applications/
  xattr -dr com.apple.quarantine /Applications/$a.app    # ký ad-hoc, chưa notarize: không gỡ quarantine thì Gatekeeper chặn
done
```

Sau đó dùng đúng các script như khi tự build: `scripts/macos-install-kext.sh <tên>` cho kext, `scripts/macos-amdcppc-policy-install.sh`
cho daemon. **Inject Wi-Fi vào `itlmt7925.kext` trước khi cài** ([INSTALL.vi.md §4](INSTALL.vi.md#4-wi-fi-inject-mạng)).
RogControl và ItlWiFi có mục "Open at login" trong cài đặt; TapGuard chỉ có login item khi build từ nguồn bằng `scripts/build-tapguard.sh --install`.

## 2. Build và cài

| Script | Nơi | Root | Làm gì | Hoàn tác |
|---|---|---|---|---|
| `scripts/build.sh [kext...]` | 🍎 | không | build 7 kext vào `build/*.kext` (cần Xcode CLT) | xóa `build/` |
| `scripts/macos-install-kext.sh <tên>` | 🍎 | sudo | chép `build/<tên>.kext` vào ESP đang boot, bản cũ vào `EFI/OC/Kexts-backup/`; giữ thông tin Wi-Fi của `itlmt7925`. Kext phải có sẵn trong `config.plist` | `--undo <tên>` |
| `scripts/build-rogcontrol.sh [--install]` | 🍎 | không | build `RogControl.app`; `--install` chép vào `/Applications` và chạy khi đăng nhập | xóa app + LaunchAgent |
| `scripts/build-itlwifi.sh [--install]`, `scripts/build-tapguard.sh [--install]` | 🍎 | không | tương tự cho ItlWiFi, TapGuard | tương tự |
| `scripts/build-amdcppc-policy.sh` | 🍎 | không | build daemon `AmdCppcPolicy` | |
| `scripts/macos-amdcppc-policy-install.sh [--undo]` | 🍎 | **root** | cài daemon vào `/Library/PrivilegedHelperTools` + LaunchDaemon | `--undo` (CPPC vẫn bật đến khi reboot) |
| `scripts/test-rogcontrol.sh` | 🍎 | không | test giải mã đường cong quạt, không ghi phần cứng | |

## 3. Thông tin Wi-Fi

| Cách | Nơi | Ghi chú |
|---|---|---|
| `scripts/inject-creds.ps1 -Kext <đường dẫn> [-Ssid a,b]` | 🪟 PowerShell admin | đọc profile Wi-Fi đã lưu trên PC, điền `itl_ssid*/itl_psk*` (tối đa 4 mạng). Mật khẩu nằm **chữ thường** trong kext |
| PlistBuddy | 🍎 | xem [INSTALL.vi.md](INSTALL.vi.md#4-wi-fi-inject-mạng) |
| `ItlWiFi.app` | 🍎 | quét/kết nối sau khi boot; kết nối đầu tiên vẫn cần thông tin đã inject |

Muốn xóa mật khẩu: cài lại kext sạch từ release/CI (key để trống).

## 4. HiDPI ("looks like 1440 x 900"), từng bước

**Kết quả.** HiDPI **2x thật, giống scale 200 % trên Windows**: OLED 2880x1800 giữ nguyên raster gốc 120 Hz, macOS vẽ desktop 1440x900 điểm với mỗi
điểm nhân đôi ("looks like 1440 x 900"). Hỗ trợ tỉ lệ 2x. Tỉ lệ lẻ (1680x1050, 1280x800, ...) không được hỗ trợ: driver NullMoth không làm được mode co giãn.
Chạy được từ System Settings → Displays sau các bước dưới (chủ máy xác nhận 2026-10-11/12, NullMoth 1.13/1.14). Chưa kiểm chứng trên máy khác.

**Vì sao cần mẹo.** macOS dựng mode HiDPI từ mode gốc, nhưng framebuffer NVIDIA (NVRMFB) không đánh dấu mode của nó "valid for HiRes", nên
WindowServer từ chối bản mật độ-2 của mode gốc (`Mode 65792 not available`). File override thêm một mode co giãn có cờ HiRes và **cùng kích
thước với raster** (`2880 1800 1 0x800000`) nên không cần NVKMS đổi mode co giãn. Mọi mode *thật sự* co giãn (1680x1050, 1280x800, và
"1440 x 900" loại độ-phân-giải-thấp do GPU phóng to) làm lệnh đổi mode thất bại và màn hình **đen**.

### Trước khi làm

* Driver NullMoth đã chạy, desktop ở 2880x1800 @ 120 Hz. Giữ **2880 x 1800** trong System Settings cho đến cuối.
* Script chỉ chạy với panel tham chiếu, vendor/product `4c83:419c`. Kiểm tra máy bạn:
  ```bash
  ioreg -l -w0 | grep -E '"DisplayVendorID" = |"DisplayProductID" = ' | sort -u
  # panel tham chiếu: DisplayVendorID = 19587 (0x4c83), DisplayProductID = 16796 (0x419c)
  ```
  ID khác: script dừng. Có thể sửa `VID=`, `PID=` (và đoạn `case`) tự chịu rủi ro; entry giả định mode gốc 2880x1800.
* Biết đường lui (mục hoàn tác) và có cách vào máy khác (SSH hoặc Recovery).

### Cài

```bash
cd ga403wm-hackintosh
# 1. cho WindowServer dựng mode HiDPI (giống one-key-hidpi; không có kext HiDPI nào)
sudo defaults write /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled -bool true
# 2. cài override cho panel trong máy (không đổi EDID, không xóa prefs)
bash scripts/macos-install-hidpi.sh
# 3. reboot
sudo shutdown -r now
```

### Chuyển mode (có lưới an toàn)

```bash
swiftc -O tools/hidpi-try.swift -o /tmp/hidpi-try
/tmp/hidpi-try list              # liệt kê mode, dòng HiDPI được đánh dấu; list --all hiện cả mode ẩn và cờ
/tmp/hidpi-try 1440              # chuyển sang "looks like 1440 x 900"; bấm Return trong 15 giây để giữ
/tmp/hidpi-try 1440 --keep       # như trên, và lưu vĩnh viễn sau khi xác nhận
```

* Không bấm Return trong 15 giây (màn hình đen, không gõ được) thì công cụ tự đổi về mode cũ. Nó chỉ nhận mode có kích thước điểm ảnh
  đúng 2880x1800 nên không bao giờ kích hoạt mode co giãn.
* `list` in trước dòng `current: ... looks like 1440x900  pixels 2880x1800  120 Hz  flags 0x00800003  HiDPI` (mode đang dùng); trong bảng,
  cùng mode đó hiện là `id 0x80001001 ... pixels 2880x1800 ... flags 0x00800003` (kiểm tra trên máy tham chiếu 2026-10-12, sau khi reboot;
  `system_profiler` báo `UI Looks like: 1440 x 900 @ 120.00Hz`). Dòng HiDPI là dòng có cờ `0x00800000`. Nếu chỉ báo `no HiDPI mode is offered` thì thiếu pref
  (bước 1) hoặc override (bước 2), hoặc chưa reboot.
* Sau khi xác nhận (`--keep` hoặc đã thấy chạy tốt), **System Settings → Displays → "1440 x 900"** cũng dùng được trên máy tham chiếu và
  tần số quét vẫn 120 Hz. Đừng chọn 1680x1050 hay 1280x800, và đừng chọn "1440 x 900" loại độ-phân-giải-thấp (mode id `0x80001000` trong
  `list --all`; mode đúng là HiDPI với 2880x1800 điểm ảnh).
* Kiểm tra: `system_profiler SPDisplaysDataType | grep -i -E 'resolution|looks like'`.

### Hoàn tác

```bash
bash scripts/macos-install-hidpi.sh --undo
sudo defaults delete /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled
sudo shutdown -r now
```

### Nếu màn hình đen

1. Nếu đã dùng `hidpi-try` thì nó tự đổi lại sau 15 giây. Không thì SSH vào (nếu bật) hoặc sang bước 2 rồi hoàn tác; gỡ override chỉ có tác
   dụng sau khi reboot.
2. Boot **macOS Recovery** từ picker OpenCore, mở Terminal, mount volume Data trong Disk Utility rồi:
   ```bash
   ls /Volumes                                  # tìm volume Data, ví dụ "Macintosh HD - Data"
   D="/Volumes/Macintosh HD - Data"
   rm -f "$D/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c"
   ```
   Reboot. Nếu mode đã lưu vẫn sai, xóa thêm pref WindowServer (`$D/Library/Preferences/com.apple.windowserver.plist` và
   `$D/Library/Preferences/ByHost/com.apple.windowserver.*.plist`; macOS tự tạo lại, nhớ backup trước).
3. Cuối cùng: mục picker *"Start once without NVIDIA driver"* (do NullMoth thêm) cho vào desktop không có driver. **Đừng** dùng
   *"1401: Remove NVIDIA driver"*: nó khôi phục `config.plist` trước NullMoth, mất USB map, patch ACPI và boot-args.
4. Từ Linux có `scripts/remove-display-override.sh` (ghi APFS bằng `linux-apfs-rw` thử nghiệm, viết cứng `/dev/nvme0n1p4`: **riêng-máy-tác-giả**), để làm lựa chọn sau cùng.

### Những thứ đã thử và hỏng

| Thử | Kết quả |
|---|---|
| Entry `w h 1 0x200000` | `0x200000` = chỉ *valid for mirroring*: mode chỉ-mirror, CoreGraphics bỏ |
| Định dạng của Apple `w h 9 0xa00000` | vẫn mirror-only; entry 2880x1800 bị coi là trùng mode gốc |
| Chọn bản mật độ-2 của mode gốc | bị từ chối: cờ `0x80000000`, `Mode 65792 not available` (mã 1007) |
| 1680x1050 / 1280x800 / 1440x900 độ-phân-giải-thấp | NVKMS test commit thất bại, **màn hình đen** |
| Thay EDID bằng timing 120 Hz | không cần nữa (driver tự đưa mode 120 Hz từ DisplayID); công cụ đã xóa |

Chi tiết và bằng chứng: [HANDOFF.md](HANDOFF.md) mục 7, [NULLMOTH.md](NULLMOTH.md).

## 5. Bản vá driver NVIDIA (NullMoth)

Các script này vá **chồng lên driver NullMoth upstream 1.14.2**, cần root, dựng lại auxiliary kernel collection, có hiệu lực sau reboot, kiểm
hash và từ chối phiên bản khác. Xem [NULLMOTH.md](NULLMOTH.md). Đừng chạy mù.

| Script | Làm gì | Hoàn tác |
|---|---|---|
| `macos-nvrmfb-vramclear-patch.sh` | **cũ** (bản vá đã bỏ 2026-10-13): NVRMFB xóa VRAM kiểu non-temporal (`movnti`), chỉ 1.14.2 | `--undo` |
| `macos-nvrmfb-vramclear-ab.sh`, `macos-vramtest.sh` | đo MB/s của VRAM clear (script A/B **cũ**, cần build đã bỏ) / thời gian cấp 8 MB | |
| `macos-build-nullmoth-local.sh`, `macos-aux-kc-dryrun.sh` | build NVRMFB + `NVRMEdpBL`, dry run kernel collection. **Riêng-máy-tác-giả** | |
| `macos-edpbl-install.sh` | cài `NVRMEdpBL` (độ sáng OLED qua DPCD AUX). **Riêng-máy-tác-giả** | `--undo`; boot-arg `nvrmedpbl=0` |
| `macos-nullmoth-vramclear.sh` | **lỗi thời**, chỉ cho NullMoth 1.13.0 | `--undo` |
| `macos-ws-upload-install.sh` | thí nghiệm **đã bỏ** (PR #139) | `--undo` |
| `zshrc-nullmoth.sh` | `source` trong `~/.zshrc`: bỏ `MESA_SHADER_CACHE_DIR` của root để Metal giữ shader cache | xóa dòng |

## 6. Công cụ EFI / OpenCore

| Script | Làm gì |
|---|---|
| `scripts/export-efi.py` | xuất `efi/OC` từ EFI đang chạy, thay mọi định danh máy bằng giá trị giữ chỗ; cũng làm rỗng `Misc.Entries` vì đường dẫn thiết bị trong đó chứa EUI-64 NVMe và GUID phân vùng của SSD |
| `scripts/check-efi-privacy.py` | fail nếu `config.plist` còn gì khác ngoài giá trị giữ chỗ, hoặc còn đường dẫn thiết bị chứa EUI-64 NVMe / GUID GPT (chạy trong CI) |
| `tools/occonfig.py` | get/set/add/del/args/check/diff `config.plist` (luôn backup; dùng `--dry` trước) |
| `scripts/build-ocvalidate.sh` | 🐧 build `ocvalidate` đúng commit OpenCore |

## 7. ESP và dual boot

| Script | Làm gì |
|---|---|
| `restore-limine-entry.ps1` 🪟 | tạo lại entry UEFI của Limine/loader Linux bị mất; in lệnh hoàn tác |
| `esp-automount.sh [--install\|--uninstall]` 🍎 | mount ESP trong máy tại `/Volumes/ESP` mỗi lần đăng nhập |
| `esp-cleanup.sh [--apply]` 🐧 | liệt kê rồi **di chuyển** (không xóa) file thừa trên ESP; mặc định chỉ liệt kê |
| `setup-linux-access.sh [--undo]` 🐧 | sửa `/etc/fstab` một lần để đọc ESP và volume macOS không cần sudo |
| `clear-nvram.ps1` 🪟 | xóa các biến NVRAM `itl*` để firmware có chỗ trống |

Xem thêm [DUAL-BOOT.md](DUAL-BOOT.md).

## 8. Chẩn đoán và log

Chỉ đọc, trừ khi ghi chú khác. **Che thông tin riêng trước khi đăng** (MAC, SSID, serial).

| Script | Làm gì |
|---|---|
| `macos-nullmoth-probe.sh [--window]` 🍎 | chụp trạng thái driver NVIDIA và màn hình vào `~/efi-audit/` |
| `macos-ws-system-collect.sh`, `macos-ws-frame-sample.sh`, `macos-ws-cpu.py`, `macos-ws-pat-check.sh` 🍎 | đo WindowServer / PAT ([WINDOWSERVER-RESEARCH.md](WINDOWSERVER-RESEARCH.md)) |
| `linux-collect-logs.sh [--unified]` 🐧 | gom log OpenCore, `ITLLOG.BIN`, NVRAM, panic từ phía Linux vào `~/ga403-logs/` |
| `decode-unified-log.sh` 🐧 | giải mã unified log của macOS không cần macOS |
| `recovery-dump.sh` 🍎 Recovery | ioreg/kextstat/dmesg + trace gõ phím ra USB |
| `usblog.ps1`, `read-nvram.ps1` 🪟 | đọc/chuẩn bị `ITLLOG.BIN`; in boot-args và biến `itl*` ([DEBUGGING.md](DEBUGGING.md)) |

## 9. Script một-lần theo phiên (lịch sử)

`macos-apply-2026-10-11{,b,c,d}.sh` và `linux-apply-2026-10-11.sh` là các đợt sudo của tác giả trong một ngày bring-up. Giữ lại như nhật ký
việc đã đổi và lệnh hoàn tác, **không phải bộ cài**: chúng sửa `config.plist` của ESP tác giả, dùng đường dẫn riêng, giả định NullMoth 1.12-1.13.
Hãy dùng các mục đánh số ở trên.
