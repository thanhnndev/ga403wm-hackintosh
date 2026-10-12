# Bluetooth (MT7925, USB 0489:e11e)

The Bluetooth half of the MT7925 is a USB device (`Wireless_Device`, class ef, interfaces e0/01/01: ACL, SCO, ISO). It is a
standard HCI controller, but only after its RAM code has been downloaded; macOS has no loader for MediaTek parts, so
`bluetoothd` finds no controller (System Information shows a placeholder "BCM_4350C2, Address NULL, State Off").

## Status (2026-10-11, first boot with it)

Works as a controller: `bt-state` = ready after 5.2 s (sections 0-2 downloaded: 74 176 + 332 224 + 41 472 bytes, 0 dropped
interrupt packets), System Information shows `State: On`, `Chipset: THIRD_PARTY_DONGLE`, firmware `v9736 c4881` and a real
address. `bluetoothd` logs `addScanFilterByUUID failed 0x1812` (Apple's LE scan-filter offload, not present on non-Apple
controllers; the same message appears with Intel + BlueToolFixup). Pairing headphones / mouse / keyboard: not tested yet.

## BLE mouse does not connect (2026-10-12, UGREEN BLE Mouse, public address, HID over GATT)

Headphones (classic, A2DP/HFP) connect. The BLE mouse is not even paired: `bluetoothd` creates the LE link (status 0), reads
the remote version and features (`Remote Features: 21 ...`, remote and local both support the Data Length Extension) and then
stays in `LE_READY_WAIT_FOR_LENGTH` (4 of 4 attempts, `Le topology ... ready-state` in the unified log) until System Settings
gives up after about 30 s. No GATT discovery, no SMP, no pairing prompt.

Reading: after the features, Apple's LE stack sends LE Set Data Length and waits for the HCI *LE Data Length Change* event. The
Core spec only generates that event when the effective lengths change; a mouse that stays at 27 bytes gives none, and Broadcom
and Intel controllers evidently send one anyway, the MT7925 firmware does not. Linux's host stack does not wait for it, so
there is nothing in `btmtk.c` / `btusb.c` to port; the wait is inside `bluetoothd`. Not confirmed with an HCI trace.

How to check:
```
/usr/bin/log show --last 10m --style compact --predicate 'process == "bluetoothd"' | grep -E "Le topology|Remote Features"
```
(`zsh` has a `log` builtin: use `/usr/bin/log`.)

### What was done about it: `kexts/BtLeDlFix` (needs a reboot to test)

Disassembly of `/usr/sbin/bluetoothd` (x86_64 slice, 15.8.1 / 24H32; `lipo -thin x86_64`, `xcrun llvm-objdump -d`) shows the
LE connection setup computing a flag "both sides support Extended Data Length" at `0x1001e4f69`:

```
callq  <chipset id>          ; 0x1001e4f64
cmpl   $0x8, %eax            ; 0x1001e4f69   chipset 8 has a vendor quirk
movzbl %r14b, %r14d
movl   $0, %eax
cmovel %eax, %r14d           ; chipset == 8 -> flag 0 -> LENGTH step skipped
```

With the flag set, the state machine sends no command and waits for the Data Length Change event. `BtLeDlFix` is a Lilu
plugin (same `cs_validate_page` hook as `BlueToolFixup`) that rewrites `83 f8 08` to `39 c0 90` (`cmp eax,eax; nop`) in the
page of `bluetoothd` being validated, so the quirk applies to every controller. The 16-byte pattern
`83 f8 08 45 0f b6 f6 b8 00 00 00 00 44 0f 44 f0` occurs once in the binary. After an OS update the pattern may no longer
match: nothing breaks, the mouse simply fails again; look for `btledl` lines in `log show --predicate 'process == "kernel"'`
(`patched LE data length wait in /usr/sbin/bluetoothd` on success; `-btledlfxdbg` adds debug output) and re-derive the bytes.

Build: `scripts/build.sh BtLeDlFix` (clones acidanthera/Lilu into `build/Lilu` for the headers and `plugin_start.cpp`).
Boot-arg `-btledlfxoff` disables it. Untested on hardware at the time of writing.

If the mouse still stays in `LE_READY_WAIT_FOR_*`, the next step is an HCI trace (PacketLogger from Additional Tools for Xcode,
needs root) to see which command or event bluetoothd is waiting for.

Side note: this boot `bt-state` was `error` (`wmt op 1 flag 0: no event`: a warm reboot with the firmware already running),
yet the controller works; `MtkBtFw` should treat "no answer to the first PATCH_DWNLD query" differently from a real failure.

## Pieces

| Piece | What it does |
|---|---|
| `kexts/MtkBtFw` | Matches interface 0 of 0489:e11e, opens it, downloads `fw/BT_RAM_CODE_MT7925_1_1_hdr.bin` (embedded) and turns the Bluetooth function on, then closes the interface again. The procedure is Linux `drivers/bluetooth/btmtk.c` (`btmtk_usb_setup`, `btmtk_setup_firmware_79xx`, `btmtk_usb_hci_wmt_sync`): WMT commands as HCI vendor command 0xfc6f on the control endpoint, WMT events polled with a vendor IN request (bRequest 1, wValue 0x30), sections in 250-byte blocks, endpoint reset option 0x74011890 = 0x00010001, WMT FUNC_CTRL 1. Sections the chip reports as already loaded (warm reboot from Windows/Linux) are skipped. |
| `BlueToolFixup.kext` 2.7.2 | From [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) (needs Lilu). Required on macOS 12+ so `bluetoothd` accepts a non-Apple controller. Not in this repository; copy it from the release zip. |
| `kexts/BtLeDlFix` | Lilu plugin, binary patch of `bluetoothd` so a BLE link does not wait for an HCI LE Data Length Change event the MT7925 never sends (see above). Install: `EFI/OC/Kexts/BtLeDlFix.kext` + a `Kernel/Add` entry after Lilu. |
| NVRAM `7C436110-...:bluetoothExternalDongleFailed` = `00`, `bluetoothInternalControllerInfo` = 14 x `00` | Also listed in NVRAM/Delete so OpenCore writes them every boot (BrcmPatchRAM README: needed for non-Broadcom controllers). |

## Checking it

```
ioreg -rc MtkBtFw -l | grep -E '"bt-state"|"bt-log"'      # loading / ready / error, and every step
system_profiler SPBluetoothDataType | head -12               # a real address and chipset instead of the placeholder
```

The kexts' `IOLog` output does not reach `dmesg` or the unified log on this machine, so `bt-log` is the record. If two
controllers end up with the same address, BrcmPatchRAM documents the boot-arg `-btlfxallowanyaddr`.

## Undo

Set `Kernel/Add/[BundlePath=BtLeDlFix.kext]/Enabled` to false to undo only the BLE patch. Set `Kernel/Add/[BundlePath=MtkBtFw.kext]/Enabled` and `.../BlueToolFixup.kext/Enabled` to false (or restore
`EFI/OC/config.plist.bt-<time>` on the ESP).
