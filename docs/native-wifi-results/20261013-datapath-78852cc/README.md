# 78852cc boot — 2026-10-13

No panic reported. Native auto-enables; core joins; en9 is UP/RUNNING and media active. IPConfiguration recognizes WiFi and LinkStatusActive TRUE. DHCP now sends requests but obtains no lease; fallback is IPv4 link-local.

First snapshot: TX sent/completed 48, drop/stall/checksum failures 0, RX received/delivered 0. BSD prepare trace: station=6 (ENXIO), offload=0; ifconfig still advertises TSO and partial checksum options. Address application was attempted before BSD attachment was ready.

Live experiment, no reboot: administrator ifconfig sets en9 to the intended firmware station identity; comparison confirms it matches. DHCP restarted with ipconfig. Later TX sent/completed 77, RX received 1, RX dropped 1, RX delivered 0. Trace reaches RX allocation/enqueue begin. The existing trace does not record the failure return code or failing substep, so allocation, buffer validation, data-length assignment and enqueue are not yet distinguished. A DHCP response is not proven; the one received frame may be unrelated.

Raw collection remains private: ~/itlmt-backup/logs-20261013-102656. Repository extracts omit addresses and credentials. No sleep/wake test; packet delivery is not established. No new kext installed during this check.
