# Datapath ownership and local bridge experiment — 24H32

Collected with tools/dump_native_wifi_datapath.py; 125 executable functions, recorded KC SHA-256 in source.json. No KC binary committed.

## Evidence used

- TxSubmission legacyDequeue invokes owner/action with a packet array and returns the action's consumed count; it advances the packet table and increments outstanding count only after the callback returns.
- Packet getDataVirtualAddress returns buffer base; getDataOffset must be added. The bridge accepts only one-buffer Ethernet packets with explicit bounds checks.
- TxCompletion enqueuePackets invokes completePackets, notifies the packet source queue, completes/prepares state, and deallocates through the pool. The bridge defers completion to a timer after the submission callback returns. Core ethTx copies into hardware-owned staging memory before returning success.
- RxCompletion enqueuePacketsForNetworking transfers packet handles to kern_netif_queue_rx_enqueue. The bridge allocates from the pool with no-sleep option, sets offset/length, and relinquishes ownership only on successful enqueue; failure deallocates the packet. RX counters denote enqueue to OS, not proof of application delivery.

## Changes

Opt-in `itlmt_native_dp=1` activates the core firmware/M2/M3 radio engine while suppressing creation of the legacy Ethernet interface. Existing injected credentials drive the core's initial scan/auth/join; this is not yet CoreWLAN scan/join integration. Firmware station MAC is kept consistent with the pre-existing Stage B test identity. Credentials are neither added to source nor printed by the bridge.

Versioned internal platform functions bind/unbind a native sink and accept TX Ethernet frames. A core callback lock makes unbind a barrier; RX/link callbacks only copy/update under the native RX lock and never acquire the native work-loop gate. TX invokes the existing core send path from the native gate. RX uses a bounded 63-frame ring; TX completions use a bounded 512-packet list. Backpressure reports zero consumed rather than freeing unsent packets. Native timer polls for TX retry, drains RX and returns completions. Queue enable/disable and control-path traces are recorded.

## Tracing and collection

- Kernel IOLog milestones, registry startup trace, last milestone and tail marker. No packet payloads logged.
- First TX, RX allocation/enqueue, TX completion; queue enable boundaries; controller startup and first 32 distinct ioctl IDs.
- Per-second registry counters: TX sent/drop/stall/completed/pending, RX received/enqueued/drop, radio link and datapath enable.
- `itlmt_native_nvtrace=1` writes bounded NVRAM checkpoints (`itlmt-native-trace`, overflow `itlmt-native-last`), forcing sync. Best effort only: an early panic or failed NVRAM write can still lose the latest checkpoint. This experiment does not guarantee a full panic trace.
- native-wifi-test.sh logs also gathers current kernel args, en9 media output, the private full core registry, selected native NVRAM checkpoints and AAPL,PanicInfo chunks. Raw core registry/panic data stays local until sanitized.

## Discovery

Read-only test on the running 5e3afae kernel: SCNetworkInterfaceCopyAll excludes en9, but the shipped framework's explicit BSD-name lookup returns en9 type IEEE80211. live-discovery-explicit-bsd-5e3afae.txt records this, without MAC/SSID. `tools/native_wifi_service.c` can probe or create a genuine IEEE80211 network service using that interface; create requires root and a private preferences backup. It was probed only, not used to create a service before the new kernel boots. Source declaration cross-checked with Apple's configd SCNetworkInterface.c: https://github.com/apple-oss-distributions/configd/blob/main/SystemConfiguration.fproj/SCNetworkInterface.c

## Hardware test pending

Build both core and native; static build/link/slot results are recorded in TEST-NATIVE-WIFI.md. Install Stage B exclusive with dp=1 and nvtrace=1; leave wl/publish defaults 1/2. After reboot collect before changing flags, then explicitly enable en9 / create its Wi-Fi service using the backed-up helper and inspect native/core counters, link, media and traffic. Stop on panic and recover its backtrace plus NVRAM checkpoints. Sleep/wake and unload have not been validated; inherited core worker shutdown is still incomplete. UI radio power and native scan/join getters/setters remain unsupported, so this experiment does not claim fully working native Wi-Fi.

## BSD link reporting follow-up

IONetworkController::_broadcastEvent only notifies objects conforming to IONetworkInterface; the native Skywalk interface does not. Controller setLinkStatus alone therefore cannot notify BSD. The verified nonvirtual IOSkywalkNetworkInterface::reportLinkStatus(status, medium) updates media/link status and posts BSD link events without IO80211 Glue ioctl calls. The native timer now calls it with the real core radio state and IEEE80211Auto; NotAttached is retried without unbounded checkpoint logging until the BSD client is ready. The declaration uses the checked Mach-O export so generated vtable headers stay untouched. Link check still has only six baseline missing symbols.
