# GA403WM keyboard bindings

This worktree adds an ATKD event feed and RogControl actions for the GA403WM top row and M1–M4 keys. The checked-in mapping is a working hypothesis from the key legends, the GA403WM DSDT event list, and Linux's generic ASUS WMI keymap. It has **not** been verified against a live run of this worktree's kext: the installed kext did not expose the new event feed during the owner's key press session.

| Key | Expected event | macOS action in this branch | Evidence |
|---|---:|---|---|
| Fn+F1 | `0x32` | Toggle speaker mute | Generic ASUS WMI keymap |
| Fn+F2 | `0xC5` | Decrease keyboard backlight | Existing GA403WM handling |
| Fn+F3 | `0xC4` | Increase keyboard backlight | Existing GA403WM handling |
| Fn+F4 | `0xB3` | Toggle Slash lighting | Existing GA403WM handling |
| Fn+F5 | `0xAE` | Cycle performance profile | Existing GA403WM handling |
| Fn+F6 | `0x2A` | Interactive screenshot (`screencapture -i`) | Generic ASUS WMI keymap |
| Fn+F7 / Fn+F8 | ACPI brightness notifications | Decrease / increase OLED brightness through BrightnessKeys | Existing ACPI path; no ATKD code expected |
| Fn+F9 | `0x2D` | Open Displays settings | Generic ASUS WMI keymap; action is a settings shortcut |
| Fn+F10 | `0x6B` | Open Trackpad settings | Event appears in this machine's DSDT; action is a settings shortcut |
| Fn+F11 | `0x0A` | Request system sleep | Event appears in this machine's DSDT; key legend mapping is inferred |
| Fn+F12 | `0x1A`, `0x5D`–`0x5F`, or `0x88` | Open Wi-Fi settings | Candidates from DSDT and generic ASUS WMI map; action is a settings shortcut |
| M1 | `0x31` | Decrease output volume | Generic ASUS WMI keymap; inferred from key legend |
| M2 | `0x30` | Increase output volume | Generic ASUS WMI keymap; inferred from key legend |
| M3 | `0x7C` | Toggle microphone mute (input mute or gain fallback) | Generic ASUS WMI keymap; inferred from key legend |
| M4 | `0x38` | Open RogControl | Generic ASUS WMI keymap identifies Armoury Crate |
| Fn+Esc | `0x4E` | Toggle macOS function-row preference | Candidate code; not present in the generic map |

The hotkey diagnostic is `sysctl debug.asuswmi.hotkey` and returns `sequence code`. To verify the table, build and load this worktree's `AsusWmi.kext`, start RogControl, then check the sequence and event code after each key. Fn+F7/F8 continue through the existing ACPI brightness path. F9, F10 and F12 open the relevant settings pane because this project has no direct display-project, trackpad-enable, or airplane-mode control yet.

Reference for generic ASUS event meanings: [Linux `asus-nb-wmi.c` keymap](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-nb-wmi.c#L2689-L2844). GA403WM-specific DSDT observations are in [ASUSCTL-MACOS.md](ASUSCTL-MACOS.md).
