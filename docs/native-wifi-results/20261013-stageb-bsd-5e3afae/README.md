# Stage B exclusive — BSD attach, 2026-10-13

Native code: `5e3afae`; build/install checkout: `2ac6fc7` (documentation-only update). Installed local build before reboot. Native loaded UUID `202BF5E3-4826-3292-BF53-EFA7A1BEC64C`; core loaded UUID `8A7B2CEB-4199-3B77-B5F7-FDFBE6CE9219`.

## Result

- User rebooted; current boot completed and no new panic was reported. Boot time 08:33:03 local; collection began 08:35:34.
- Both core and native kexts loaded. Controller and Infrastructure interface registered/matched/active.
- `wq == ctl == iface`, provider loop differs. Trace reaches `mk:deferBSDAttach(false)=0`.
- Trace records `lp:inGate=0 onThread=0 wl=1` at the diagnostic sample before publication. This is not the inGate value inside the BSD command gate; do not claim the anticipated sample value of 1 was observed.
- `IOInterfaceUnit=9`, BSD Name/interface name `en9`, no `IODeferBSDAttach` property; active `IOSkywalkNetworkBSDClient` child. Hardware/driver version properties successfully populated.
- `ifconfig -l` contains en9. `ifconfig en9` prints flags without UP/RUNNING, CHANNEL_IO, then `SIOCGIFXMEDIA: Input/output error` and exits 1. Native controller link status/speed remain 0. This establishes BSD publication, not working Wi-Fi or datapath enable.
- `networksetup -listallnetworkservices` shows existing Ethernet services and the phone tethering service, no Wi-Fi service. System Settings UI not inspected. Phone name omitted from repository.
- Sleep/wake, unload, another reboot and manual interface enable were not tested. EFI/NVRAM not changed during collection; Stage B exclusive retained for cloud analysis.

Raw logs stay local at `~/itlmt-backup/logs-20261013-083534/`. Exported interface MAC removed, including the intentional placeholder. Unprivileged dmesg collection failed with Operation not permitted; persistent registry trace is available in full.

Next: cloud review of enable/media handling and native Wi-Fi userland integration; request round 12 if needed.
