# Datapath boot c2e21ce — 2026-10-13

Boot at 09:23:47, macOS 24H32. No panic reported. Native BSD attach succeeds; en9 exists and media query no longer returns EIO. Legacy Ethernet creation is disabled.

Core joins successfully (`RESULT rc=0 link up`). Efuse tag 2 and CLC processing succeed. Radio-link property is Yes and controller link status is 3, speed 54 Mbps.

Explicit `ifconfig en9 up` succeeds: UP/RUNNING and datapath enabled. A real SystemConfiguration IEEE80211 service named Wi-Fi Native was created after privately backing up preferences; USB tethering remains available. IPConfiguration still reports Active FALSE, DHCP INACTIVE, unpublished. Native TX/RX/completion counters remain zero, so packet delivery is not verified.

Observed inconsistencies: BSD media remains inactive despite core link up; the interface station address changes during enable. Follow-up fixes provide stable controller hardware address, reject unsupported address changes, return real radio link state, advertise zero hardware assists, and finalize ordinary IP checksums in a bounded private TX copy. These fixes are not hardware-tested. Media traces are deduplicated to preserve checkpoint capacity.

Raw logs and preferences stay outside the repository under ~/itlmt-backup. Extracts omit addresses, credentials, and machine identity. Do not interpret old stored panic chunks as a panic from this boot.
