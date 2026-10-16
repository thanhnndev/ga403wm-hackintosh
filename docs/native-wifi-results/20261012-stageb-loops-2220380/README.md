# Post-panic loop trace collection — 2026-10-12

User reports one panic with publish build 06840d9, followed by reboot. That panic is already recorded in `docs/native-wifi-results/20261012-stageb-publish-06840d9/panic-decoded.txt`. This turn collected the current running state and round 10 read-only; it did not build/install another kext, change NVRAM or reboot.

Current native UUID: 2A4BF604-7D91-35D3-BBF1-7CF5E699A3DA. Its trace includes the loop diagnostics introduced in 2220380; this is a post-recovery diagnostics build, not the original panic boot. The exact independently installed binary/source mapping was not verified in this collection.

Controller and interface are registered/matched/active. Interface has unit 9, role Infrastructure, and IODeferBSDAttach=Yes. No en9 is present. Actual kern.bootargs contains Stage B exclusive and neither a publish override nor itlmt_native_wl=1. This state is consistent with the new default publish=1.

Trace reaches registerInfraEthernetInterface=0, registerService(8), setRunningState(false), and startWithInfo success. The final diagnostic is truncated:

```text
mk:loops wq=0xffffff90543a5a10 provider=0xffffff90543a6d30 ctl=0xffffff90543a6d30 iface=0xfffff
```

The fully captured wq pointer differs from provider; ctl equals provider. iface and wq.inGate/wq.onThread are unavailable. The implementation uses a 96-byte formatting buffer for each itlmtTrace addition, which truncates the long pointer/status format before all fields can be recorded; the accumulated trace also has a finite cap. Split the loop diagnostic into short entries or separate registry properties before drawing runtime conclusions about iface/gate/thread.

Round 10 is supplied with this result. Original tool has 88 dumps and six missing exact names. Supplementary dumps cover executable Glue functions omitted by the CLASS_RE filter and correctly matched work-loop getters; missing-candidates.txt lists matches found. Exact missing names remain preserved in missing.txt. The original broad prefix scanner may dump data symbols; those should not be interpreted as executable functions.

Full local logs: `~/itlmt-backup/logs-20261012-221233/` and sibling `.tar.gz`. dmesg was unavailable without privileges; persistent trace is included. Repository extracts remove SSIDs/MACs/passphrases/SMBIOS. No experimental work-loop/publish=2 retry or sleep/wake was performed.
