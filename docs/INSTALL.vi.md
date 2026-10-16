# Cài macOS 15 lên ASUS ROG Zephyrus G14 (GA403WM)

English: [INSTALL.md](INSTALL.md).

> ⚠️ **Dự án vibe-code, chỉ test trên một máy.** Đọc cảnh báo trong [README.vi.md](../README.vi.md). Hướng dẫn này là đường đi đã
> chạy được trên máy tham chiếu (BIOS GA403WM.310, OLED 2880x1800, RTX 5060). Nó không phải bộ cài hoàn chỉnh. Nếu một bước làm bạn
> bất ngờ, dừng lại và hỏi trong issue; đừng tự ý thử trên ESP.
>
> **Chỉ macOS 15 (Sequoia).** macOS 26 chưa hỗ trợ, chưa test; đừng cài và đừng chấp nhận bản cập nhật lớn.

## 0. Cần chuẩn bị

* Một chiếc GA403WM (biến thể GA403 khác: chưa test). Kext thử nghiệm có thể đụng tới mọi thứ trên ổ bạn cài: **backup trước**.
  Giữ sẵn USB cứu hộ Windows/Linux.
* Một máy thứ hai, tốt nhất là Mac, để tạo bộ cài và build kext. (Cần Mac để build kext và app; nếu không có Mac thì CI build
  kext giúp bạn, còn app thì không.)
* Một USB (16 GB+) cho OpenCore và một USB hoặc ổ (32 GB+) riêng cho bộ cài macOS.
* Cách có mạng khi cài: **USB Ethernet** hoặc **USB tethering Android** (`HoRNDIS.kext` có trong EFI). Wi-Fi của dự án chạy nhưng
  chạy ở tốc độ tối đa của link nhưng chỉ qua driver riêng, chưa tích hợp Wi-Fi native: để tải bộ cài 16 GB, mạng dây / tethering vẫn an toàn hơn.
* Thời gian. Lần boot đầu mất vài phút và bạn sẽ reboot nhiều lần.

### Dual boot

Windows và Linux vẫn giữ được: macOS có phân vùng/ổ **riêng**, mọi thứ khởi động từ picker OpenCore. Đọc
[DUAL-BOOT.md](DUAL-BOOT.md) trước (co phân vùng là bước rủi ro; entry UEFI có thể biến mất sau *Reset NVRAM*). Máy tham chiếu chạy
OpenCore từ ESP trong máy, dùng chung với Windows và Limine.

## 1. Cài đặt BIOS

| Mục | Giá trị | Lý do |
|---|---|---|
| Chế độ GPU (Armoury Crate trong Windows, hoặc BIOS) | **Ultimate** (MUX: chỉ dGPU) | Ở Hybrid, OLED nối với iGPU AMD, macOS không có driver, driver NVIDIA báo `0 displays`. Đặt một lần từ Windows. |
| Above 4G Decoding | **ON** | driver NVIDIA đổi kích thước BAR của GPU |
| CSM | **OFF** | |
| Secure Boot | **OFF** | OpenCore không được ký |
| Fast Boot | OFF | |

BIOS đã test: `GA403WM.310`. Nâng/hạ BIOS là rủi ro của bạn; hãy báo lại kết quả.

## 2. Lấy kext và công cụ

Cần hai nhóm. Để vào thư mục tạm, **chưa** chép lên ESP.

### 2a. Kext của repo này

Chọn một:

