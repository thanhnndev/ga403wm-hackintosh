# ACPI Wi-Fi review (read-only), 2026-10-12

Source: `/Volumes/ESP/SysReport/ACPI/DSDT.aml` and SSDT tables. Disassembled with locally built ACPICA iasl, without evaluating ACPI methods or changing EFI. Full tables remain in ignored build output; no MSDM/licensing table was copied.

* Live IOPCIDevice WLAN@0 has vendor/device 14c3:7925 and acpi-path `IOACPIPlane:/_SB/PCI0@0/GPP5@20003/WLAN@0`, matching the dump's `_SB.PCI0.GPP5.WLAN`.
* DSDT defines GPP5 `_ADR=0x20003`, WLAN `_ADR=0`, MTDS package length 31 and MTGS package length 49. These are the actual static inputs for the core's SAR parser; `itlmt7925_pwr.cpp` already evaluates these names through the PCI acpi-path. MTCL, MTAS and MTSP are also present; their semantics were not established in this review.
* DSDT defines WLAN WRST reset: toggles EC0.WLRY from zero to one with Sleep(0xC8), under EC mutex; `_PRR` refers to WRST.
* SSDT-25 (AMD WLAN) defines bridge PWSR `_PR0` and `_PR3`, P_ON/P_OF using EC/PCI/ALIB helpers; WLAN `_PS0` sleeps 0x05DC (1500 ms), `_PS3` is empty, `_S0W=3`. Its vendor `_DSM` has a WLD3-dependent branch returning 0x18 for function 2, described by firmware logging as Enable D3Cold. This does not prove macOS uses that branch.
* SSDT-19 `_E10` can Notify GPP5 with 0x02 when its PCI wake conditions match.
* Current ESP config has SSDT-Disable_Network_GPP5.aml disabled. Live PCI device and native controller are active; no evidence of ACPI hiding the Wi-Fi PCI device in this run.

ACPI is useful for SAR/power tables and future reset/sleep-wake debugging. It does not by itself establish why Stage B has an unregistered child and no en9: inspect native interface registration first. An additional runtime clue from the prior Stage B diagnostic report is `IO80211InterfaceRole=LowLatency`; whether role 2 is the correct intended interface role remains unverified.

Combined table disassembly failed on duplicate namespace objects; per-table disassembly succeeded. These disassembler conflicts alone are not evidence of a runtime firmware fault. External method linkage was not executed or exhaustively validated.

## Included evidence

All 29 disassembled DSDT/SSDT files are included beside this report. `source.json` records hashes of the original AML inputs and the ACPICA source commit used to build iasl. They were disassembled separately (`iasl -d <table.aml>`). No ACPI method was evaluated. These are firmware static tables, not proof that each optional firmware branch executes on macOS. Raw originals and the remaining SysReport tables are kept locally.
