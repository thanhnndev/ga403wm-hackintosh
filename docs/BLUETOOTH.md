# Bluetooth (MT7925, USB 0489:e11e)

The Bluetooth half of the MT7925 is a USB device (`Wireless_Device`, class ef, interfaces e0/01/01: ACL, SCO, ISO). It is a
standard HCI controller, but only after its RAM code has been downloaded; macOS has no loader for MediaTek parts, so
`bluetoothd` finds no controller (System Information shows a placeholder "BCM_4350C2, Address NULL, State Off").

## Status (2026-10-11, first boot with it)

Works as a controller: `bt-state` = ready after 5.2 s (sections 0-2 downloaded: 74 176 + 332 224 + 41 472 bytes, 0 dropped
interrupt packets), System Information shows `State: On`, `Chipset: THIRD_PARTY_DONGLE`, firmware `v9736 c4881` and a real
address. `bluetoothd` logs `addScanFilterByUUID failed 0x1812` (Apple's LE scan-filter offload, not present on non-Apple
controllers; the same message appears with Intel + BlueToolFixup). Pairing headphones / mouse / keyboard: not tested yet.

## bluetoothd restart loop after a warm reboot (2026-11-08, fixed in MtkBtFw 0.2.0)

A warm reboot keeps the Bluetooth firmware of the previous session. When it had hung (UHW `WDT status` = 1), MtkBtFw 0.1.0
still reported `ready`; `bluetoothd` timed out on HCI Reset, wrote NVRAM `bluetoothExternalDongleFailed` = `01`, and every later
`bluetoothd` of that boot skipped the USB controller, fell back to the MacBookPro16,2 UART transport (`H4BC`,
`/dev/cu.BLTH`), timed out after 15 s and restarted, each time with an `ExcUserFault_bluetoothd` report (ReportCrash 11-13 % CPU
at idle). A cold boot clears the chip, which is why it always fixed it.

MtkBtFw 0.2.0 checks the watchdog status before loading and sends its own HCI Reset after FUNC_CTRL; on failure it runs the
Linux subsystem reset (`btmtk_usb_subsys_reset`, MT7925 CONNV3) and loads the whole firmware again. Installed on the ESP
2026-11-08 18:31, active from the next boot. Full analysis, live recovery tool (`tools/mtkbtctl`) and undo:
[mt7925-macos docs/BLUETOOTH.md](https://github.com/thanhnndev/mt7925-macos/blob/dev/awdl/docs/BLUETOOTH.md) (section
"bluetoothd restart loop after a warm reboot").

## Pieces

| Piece | What it does |
|---|---|
| `kexts/MtkBtFw` | Matches interface 0 of 0489:e11e, opens it, downloads `fw/BT_RAM_CODE_MT7925_1_1_hdr.bin` (embedded) and turns the Bluetooth function on, then closes the interface again. The procedure is Linux `drivers/bluetooth/btmtk.c` (`btmtk_usb_setup`, `btmtk_setup_firmware_79xx`, `btmtk_usb_hci_wmt_sync`): WMT commands as HCI vendor command 0xfc6f on the control endpoint, WMT events polled with a vendor IN request (bRequest 1, wValue 0x30), sections in 250-byte blocks, endpoint reset option 0x74011890 = 0x00010001, WMT FUNC_CTRL 1. Sections the chip reports as already loaded (warm reboot from Windows/Linux) are skipped. |
| `BlueToolFixup.kext` 2.7.2 | From [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM/releases) (needs Lilu). Required on macOS 12+ so `bluetoothd` accepts a non-Apple controller. Not in this repository; copy it from the release zip. |
| NVRAM `7C436110-...:bluetoothExternalDongleFailed` = `00`, `bluetoothInternalControllerInfo` = 14 x `00` | Also listed in NVRAM/Delete so OpenCore writes them every boot (BrcmPatchRAM README: needed for non-Broadcom controllers). |

## Checking it

```
ioreg -rc MtkBtFw -l | grep -E '"bt-state"|"bt-log"'      # loading / ready / error, and every step
system_profiler SPBluetoothDataType | head -12               # a real address and chipset instead of the placeholder
```

The kexts' `IOLog` output does not reach `dmesg` or the unified log on this machine, so `bt-log` is the record. If two
controllers end up with the same address, BrcmPatchRAM documents the boot-arg `-btlfxallowanyaddr`.

## Undo

Set `Kernel/Add/[BundlePath=MtkBtFw.kext]/Enabled` and `.../BlueToolFixup.kext/Enabled` to false (or restore
`EFI/OC/config.plist.bt-<time>` on the ESP).
