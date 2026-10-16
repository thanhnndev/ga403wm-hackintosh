# Which Wi-Fi mode to use: legacy `itlmt7925` or native (`itlmt7925` + `itlmt7925Native`)

Tiếng Việt: [bên dưới](#tiếng-việt).

There is **one core driver** and **one optional front end**. They are not two unrelated drivers:

* `itlmt7925.kext` (the **core**) drives the MT7925: firmware, DMA, 802.11 handshake, Block Ack, data path. It always has to be loaded.
* `itlmt7925Native.kext` (the **native front end**) sits on top of the core and presents the radio to macOS as a real
  `IO80211Controller` / Wi-Fi interface. It is idle unless the boot-arg `itlmt_native=1` is set.

So there are two **modes**, chosen by boot-args only (no kext has to be removed to switch):

| | **Legacy mode** (default, no `itlmt_native*` boot-arg) | **Native mode** (`itlmt_native=1 ...`) |
|---|---|---|
| macOS sees it as | **Ethernet** (`en*`): no Wi-Fi menu, no Wi-Fi pane in System Settings | a **Wi-Fi** interface: Wi-Fi menu and System Settings → Wi-Fi list, scan and join |
| Network name / password | injected into the core's `Info.plist` ([INSTALL.md §4](INSTALL.md#4-wi-fi-inject-your-network)) or set from the ItlWiFi app | **none in the kext**: join from the Wi-Fi menu / System Settings (WPA2-PSK) |
| Speed (reference unit, 2026-10-14) | HE / 160 MHz, same data path | **28-36 MB/s** one TCP stream, `networkQuality` 293 Mb/s down, 45 Mb/s up ([numbers](TEST-NATIVE-WIFI.md#round-26d-result-2026-10-14-a-msdu-off--33-41-mbs)) |
| Status | ✅ stable, the long-tested path | 🔧 **works, still being tested**: not verified across sleep/wake, a long uptime or a chip recovery |
| Not available in either | WPA3 / SAE, open networks, enterprise, 6 GHz, **AirDrop / AWDL** ([ROADMAP-AWDL.md](ROADMAP-AWDL.md)) | same |

The shipped reference EFI (`efi/OC/config.plist`) is in **legacy mode**. Native mode is opt-in.

## Native mode: what to set

Both kexts in `EFI/OC/Kexts` and enabled in `Kernel -> Add`: `itlmt7925.kext` first, then `itlmt7925Native.kext` (both come from
the release `kext-v1.1` or from `scripts/build.sh itlmt7925 itlmt7925Native`). The core's `itlmt7925_m1.cpp` stays the owner of the
hardware; the native kext only attaches to it.

Boot-args (add with `tools/occonfig.py`, see below):

| boot-arg | Meaning |
|---|---|
| `itlmt_native=1` | start the `IO80211Controller` front end |
| `itlmt_native_if=1` | publish the Wi-Fi interface (macOS then shows a Wi-Fi port) |
| `itlmt_native_dp=1` | connect the interface to the core's data path (without it there is an interface but no traffic) |
| `itlmt_fast=6` | highest data-path level: Block Ack, HE, 160 MHz. A-MSDU stays **off** at every level (below) |
| `itlmt_nopwr=1` *(optional)* | do not send the regulatory power tables at join (they changed nothing in the A/B matrix) |
| `itlmt_stat=1` *(optional)* | publish `stat-log` / `rx-log` / `ts-log` in the registry for diagnosis |
| `itlmt_native_nvtrace=1` *(optional)* | keep the start trace in NVRAM; leave it off for daily use |

Do **not** also set `itlmt_m1/m2/m3`: those are the legacy mode's in-kext join. Do **not** set `itlmt_amsdu=1` (see below).

```bash
C=/Volumes/ESP/EFI/OC/config.plist          # mount the ESP first
python3 tools/occonfig.py -c $C args add --tag pre-native -- itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_fast=6
python3 tools/occonfig.py -c $C check       # ocvalidate; a config.plist.pre-native backup was written next to config.plist
```

Reboot, then join your network from the Wi-Fi menu. The interface name is stable (the unit is keyed by the MAC in
`/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist`); if you tried several earlier builds, stale `en*` entries can
linger: remove the old Wi-Fi service in System Settings → Network and re-add it.

### A-MSDU is off, on purpose

A-MSDU packs several Ethernet frames into one 802.11 frame. With A-MSDU accepted in the Block Ack agreement, the driver's receive
path collapsed to ~50 KB/s on the reference unit (every frame arrives, hardware splits it, yet TCP stalls); with it off the same
link does 33-41 MB/s. The cause is **not known (chưa xác định)**, so the default is off and `itlmt_amsdu=1` is only for debugging.
Details: [TEST-NATIVE-WIFI.md](TEST-NATIVE-WIFI.md) (round 26).

### Known limits of the native mode

* Join: WPA2-PSK only; the PMK comes from macOS, the core runs the 4-way handshake.
* 1400-byte pings to some WAN hosts lose ~70 % while TCP is fast: cause **chưa xác định**, not a throughput problem.
* Upload (45 Mb/s) is far below download: the TX path is less tuned (rate control is the firmware's); not yet investigated.
* After a lost link the core resets the chip and rejoins; the one-time firmware setup is redone since round 26c, but this
  has **not** been exercised on hardware yet.
* No AirDrop / AWDL / Handoff: that is the next workstream, [ROADMAP-AWDL.md](ROADMAP-AWDL.md).

## How to know which mode is active

```bash
sysctl -n kern.bootargs | tr ' ' '\n' | grep itlmt   # boot-args really in effect
kextstat | grep -E "itlmt"                           # com.itlmt7925.kext always; com.itlmt7925.native only if loaded
ioreg -rc itlmt7925 -d1 | grep wifi-                 # core: wifi-state = "connected", wifi-rate, ...
ioreg -rc itlmt7925Wifi -d1 | head                   # exists only in native mode
networksetup -listallhardwareports | grep -A1 Wi-Fi # native: a Wi-Fi port; legacy: only an Ethernet port
```

## Going back to legacy mode

```bash
C=/Volumes/ESP/EFI/OC/config.plist
python3 tools/occonfig.py -c $C args del --tag pre-legacy -- itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1
python3 tools/occonfig.py -c $C args add --tag pre-legacy2 -- itlmt_m2=1 itlmt_m3=1 itlmt_fast=6
python3 tools/occonfig.py -c $C check
```

Delete any other `itlmt_native_*` argument the same way, keep `itlmt_m1=0`, reboot. The native kext may stay installed: it is idle
without `itlmt_native=1`. If the machine does not come back, copy the `config.plist.<tag>` backup over `config.plist` from Windows,
Linux or the recovery shell. Never run NullMoth's "1401 Build" on a config you edited: it overwrites `config.plist`.
Always have a wired or tethered way online before trying native mode.

## Source and design

Core `kexts/itlmt7925/`, front end `kexts/itlmt7925Native/`; both are built by `scripts/build.sh` and published by the `kext-v*`
release workflow. Clean-room (no `itlwm` / `AirportItlwm` / OWL code): the Apple-side contracts were derived from the macOS 24H32
binaries, read-only. Design and research: [NATIVE-WIFI.md](NATIVE-WIFI.md), [WIFI-AS-WIFI.md](WIFI-AS-WIFI.md),
[IO80211-ABI.md](IO80211-ABI.md); test log: [TEST-NATIVE-WIFI.md](TEST-NATIVE-WIFI.md).

---

## Tiếng Việt

Có **một driver lõi** và **một lớp trước tuỳ chọn**:

* `itlmt7925.kext` (**lõi**) điều khiển MT7925: firmware, DMA, bắt tay 802.11, Block Ack, đường dữ liệu. Luôn phải nạp.
* `itlmt7925Native.kext` (**lớp native**) nằm trên lõi, đưa card lên macOS dưới dạng `IO80211Controller` / giao diện Wi-Fi thật.
  Nó đứng yên nếu không có boot-arg `itlmt_native=1`.

Hai **chế độ**, chọn chỉ bằng boot-args (không phải gỡ kext):

| | **Legacy** (mặc định, không có `itlmt_native*`) | **Native** (`itlmt_native=1 ...`) |
|---|---|---|
| macOS thấy là | **Ethernet** (`en*`): không có menu Wi-Fi | giao diện **Wi-Fi**: menu Wi-Fi, mục Wi-Fi trong System Settings, quét và kết nối |
| Tên mạng / mật khẩu | inject vào `Info.plist` của lõi hoặc đặt từ app ItlWiFi | **không để trong kext**: kết nối từ menu Wi-Fi (WPA2-PSK) |
| Tốc độ (máy tham chiếu 2026-10-14) | HE / 160 MHz | **28-36 MB/s** một luồng TCP; `networkQuality` 293 Mb/s xuống, 45 Mb/s lên |
| Trạng thái | ✅ ổn định, đã dùng lâu | 🔧 **chạy được, đang test**: chưa kiểm chứng qua sleep/wake, uptime dài, hay chip recovery |
| Chưa có ở cả hai | WPA3, mạng mở, enterprise, 6 GHz, **AirDrop / AWDL** | như vậy |

EFI tham chiếu trong release dùng **legacy**. Native là tuỳ chọn bật thêm.

### Bật native

Cả hai kext trong `EFI/OC/Kexts` và bật trong `Kernel -> Add` (`itlmt7925.kext` trước). Boot-args:
`itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1 itlmt_fast=6` (bảng ý nghĩa ở phần tiếng Anh). Không thêm `itlmt_m1/m2/m3`,
không thêm `itlmt_amsdu=1`. Dùng đúng khối lệnh `occonfig.py` ở trên (tự tạo backup `config.plist.<tag>`), reboot, rồi kết nối mạng từ
menu Wi-Fi.

**A-MSDU tắt có chủ đích:** bật A-MSDU trong Block Ack làm tốc độ nhận tụt còn ~50 KB/s; tắt thì 33-41 MB/s. Nguyên nhân
**chưa xác định**, nên mặc định tắt.

**Giới hạn của native:** chỉ WPA2-PSK; ping 1400 byte ra WAN mất ~70 % trong khi TCP nhanh (chưa xác định); upload (45 Mb/s) thấp hơn
nhiều so với download; đường chip recovery sau khi mất link chưa được thử trên máy; chưa có AirDrop / AWDL (xem
[ROADMAP-AWDL.md](ROADMAP-AWDL.md)).

### Quay lại legacy

Dùng khối lệnh "Going back to legacy mode": bỏ `itlmt_native=1 itlmt_native_if=1 itlmt_native_dp=1`, thêm `itlmt_m2=1 itlmt_m3=1
itlmt_fast=6`, giữ `itlmt_m1=0`, reboot. Kext native để nguyên cũng được (không có `itlmt_native=1` nó đứng yên). Luôn chuẩn bị sẵn
đường lên mạng khác (USB LAN / tethering) trước khi thử native. Nếu máy không lên: chép `config.plist.<tag>` đè lên `config.plist`
từ Windows, Linux hoặc recovery. Đừng chạy "1401 Build" của NullMoth trên config đã sửa tay.