* **Release v1** (nên dùng): tải các file `.kext.zip`, `SHA256SUMS.txt` và phần còn lại ở [Releases](https://github.com/thanhnndev/ga403wm-hackintosh/releases);
  cách giải nén, app và daemon CPU ở [SCRIPTS.vi.md §1](SCRIPTS.vi.md#1-dùng-bản-build-sẵn-release-v1). Release còn có OpenCore đã vá và
  `EFI-reference.zip`, nên mục 2c bên dưới đã có sẵn.
* **Artifact CI:** Actions → `build-kexts` → lần chạy mới nhất → artifact `kexts`.
* **Build trên Mac** (Xcode command line tools):
  ```bash
  git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
  bash scripts/build.sh            # build mọi kext vào build/*.kext
  ```

Các kext: `itlmt7925` (Wi-Fi), `ItlXhciKick` (USB, **bắt buộc**), `AsusWmi`, `AmdCppc`, `MtkBtFw`, `BtLeDlFix`, tùy chọn `ItlDiag`.
Từng cái làm gì: [COMPONENTS.md](COMPONENTS.md).

### 2b. Kext bên thứ ba

Tải từ upstream; danh sách kèm phiên bản và hash ở [../efi/KEXTS.md](../efi/KEXTS.md) và [../efi/kexts.json](../efi/kexts.json)
(Lilu, VirtualSMC, AppleALC, VoodooI2C, USBToolBox, HoRNDIS, AMFIPass, BlueToolFixup, ...). Bản mới hơn thường dùng được; hash chỉ
để dựng lại đúng môi trường.

### 2c. OpenCore đã vá

OpenCore 1.0.9 gốc tính sai tần số bus trên Zen 5 (timer chạy sớm ~10 lần). Lấy bản đã vá từ workflow `opencore` (Actions →
`opencore` → chạy thủ công → artifact `opencore-zen5-fsb`) hoặc tự build OpenCore với
[`patches/opencore/fix-zen5-fsb.diff`](../patches/opencore/fix-zen5-fsb.diff). Tải thêm driver của OpenCore 1.0.9
(`HfsPlus.efi`, `OpenRuntime.efi`, `ResetNvramEntry.efi`).

## 3. Ghép EFI

> 📦 **EFI chuẩn** đã test của tác giả sẽ được upload lên release sau (hướng dẫn này sẽ được cập nhật). Trước đó, hãy tự ghép từ bản tham khảo
> đã làm sạch dưới đây.

Bố cục trên USB OpenCore (FAT32/GPT, ESP):

```
EFI/
  BOOT/BOOTx64.efi
  OC/
    OpenCore.efi          <- bản đã vá
    config.plist          <- từ efi/OC/config.plist, sửa như dưới
    ACPI/*.aml            <- từ efi/OC/ACPI/
    Drivers/              <- HfsPlus.efi OpenRuntime.efi ResetNvramEntry.efi
    Kexts/                <- mọi kext trong config.plist > Kernel > Add
```

Sửa `config.plist` (bằng `tools/occonfig.py`, ProperTree hoặc OpenCore Configurator; sau đó chạy `ocvalidate` cùng bản OpenCore):

1. **SMBIOS: tự tạo** `PlatformInfo > Generic`: `SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM` (`macserial`/GenSMBIOS, model
   `MacBookPro16,2`). Repo chỉ có giá trị giữ chỗ `CHANGE_ME_*`. Đừng công khai SMBIOS của bạn.
2. **Số nhân:** bốn patch "Force cpuid_cores_per_package" mang giá trị `0x0c` (12 nhân = HX 370). Giữ nguyên nếu GA403WM của bạn
   dùng CPU đó.
3. **Boot-args** (tham khảo, rút gọn cho dùng hằng ngày):
   ```
   -vi2c-force-polling nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth
   amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 -nvrmnobootscreen nvrmacpibl=1
   itlmt_m1=0 itlmt_m2=1 itlmt_m3=1 itlmt_fast=6
   ```
   Thêm `-v debug=0x100 keepsyms=1` khi cài đặt / bring-up; bỏ sau đó (boot nhanh hơn khi không verbose; bấm Cmd+V trong picker để verbose một lần).
   Ý nghĩa từng tham số: [../efi/README.md](../efi/README.md#boot-args-reference-machine).
4. **USB map:** `Kexts/UTBMap.kext` (trong `EFI-reference.zip` của release) là bản map của tác giả cho laptop này (bốn controller xHCI
   AMD, đã bật trong `config.plist`); `UTBDefault.kext` để tắt. Nó chỉ khớp đúng model này: máy khác thì tự map port bằng công cụ
   USBToolBox. Bàn phím trong máy `0b05:19b6` phải giữ ở dạng port nội bộ.
5. `SSDT-Disable_Network_GPP5.aml` phải để **tắt** (nếu bật, macOS không thấy card Wi-Fi).

**Không** chạy "1401 Build" của NullMoth lên config đã sửa tay: nó ghi đè `config.plist`.

## 4. Wi-Fi: inject mạng

> **Có hai chế độ.** Mặc định (mục này) là chế độ legacy của `itlmt7925.kext`: Wi-Fi hiện là Ethernet và mạng được inject như bên dưới.
> Chế độ native tuỳ chọn (`itlmt7925Native.kext` + boot-args `itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_fast=6`) cho
> giao diện Wi-Fi thật, không cần inject; chạy được nhưng vẫn đang test. Cách bật, kiểm tra và quay lại:
> [WIFI-DRIVERS.md](WIFI-DRIVERS.md#tiếng-việt).

macOS chưa có Wi-Fi gốc cho card này: phải "dặn" `itlmt7925.kext` biết mạng. Cho tới khi
[Wi-Fi gốc](ROADMAP.md) xong, SSID và mật khẩu nằm trong `Info.plist` của kext, **dạng chữ thường**, và driver tự kết nối sau khi
boot (boot-args `itlmt_m2=1 itlmt_m3=1`). Tối đa **4 mạng**, thứ tự = ưu tiên.

**Windows (đọc profile Wi-Fi đã lưu trên PC, PowerShell chạy quyền admin):**

```powershell
.\scripts\inject-creds.ps1 -Kext 'E:\EFI\OC\Kexts\itlmt7925.kext' -Ssid 'WifiNha','Hotspot-dien-thoai'
```

**macOS (PlistBuddy) hoặc editor bất kỳ:** các key `itl_ssid`, `itl_psk`, `itl_ssid2`, `itl_psk2`, ..., `itl_ssid4`, `itl_psk4` nằm trong
personality `itlmt7925` của `itlmt7925.kext/Contents/Info.plist`:

```bash
P=itlmt7925.kext/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :IOKitPersonalities:itlmt7925:itl_ssid 'WifiNha'" \
                        -c "Set :IOKitPersonalities:itlmt7925:itl_psk  'mat khau'" "$P"
```

Quy tắc và giới hạn:

* Chỉ WPA2-PSK (mạng WPA2/WPA3 hỗn hợp chạy qua phía WPA2). Không có mạng mở, WPA3-only, doanh nghiệp, 6 GHz. Hotspot điện thoại đặt
  WPA2, 2,4 hoặc 5 GHz là mạng đầu tiên dễ nhất.
* Đừng commit hay chia sẻ kext đã inject. `*.kext` nằm trong `.gitignore` vì lý do này.
* Wi-Fi hiện trong System Settings → Network là **Ethernet**, không phải Wi-Fi. Đó là bình thường.
* Sau khi cài macOS có thể dùng app **ItlWiFi** trên thanh menu để quét và kết nối thêm mạng
  ([COMPONENTS.md](COMPONENTS.md#itlwifi-itlwifiapp-the-stop-gap-wi-fi-menu)); kết nối đầu tiên vẫn đến từ thông tin đã inject.
* Link chạy ở tốc độ tối đa (xem [WIFI.md](WIFI.md)). Với bộ cài macOS 16 GB vẫn nên dùng bộ cài offline hoặc USB Ethernet / tethering.

## 5. Boot lần đầu và cài macOS

1. Chép EFI lên USB OpenCore, boot từ nó (ASUS: `Esc`/`F8` ở logo → chọn USB, entry UEFI).
2. Trong picker OpenCore chọn bộ cài macOS (hoặc **Recovery**).
3. **Nên dùng bộ cài offline.** Trên một Mac bất kỳ:
   `sudo /Applications/Install\ macOS\ Sequoia.app/Contents/Resources/createinstallmedia --volume /Volumes/INSTALLER`
   (tải bộ cài 15.x từ Mac App Store hoặc `softwareupdate --fetch-full-installer --full-installer-version 15.x`).
   Bộ cài online (Recovery) cũng được nhưng tải ~16 GB: cần Ethernet/tethering.
4. Trong Disk Utility của bộ cài: xóa **ổ/phân vùng đích** sang APFS (GUID). Không đụng ESP dùng chung, phân vùng Windows hay Linux.
5. Cài. Máy sẽ reboot vài lần: mỗi lần chọn mục "macOS Installer", cuối cùng chọn volume macOS mới. Nếu treo ở `-v`, chụp vài
   dòng cuối và mở issue (mẹo: `Cmd+V` trong picker để bật verbose).
6. Hoàn tất Setup Assistant (không bắt buộc Apple ID; iMessage/FaceTime/Continuity chưa test).

## 6. Sau lần boot đầu: đưa OpenCore vào ổ trong (tùy chọn nhưng nên làm)

USB chỉ cần để khởi động bộ cài. Dùng hằng ngày, máy tham chiếu boot OpenCore từ ESP trong máy:

1. Backup ESP hiện tại (`diskutil mount` nó, chép cả thư mục `EFI`).
2. Chép `EFI/OC` và `EFI/BOOT` hoàn chỉnh cạnh `EFI/Microsoft` và `EFI/limine` có sẵn. Không xóa chúng.
3. Thêm entry (hoặc đặt OpenCore làm mặc định) trong menu boot firmware; giữ đường lui (các entry cũ và bản backup). Nếu entry biến
   mất: [DUAL-BOOT.md](DUAL-BOOT.md).
4. Windows và Linux khởi động từ picker OpenCore (bấm `Space` để hiện mục ẩn/phụ). Lưu ý: patch ACPI của OpenCore cũng áp lên Windows.

## 7. Driver NVIDIA (RTX 5060 + OLED)

Không có nó, macOS **không có framebuffer** trên laptop này (đen màn hình sau logo).

* Driver là [driver NVIDIA của NullMoth](https://github.com/nullmoth/nvidia-macos-driver) (bên thứ ba, PolyForm
  Noncommercial: đọc README và license của họ). **Dùng fork của mình cho laptop này:**
  [`thanhnndev/nvidia-macos-driver`](https://github.com/thanhnndev/nvidia-macos-driver), nhánh **`ga403wm`** = upstream `v1.15.0` + driver độ sáng OLED (`NVRMEdpBL`,
  panel chỉ có AUX; không còn gì khác) ([danh sách bản vá](https://github.com/thanhnndev/nvidia-macos-driver/blob/ga403wm/docs/GA403WM-PATCHES.md)).
  Fork chỉ chứa mã nguồn, không có binary, nên cài gồm hai phần:
  1. **Cài bản upstream trước**, *bên trong* macOS 15, bằng `install.sh` của họ / app Mac 1401 (NVRM, NVAccel, plugin
     WindowServer, thay đổi OpenCore và `uninstall.sh` đều từ đó).
  2. **Rồi hai phần của fork** (`NVRMEdpBL.kext` và `NVRMFB` hỏi nó trước) chồng lên:
     ```sh
     # chạy từ một bản clone của repo này (script nằm trong scripts/)
     git clone --depth 1 --branch 610.57.04 https://github.com/NVIDIA/open-gpu-kernel-modules ~/ogkm610   # header
     git clone --branch ga403wm https://github.com/thanhnndev/nvidia-macos-driver.git ~/nvidia-macos-driver-ga403wm
     BRIGHT_DIR=~/efi-audit/brightness bash scripts/macos-build-nullmoth-local.sh ~/nvidia-macos-driver-ga403wm   # cần Xcode CLT
     # root (osascript "with administrator privileges" hoặc sudo), kiểm hash, backup ở /Library/NullMoth/edpbl-patch:
     sudo env BRIGHT_DIR=~/efi-audit/brightness bash scripts/macos-aux-kc-dryrun.sh    # dựng collection thử, không cài gì
     sudo env BRIGHT_DIR=~/efi-audit/brightness UPSTREAM_NVRMFB=<pkgroot>/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB \
          bash scripts/macos-edpbl-install.sh            # reboot để nạp;  --undo trả NVRMFB upstream về
     ```
     Chi tiết, bằng chứng và công tắc tắt boot-arg `nvrmedpbl=0|1|2`: [OLED-BRIGHTNESS-DPCD.md](OLED-BRIGHTNESS-DPCD.md).
* Trạng thái: máy tham chiếu từng chạy upstream **1.14.2** + bản vá VRAM clear và bản vá độ sáng, rồi **1.14.7**, và đã được cài
  **1.15.0 + lớp độ sáng ngày 2026-10-13** (nạp ở lần boot kế tiếp; chưa xác nhận đã boot). Bản vá VRAM clear đã bỏ: desktop giật
  do slot PAT của OpenCore chứ không phải driver ([VRAM-GRANT-STALL.md](VRAM-GRANT-STALL.md); bản sửa PAT nằm trong EFI của repo
  này). Upstream không đổi phần backlight nên bản vá độ sáng vẫn cần. Upstream thuần cũng chạy trên laptop này, nhưng độ sáng
  OLED chỉ được xác nhận khi có bản vá ([NULLMOTH.md](NULLMOTH.md)). EFI đã mang sẵn điều kiện cần của driver
  (`csr-active-config` = `43 0A 00 00`, boot-args, `SecureBootModel = Disabled`); xem
  [../efi/README.md](../efi/README.md#nvidia-dgpu-nullmoth-driver). AMFIPass phải được nạp.
* **Đừng** chép giá trị BAR (`ResizeGpuBars`, `ResizeAppleGpuBars`) hay mục `IONDRVSupport` từ board khác: `EFI-reference.zip` ở
  trạng thái an toàn cho installer, installer của driver tự đổi (README upstream: không thay cấu hình đang chạy bằng giá trị BAR cố
  định của board khác). Từ 1.14.3 nó còn bật `DisableVariableWrite` trên EFI Ryzen có `OpenRuntime.efi`: macOS không còn tự đổi
  được ổ khởi động.
* Lưới an toàn: công cụ 1401/NullMoth thêm mục *"Start once without NVIDIA driver"* vào picker. Dùng khi màn hình vẫn đen.

## 8. App và daemon (trên macOS đã cài)

Không có Xcode: dùng app và daemon build sẵn trong release ([SCRIPTS.vi.md §1](SCRIPTS.vi.md#1-dùng-bản-build-sẵn-release-v1)). Tự build (cần Xcode Command Line Tools):

```bash
xcode-select --install
git clone https://github.com/thanhnndev/ga403wm-hackintosh && cd ga403wm-hackintosh
bash scripts/build-rogcontrol.sh --install     # ROG Control: profile, quạt, giới hạn sạc, đèn
bash scripts/build-itlwifi.sh    --install     # menu Wi-Fi
bash scripts/build-tapguard.sh   --install     # chặn tap touchpad khi gõ (cần quyền Accessibility)
```

Mọi script, quyền root và cách hoàn tác: [SCRIPTS.vi.md](SCRIPTS.vi.md). Cài các kext khác lên ESP bằng `scripts/macos-install-kext.sh <tên>` (tự backup bản cũ và giữ thông tin Wi-Fi đã inject). Daemon
boost CPU (cần quyền administrator):

```bash
bash scripts/build-amdcppc-policy.sh
sudo bash scripts/macos-amdcppc-policy-install.sh        # --undo để gỡ
```

Kiểm tra:

```bash
sysctl debug.asuswmi.status            # profile, giới hạn sạc, MUX ... (AsusWmi)
sysctl debug.amdcppc.freq              # xung của từng CPU (AmdCppc)
ioreg -rc itlmt7925 -d1 | grep wifi-  # trạng thái Wi-Fi, SSID, tín hiệu
ioreg -rc MtkBtFw -l | grep -E '"bt-state"|"bt-log"'    # nạp firmware Bluetooth
/Applications/RogControl.app/Contents/MacOS/RogControl --bench 20   # chạy các profile dưới tải
```

## 8b. Tùy chọn: HiDPI ("looks like 1440 x 900")

OLED chạy 2880x1800 / 120 Hz; một file override màn hình cùng một preference cho desktop 2x ở 1440x900 điểm. Chỉ cỡ này chạy được.
Làm theo [SCRIPTS.vi.md §4](SCRIPTS.vi.md#4-hidpi-looks-like-1440-x-900-từng-bước) (có lưới an toàn và cách hoàn tác); đừng chọn cỡ co giãn khác trong
System Settings.

## 9. Cập nhật, và những điều không nên làm

* **Đừng cập nhật macOS** lên quá bản 15.x đã cài khi chưa xem issue. Tắt cập nhật tự động. **macOS 26 sẽ làm hỏng cấu hình này**;
  không có hỗ trợ.
* Đừng chạy lại "1401 Build" của NullMoth trên ESP; đừng dùng *Reset NVRAM* nếu bạn phụ thuộc vào entry boot của firmware.
* Trước khi sửa ESP: chép `config.plist` thành `config.plist.<tên>`; trước khi thay kext: `macos-install-kext.sh` tự backup, `--undo` để trả lại.

## 10. Khi có sự cố

| Triệu chứng | Thử trước |
|---|---|
| Đen màn hình sau logo | picker → *Start once without NVIDIA driver*; kiểm tra MUX = Ultimate; xem [NULLMOTH.md](NULLMOTH.md) |
| Kernel panic lúc boot | boot với `-v`, chụp màn hình panic, bỏ kext vừa đổi gần nhất khỏi `config.plist` |
| Phím lặp / nhả trễ | thiếu hoặc tắt `ItlXhciKick.kext` ([USB-XHCI-LAG.md](USB-XHCI-LAG.md)) |
| Không có Wi-Fi | đã inject mật khẩu chưa? boot-args `itlmt_m1/m2/m3`? `ioreg -rc itlmt7925 -d1 \| grep wifi-` |
| Touchpad chết | từng chết một lần trên máy tham chiếu (2026-10-10) và hoạt động lại từ 2026-10-12; chưa ghi lại nguyên nhân. Thử xả hết điện (rút sạc, giữ nút nguồn 40 giây) và mở issue ([HANDOFF](HANDOFF.md)) |
| Mất entry Linux/Windows | [DUAL-BOOT.md](DUAL-BOOT.md) |
| Cần log | [DEBUGGING.md](DEBUGGING.md), `scripts/linux-collect-logs.sh`; che serial, MAC, SSID trước khi đăng |

Khi mở issue, dùng mẫu **Hardware report** và đính kèm log đã che thông tin riêng.
