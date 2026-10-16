# c78492b boot — 2026-10-13

No panic reported. Both kexts load; native auto-enables, all four TX queues and completion queues enable. Core radio link is up; controller link status 3 and speed 54 Mbps. en9 is UP/RUNNING, but BSD media remains inactive, DHCP reports media inactive, and all TX/RX counters are zero. Station identity and advertised offloads still do not match the intended configuration. Packet delivery is not verified.

Round-11 updateMediumStatus reads private internal state directly rather than calling linkState. Round-12 Ethernet prepareBSDInterface reads registration offload bits directly rather than getHardwareAssists. Follow-up keeps base media handling and overwrites only the shared ifmediareq status field from actual radio state; BSD prepare explicitly applies the station address and clears offloads, with return-code tracing. Interface hardware getter now supplies the same station identity as core. These follow-up changes require hardware verification.

Raw logs: ~/itlmt-backup/logs-20261013-102152 (private; not committed). No sleep/wake test performed because traffic is not yet working.
