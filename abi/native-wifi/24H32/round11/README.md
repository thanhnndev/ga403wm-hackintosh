# Round 11 — macOS 24H32

Collected on the Mac from source commit `5e3afae`, using `tools/dump_native_wifi_round11.py` and the recorded KC SHA-256 in `source.json`. Read-only collection; EFI, NVRAM and the running kexts were not changed. No reboot or hardware retest.

- Original collector: 154 entries; four exact symbol names missing, preserved in `missing.txt`.
- `missing-candidates.txt` lists matching available names. The requested `IO80211Glue::sendIOUCToWcl` with length 13 is already in the original output; the length-10 spelling is absent.
- Three additional executable functions are in `supplemental-source.json`: Skywalk `isCommandProhibited`, parent `IOSkywalkNetworkInterface::finalizeBSDInterface`, and the Glue send block callback. These are candidates, not proof that the missing class-specific overrides exist. No matching IO80211 `apple80211Request` symbol was found.
- The broad original class match can include data symbols such as `superClass`; do not interpret those files as executable functions.

Next: cloud review of enable/finalize/country-code/ioctl paths before installing the new Stage B exclusive build. Hardware panic risk remains untested.
