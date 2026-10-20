// SPDX-License-Identifier: BSD-3-Clause-Clear
#pragma once
#include <IOKit/IOService.h>
// Internal versioned ABI, kernel pointers only; no userspace entry point.
struct ItlNativeSink {
    uint32_t version;
    OSObject *owner;
    OSObject *lifetime; // retained with each out-of-lock link callback
    void (*receive)(OSObject *, const uint8_t *, uint32_t);
    void (*link)(OSObject *, bool, uint64_t);
};
struct ItlNativeTx { const uint8_t *bytes; uint32_t length; int result; };
#define ITL_NATIVE_BIND "itlmt-native-bind-v2"
#define ITL_NATIVE_UNBIND "itlmt-native-unbind-v2"
#define ITL_NATIVE_TX "itlmt-native-tx-v1"
#define ITL_NATIVE_MAC "itlmt-native-mac-v1"

// ITL_NATIVE_AWDL_SYNC, p1 = ItlNativeAwdlSync*: hand one AWDL PSF (sync) frame to the core's link thread. It holds the radio
// on `channel` (a UNI_ROC window), hands the frame to the firmware, and returns to the infrastructure channel afterwards.
// The firmware has no AWDL channel sequencing of its own, so this off-channel slot is the driver's half of the AWDL sync
// (docs/ROADMAP-AWDL.md phase 3). The call only copies the frame into the core's mailbox; it never blocks on the chip.
struct ItlNativeAwdlSync {
    uint32_t version;
    const uint8_t *frame;     // complete 802.11 frame (the Family's sync frame template)
    uint32_t len;
    uint8_t channel;          // AWDL channel; 6 is the 2.4 GHz social channel
    uint32_t dwellMs;         // ROC window that covers the transmission
};
#define ITL_NATIVE_AWDL_SYNC "itlmt-native-awdl-sync-v1"

// ---- scan / join control (all calls come from the interface's work queue; none blocks on the chip) -------------------------
// Information elements are kept whole-element up to this many bytes (a beacon's own IEs; the rest is cut at an element boundary).
#define ITL_NATIVE_IE_MAX 512
// AP table size. 48 was too small for a dense 5 GHz neighbourhood: the scan visits 2.4 GHz (1..13) first and 5 GHz (36..165)
// after, so with the table full the early-heard 2.4 GHz APs were the "oldest" and got evicted by the 5 GHz flood - named
// 2.4 GHz networks (the ones the user was looking for) never reached the published list. 128 keeps everything in one pass;
// the eviction below additionally refuses to drop an AP heard in the scan that is running.
#define ITL_NATIVE_AP_MAX 128

// ITL_NATIVE_SCAN, p1 = ItlNativeScan*: asks the core worker for one wildcard scan. started = 0 when the core scanned less than
// 10 s ago (the cached list is current enough; the caller delivers it at once), 1 when a scan was queued.
struct ItlNativeScan { uint32_t version; uint32_t started; };
#define ITL_NATIVE_SCAN "itlmt-native-scan-v1"

// ITL_NATIVE_NETS, p1 = ItlNativeNets*: snapshot of the core's AP table. `aps` is caller memory for `max` entries.
struct ItlNativeAp {
    uint8_t bssid[6];
    uint8_t channel;          // primary channel
    uint8_t security;         // core's own classification (ITL_SEC_*), informational
    int8_t rssi;              // dBm, 0 = unknown
    uint8_t ssidLen;
    char ssid[33];
    uint8_t probeResponse;    // 1: last frame heard was a probe response, 0: beacon
    uint16_t capability;
    uint16_t beaconInterval;
    uint16_t ieLen;
    uint32_t ageMs;
    uint8_t ie[ITL_NATIVE_IE_MAX];
};
struct ItlNativeNets {
    uint32_t version;
    uint32_t max;             // in: capacity of aps
    uint32_t count;           // out
    uint32_t scanGen;         // out: incremented when a scan finishes
    uint32_t scanBusy;        // out: a scan is queued or running
    ItlNativeAp *aps;
};
#define ITL_NATIVE_NETS "itlmt-native-nets-v1"

// ITL_NATIVE_JOIN, p1 = ItlNativeJoin*: connect to `ssid` with a ready pairwise master key (the supplicant of Apple's design
// runs in userland; the 4-way handshake still runs in the core). The core wipes its copy; the caller wipes this one.
struct ItlNativeJoin {
    uint32_t version;
    uint8_t ssidLen;
    char ssid[33];
    uint8_t pmk[32];
};
#define ITL_NATIVE_JOIN "itlmt-native-join-v1"
// ITL_NATIVE_LEAVE, p1 unused: leave the network / abort a join in progress.
#define ITL_NATIVE_LEAVE "itlmt-native-leave-v1"

// ITL_NATIVE_STATUS, p1 = ItlNativeStatus*: link / join state and the current BSS.
enum { ITL_NATIVE_IDLE = 0, ITL_NATIVE_CONNECTING = 1, ITL_NATIVE_UP = 2, ITL_NATIVE_FAILED = 3 };
struct ItlNativeStatus {
    uint32_t version;
    uint32_t state;           // ITL_NATIVE_*
    uint32_t joinSeq;         // incremented by every ITL_NATIVE_JOIN
    uint32_t failStage;       // 0 none; 1 no credentials, 2 network not seen, 3 radio, 4 authentication, 5 association, 6 handshake, 7 other
    uint32_t scanGen;
    uint32_t scanBusy;
    uint8_t bssid[6];
    uint8_t channel;
    int8_t rssi;
    uint32_t rateMbps;
    uint8_t ssidLen;
    char ssid[33];
    uint16_t capability;
    uint16_t beaconInterval;
    uint16_t ieLen;
    uint8_t ie[ITL_NATIVE_IE_MAX];
    // Negotiated rates for the current link (appended in round 21; both kexts are built from this header). All zero / 0xffff while
    // the core runs the legacy 6 Mb/s path. htMcs = RX MCS bitmask bytes 0-9 of the streams in use; vhtMcs / heMcs = 2 bits per
    // spatial stream (0: MCS 0-7 / 0-7, 1: 0-8 / 0-9, 2: 0-9 / 0-11, 3 or 0xffff: none), the IEEE map format.
    uint8_t fastActive, fastNss, fastHe, fastBw;
    uint8_t htMcs[10];
    uint16_t vhtMcs, heMcs;
    // Beacons heard from the connected BSS since the counter started (round 27, appended at the end: both kexts are rebuilt
    // together). The native front end posts it in the periodic LQM event (0x27) so the family's missed-beacon monitor sees the
    // link is alive: without those posts the family drops the link with "missed beacons timeout" 60 s after it came up.
    uint32_t beaconCount;
};
#define ITL_NATIVE_STATUS "itlmt-native-status-v1"
