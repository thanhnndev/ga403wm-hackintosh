# Native join failure after booting 36e0da6 — 2026-10-13

## Observed on hardware

Settings lists networks and issues native WCL_ASSOCIATE. Two attempts reached successful open-system authentication and
association, received EAPOL M1 (`info=008a`, 121 bytes), queued four M2 transmissions and timed out with no M3.
Native reports `assoc:result ok=0 stage=6`. Thus the successful-join 0xd8/BSS event chain has not been tested on this boot.
The user confirms the passphrase is correct. The old "wrong password?" label was speculative.
`join-extract.txt` contains only lengths, packet stages and counters; no credentials or station/AP identifiers.

## Corrected driver defects

* Old handshake discarded retransmitted M1, then resent M2 with the first M1's replay counter and ANonce.
  Each accepted M1 now updates the counter and, if ANonce changes, derives PTK again before constructing/MICing M2.
  SNonce is retained during the exchange. Stale/inconsistent M1 is rejected.
* Old one-frame RX mailbox discarded every subsequent EAPOL frame in a poll batch. An eight-frame FIFO now preserves
  ordering and records overflow instead of silently dropping. Frames are validated and copied at their EAPOL-declared length.
* M3 must have supported pairwise/ACK/MIC/INSTALL flags, a newer counter, matching ANonce and a valid MIC before key installation.
* Deauthentication/disassociation during handshake now terminates the exchange and records the AP's reason code.
* Generic handshake failure no longer alleges an incorrect password.

These are demonstrated source defects. The old logs do not record retransmitted M1, counters or discarded packets, so they
cannot prove which defect caused this particular failure. Hardware success is still pending; do not claim Wi-Fi is fixed yet.

## Diagnostic evidence added

M1/M2 replay counters, ANonce-change boolean, M3 MIC result, FIFO drops, AP leave reason, RX and firmware TX-free/failure deltas.
No PMK/PTK/nonces/MICs/passphrases are printed. If M1 includes a PMKID KDE, compare the AP's PMKID with
HMAC-SHA1(PMK, "PMK Name" || AA || SPA), recording only `wifi-pmkid-match` true/false.
A mismatch identifies a PMK/station-identity disagreement, not necessarily a wrong user-entered password.
The existing 121-byte M1 could contain a 22-byte PMKID KDE, but payload was not recorded, so presence is not assumed.

`wifi-handshake` contains the latest summary even when the older 3 KB m3-log is full. `txFree` only means the firmware freed
buffers; it does not prove AP acknowledgment. WPA2-PSK/CCMP remains the supported mode.

## Build/install

Both kexts built. Native link check: 741 undefined imports, exactly six baseline reserved IONetworkController symbols missing.
Controller slots: 23 correct/0 wrong. Interface slots: 215 correct/0 wrong.
ESP config schema: zero issues; ocvalidate 1.0.9: no issues.
Full pre-install EFI backup: `~/itlmt-backup/EFI-20261013-212042` (+ tar.gz and NVRAM boot-args).
Both executable files replaced on ESP; config.plist and both Info.plists verified byte-identical, preserving injected credentials.
Installed SHA256:

* core: `71256f9814069bea886acb6b45ee5f026fec644cb57cdb584e1e39f1bcff49a1`
* native: `5c5763c161d14c62004d1545c407c3cf4059857555bbeab278e4be1ad05b1a45`

The running kernel still contains the old build. No automatic reboot or join was performed.
After the next user-controlled reboot, join from Settings and inspect `wifi-handshake`, `wifi-pmkid-match`, EAPOL kernel logs
and the native 0xd8/BSS event chain. If still failing, use this evidence to distinguish identity/key mismatch, AP rejection,
transport loss or MIC failure before changing unrelated media/UI code.

Reference for handling M1 and constructing M2: upstream hostap/wpa_supplicant `src/rsn_supp/wpa.c`:
https://chromium.googlesource.com/external/w1.fi/cgit/hostap/+/refs/heads/pending/src/rsn_supp/wpa.c
