# Round 12 — Mac 24H32, 2026-10-13

Collector source `6125831`; KC SHA-256 recorded in source.json. Original collector: 204 entries, zero missing. Supplemental executable functions: 12 (source map in supplemental-source.json), including the IO80211 and BCM supported-media/chosen-media implementations omitted by the original collector. Broad class matching also emits data symbols; these must not be treated as code.

## Media finding and local fix

`IOSkywalkNetworkInterface::ioctl_gifmedia` at 0xffffff80029825d6 invokes getSupportedMediaArray through vptr+0x940. At 0xffffff8002982680..2693 it frees the array and sets errno 5 (EIO) if the getter fails or returns an invalid count.

The inherited `IO80211SkywalkInterface::getSupportedMediaArray` at 0xffffff8002264eb4 reads controller->getMediumDictionary (vptr+0x890), iterates IONetworkMedium objects and writes their types. A NULL dictionary returns 0xe00002f0 at 0xffffff8002264f88. BCM uses the same dictionary approach. Thus an interface override is not required merely to supply supported media.

The native controller has no published dictionary. Local change publishes one zero-speed IEEE80211Auto medium and selects it before interface publication. selectMedium accepts that sole supported type; inherited handleChosenMedia routes to controller selection. Trace records ctl:media auto=1 on success. The dictionary is copied by publishMediumDictionary according to local MacKernelSDK IONetworkController.h, so temporary objects are released. No active link or radio operation is claimed. Static inference that this removes current EIO; hardware verification remains required.

Build succeeds. Link check: 712 undefined, only the six existing reserved IONetworkController symbols missing; no new unresolved symbol. Controller slot check: 21 correct overrides, zero wrong (one more for selectMedium). Not installed on ESP. Running kernel remains the tested 5e3afae build.

## Enable and remaining work

IO80211SkywalkInterface::enable calls a base-class vtable entry then unconditionally returns 0. This alone does not prove successful hardware enable. BCM adds work-loop gate handling, running-state checks and BPF attachment. The native enableDatapath stub still returns Unsupported because no radio datapath exists; it has not been changed to fake success. Virtual-call receiver and table offsets need care before deciding which path invokes the stub.

No manual ifconfig up, unload, sleep/wake, EFI/NVRAM changes or reboot performed. Userland Wi-Fi classification is still unresolved; KC does not include SystemConfiguration dyld code. Existing ACPI dumps cover power/reset/wake but do not explain the medium dictionary failure.

## Local continuation: live discovery and enable instrumentation

`tools/native_wifi_discovery.c` queries SystemConfiguration and IOKit read-only; output from the still-running 5e3afae kernel is in live-discovery-5e3afae.txt. SC enumerates only en0/en1, not en9. The native Skywalk interface and BSD client do not conform to IONetworkInterface. Apple's public configd source, SystemConfiguration.fproj/SCNetworkInterface.c on main, enumerates IOServiceMatching(IONetworkInterface) in __SCNetworkInterfaceCopyAll_IONetworkInterface. This supports a discovery mismatch hypothesis; that public source is not proof of the exact shipped 24H32 implementation. No class-name property hack applied. Source: https://github.com/apple-oss-distributions/configd/blob/main/SystemConfiguration.fproj/SCNetworkInterface.c

Native interface now traces enable/disable entry/results, enableDatapath/disableDatapath calls, media query results and SIOCSIFFLAGS results. Wrappers call inherited Family implementation and preserve return values; no payload logging or fake successful datapath. Build/link passed; interface slots 212 correct, zero wrong. Next hardware step: reboot the media+trace build, collect media query and discovery results, then examine explicit enable.
