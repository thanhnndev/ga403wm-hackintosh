# Round 14 — RX, station identity and link lifecycle (24H32)

Read-only collection from the recorded KC hash; 55 executable functions, manifest in source.json. Reproduce with `KC=<BootKernelExtensions.kc> build/abi-venv/bin/python tools/dump_native_wifi_rx_root.py abi/native-wifi/24H32/round14`. No KC is committed.

## RX defect

`IOSkywalkPacketBufferPool::allocatePacket(unsigned,Packet**,unsigned)` calls kernel pool allocation then packet `acquireWithPacketHandle`; the generic acquire only stores handle/flags/state. `IOSkywalkPacket::initWithPool` allocates the buffer-pointer table but does not fill it or set the active count. `prepareWithQueue` enumerates kernel buflets, acquires/prepares each buffer, fills that table and writes active count at packet+0x64. Our previous code skipped prepare and dropped a newly allocated packet when count != 1. Missing preparation is a definite code defect; the current live trace does not identify the exact failed substep of its first dropped frame.

Fix: no-sleep allocate, prepare for CPU copy, verify buffer count/size, copy, set data offset/length, initialize Ethernet metadata, enqueue. Plain pool type 1 creates IOSkywalkNetworkPacket. Metadata setters are exported nonvirtual wrappers returning IOReturn. RX enqueue calls packet completion with direction 2 then hands kernel packet chain to networking. Success transfers ownership; failure returns packet to pool. Pool deallocate completes a prepared packet before disposal/free, so it is the only cleanup needed on failure. Completion and kernel finalize do not prove a DHCP response or end-to-end delivery.

## Station identity defect

`IO80211SkywalkInterface::start` creates MAC agent from its ivars+0xe4 seed. Parameterless init does not supply station identity. Overloaded `init(IOService*,ether_addr*)` initializes ivars and copies the provided identity to +0xe4. MacAddressAgent init generates a random local address for zero/multicast input. Infra registration can overwrite supplied RegistrationInfo MAC using the agent getter. The controller getter override cannot seed that field.

Fix: call the verified provider/address init overload before role/id setup and before start. Remove BSD getter/ifnet_set_lladdr patches. The latter failed ENXIO on live hardware because the BSD interface had not attached yet. No direct private-field write, boot-arg MAC override or post-boot shell repair is part of the new build.

## Link lifecycle defect

`IO80211InfraInterface::updateMediumStatus` reads its internal state directly, bypassing virtual linkState. Classic controller setLinkStatus and Skywalk reportLinkStatus do not update that Infra state. `InfraInterface::setLinkState` dispatches to setLinkStateInternal; the Up path updates state, publishes Skywalk link, updates speed/bandwidth and notifies managers/IPv6. It returns a boolean success flag; old generated headers guessed IOReturn/void.

Fix: use the Family setter; remove linkState override and ifmediareq status patch. updateLinkSpeed can send Glue IOUC, so setter must run in W's gate on an external caller, not W's event thread. Core worker link notification snapshots/retains interface and controller under bridge lock, releases that lock, then native runAction enters W on the core worker. Gated action rechecks binding. Stop marks unbound before removing queues; pending snapshots retain lifetimes and skip stopped interface. RX still uses the short locked callback barrier. Bind/unbind ABI is version 2, requiring both rebuilt kexts. No sleep/unload hardware validation is claimed.

## Offloads and legacy

Hardware assists remain zero; software checksum finalization remains in the bounded TX copy. Previous claims that prepare bypassed the hardware-assist getter were too broad: Ethernet prepare calls the virtual getter then stores registration+0x20. It also invokes ifnet_set_offload. The exact reason live ifconfig capability options retain TSO/partial-checksum flags is still unresolved; those flags alone do not prove hardware assists are enabled. The direct BSD offload-clearing patch was removed; the getter now traces and exports its zero value.

Legacy Ethernet is already suppressed by nativeMode; there is no legacy Ethernet IORegistry object. Core radio engine is required by native. Legacy ItlWiFi app was active and implements auto-join: stopped/disabled locally, with launch-agent/state backup outside repo. New core refuses legacy user clients while nativeMode is active, preventing scan/join/disconnect commands competing with IO80211. USB tethering and unrelated kexts are preserved.

Native core link notification is also moved after m3linkUp/session initialization. Publishing before TX readiness could cause an immediately generated DHCP frame to be rejected by ethTx. The legacy branch keeps its previous notification position.
