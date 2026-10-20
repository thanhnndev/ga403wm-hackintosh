// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
#ifndef ITLMT7925_HPP
#define ITLMT7925_HPP

#include <IOKit/IOService.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IOLib.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IOLocks.h>

#include "itl_caps.h"
#include "itl_ba.h"
#include "itl_native_bridge.h"

class itlmt7925Eth;
class IOUserClient;

// Per-frame options for m3Tx (everything defaults to the verified legacy behaviour: fixed 6 Mb/s, management queue)
struct M3TxOpt {
    bool protect = false;     // encrypt (Protected Frame bit; the hardware adds the CCMP header)
    bool rateAdapt = false;   // no FIXED_RATE: the firmware's rate control chooses the MCS
    uint8_t tid = 0;          // TXD1.TID: 0 normal, 2 = MT_TX_ADDBA for an ADDBA request
    uint8_t qidx = 0x10;      // TXD0.Q_IDX: 0x10 = MT_LMAC_ALTX0 (management / non-QoS), 0..3 = access categories
    int sn = -1;              // >= 0: sequence number chosen by the host (TXD3.SN_VALID)
    bool aggr = false;        // leave BA_DISABLE clear: the frame may be sent in an A-MPDU
    bool *full = nullptr;     // set: no staging slot / descriptor free, the caller keeps the frame (Ethernet output queue)
};

struct itl_dma_buf {
    IOBufferMemoryDescriptor *md = nullptr;
    uint8_t *va = nullptr;
    uint64_t pa = 0;
    size_t size = 0;
};

struct itl_ring {
    itl_dma_buf desc;      // n * 16 bytes
    itl_dma_buf buf;       // tx: one 4 KiB staging buffer, rx: n * 2048
    uint32_t regs = 0;     // BAR0 offset of this queue's register block
    int n = 0;
    int head = 0;          // tx: next slot to write; rx: next slot to refill
    int tail = 0;          // rx: next slot to read
    uint16_t slotBuf[1536]; // rx: which buffer sits in which slot (MT7925_RX_RING_SIZE at most)
};

class itlmt7925 : public IOService {
    OSDeclareDefaultStructors(itlmt7925)

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn callPlatformFunction(const OSSymbol *, bool, void *, void *, void *, void *) override;
    // Ethernet interface glue (itlmt7925_eth.cpp): frames from the network stack / frames received from the AP
    // 0 sent, 1 no TX buffer free (the output queue keeps the frame until ethTxKick()), -1 dropped
    int  ethTx(const uint8_t *frame, uint32_t len);
    bool ethCreate();
    void ethRx(const uint8_t *frame, uint32_t len);
    void ethTxKick();                        // restart a stalled output queue
    void ethFlush();                         // deliver the received batch to the stack
    // Speed shown by macOS for the interface: the estimated best PHY rate when HT/VHT is in use, else the 54 Mb/s legacy value
    static void baDeliverCb(void *ctx, const uint8_t *frame, uint32_t len);
    uint64_t linkSpeedBps() const { return fastActive ? (uint64_t)fastRate * 1000000ull : 54000000ull; }
    // Runtime control from user space (itlmt7925_uc.cpp, ABI in itl_uc_abi.h): the worker thread picks the commands up.
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                           IOUserClient **handler) override;
    IOReturn ucScan();
    IOReturn ucJoin(const char *ssid, const char *psk);
    IOReturn ucDisconnect();

private:
    bool nativeMode = false;
    IOLock *nativeLock = nullptr;
    ItlNativeSink nativeSink = {};
    IOPCIDevice *pci = nullptr;
    IOMemoryMap *bar0 = nullptr;
    volatile uint8_t *regs = nullptr;
    uint32_t barSize = 0;

    uint32_t rd(uint32_t off);
    void wr(uint32_t off, uint32_t val);
    uint32_t rdMapped(uint32_t addr);       // translates a few CONN addresses
    // M1 (gated by boot-arg itlmt_m1=<delay seconds>)
    uint32_t mapAddr(uint32_t addr, uint32_t *restoreL1);
    uint32_t rdA(uint32_t addr);
    void wrA(uint32_t addr, uint32_t val);
    void rmwA(uint32_t addr, uint32_t clr, uint32_t set);
    bool pollA(uint32_t addr, uint32_t mask, uint32_t val, uint32_t timeoutMs);
    void m1log(const char *fmt, ...);
    bool dmaAlloc(itl_dma_buf &b, size_t size, bool cached = false);
    void dmaFree(itl_dma_buf &b);
    bool ringInit(itl_ring &r, int qid, uint32_t base, int n, bool rx, bool cached = false);
    void ringFree(itl_ring &r);
    void dmaDisable();
    void dmaEnable();
    bool txKick(itl_ring &r, size_t len);
    int  mcuSend(uint8_t cid, const void *payload, size_t plen, bool wantResp, int *ret);
    int  fwScatter(const uint8_t *data, size_t len);
    int  rxWait(uint8_t seq, int *ret, uint32_t timeoutMs);
    int  initDownload(uint32_t addr, uint32_t len, uint32_t mode);
    int  loadPatch();
    int  loadRam();
    int  m1Run();
    void m1Main();
    static void m1Thread(void *arg);
    itl_ring txWm, txFwdl, rxEvt, rxData;
    // M2 (boot-arg itlmt_m2=1): UNI commands, interface setup, scan, beacon parsing
    bool m2On = false;
    int  uniSend(uint8_t cid, const void *payload, size_t plen, bool query, uint8_t *evOut, size_t evMax,
                 uint32_t *evLen, uint32_t timeoutMs);
    bool ringPeek(itl_ring &r, const uint8_t **data, uint32_t *len, int *bi);
    void ringRelease(itl_ring &r, int bi);
    void rxDataPoll();
    void rxParseFrame(const uint8_t *p, uint32_t len);
    void rxFrameDump(const uint8_t *p, uint32_t len);
    void m2log(const char *fmt, ...);
    void m2State(const char *tag);
    uint32_t fwLogCnt = 0;
    void m2Publish();
    int  m2Run();
    int  m2Scan(const char *ssid);
    uint8_t scanSeq = 0;
    uint32_t scanMs = 0, evLogged = 0;
    uint8_t chHist[200] = {0};
    char m2buf[2048] = {0};
    size_t m2len = 0;
    char m2res[400] = {0};
    uint8_t mac[6] = {0};
    bool scanDone = false;
    uint32_t rxPkts = 0, rxBeacons = 0, rxOther = 0, rxDump = 0;
    uint32_t evCount = 0;
    // sec: ITL_SEC_* (itlmt7925_uc.cpp); rssi in dBm, 0 = not measured; seenMs = nowMs() of the last beacon / probe response
    // cap / bcnInt / ie / probe: the frame as heard (native Wi-Fi hands them to the Family as the scan result's beacon message)
    struct itl_ap { uint8_t bssid[6]; uint8_t ch; char ssid[33]; int8_t rssi; uint8_t sec; uint32_t seenMs; uint32_t seenGen;
                    uint8_t probe; uint16_t cap, bcnInt, ieLen; uint8_t ie[ITL_NATIVE_IE_MAX]; } aps[ITL_NATIVE_AP_MAX];
    int nAps = 0;
    uint32_t apGen = 0;                      // bumped per scan: an entry with seenGen != apGen was not heard in the current scan
    uint8_t mcuSeq = 0;
    // M3 (boot-arg itlmt_m3=1, implies M2): associate to the configured network, WPA2-PSK, Ethernet interface
    bool m3On = false;
    itl_ring txData;                         // band0 data TX ring (mgmt + data frames)
    void m3log(const char *fmt, ...);
    void m3Publish(const char *stage);
    int  m3Run();
    void m3Capture(const uint8_t *frame, uint32_t len, const char *ssid, uint8_t ch);
    int  m3Cmd(uint8_t cid, const void *payload, size_t plen, const char *name);
    int  m3HwPrep();
    void ctlPoll();                          // link loop: take run-time control requests (setProperties)
    enum M3BssOp { M3_BSS_ADD, M3_BSS_ASSOC, M3_BSS_REMOVE };
    int  m3Bss(M3BssOp op);
    uint8_t grpWcid19 = 0;                   // itl_grp19: 0 = group TX on the AP wcid (the proven path), 1 = the mt76 BSS wcid 19 + its STA_REC records
    int  m3Clc(const char *cc, uint8_t env);   // CLC power tables from the RAM firmware for country cc
    int  clcSend(const uint8_t *clc, const char *cc, uint8_t env, uint8_t idx);
    int  m3TxPower();                        // per-channel rate power limits (SAR from ACPI MTDS / MTGS)
    int  efuseRead(uint32_t off, uint8_t *val);
    void sarInit();
    int  powerCmd(const void *payload, size_t plen, const char *name);
    int  m3Edca();                           // per-AC contention parameters from the AP's WMM element (after every BSS_INFO)
    int  m3Sta(uint8_t state, bool newly, uint16_t aid);
    int  m3StaBss();                         // STA_REC_UPDATE for the BSS wcid (19): what mt76 sends on BSS_CHANGED_ASSOC
    int  m3Roc(bool acquire, int channel = -1);
    // AWDL PSF sync frame handoff (docs/ROADMAP-AWDL.md phase 3): awdlSubmit() copies one frame from the native interface's
    // setAWDL_SYNC_FRAME_TEMPLATE into this mailbox and awdlSyncTx() runs on the link thread, pushing it out during a ROC
    // window on the AWDL channel (the firmware has no AWDL channel sequencing of its own).
    int  awdlSubmit(const uint8_t *frame, uint32_t len, uint8_t channel, uint32_t dwellMs);
    void awdlSyncTx();
    uint8_t awdlFrame[256] = {};
    volatile uint32_t awdlFrameLen = 0;
    volatile uint32_t awdlFrameSeq = 0, awdlFrameDone = 0;
    uint8_t awdlChannel = 6;
    uint32_t awdlDwellMs = 60;
    uint32_t awdlTxTry = 0, awdlTxOk = 0, awdlTxRocFail = 0;
    void m3Pump(uint32_t ms);
    void m3Event(const uint8_t *ev, uint32_t len);
    void m3ParseAp();
    volatile bool rocGrant = false;
    volatile bool rocWant = false;                  // a ROC grant is expected (set by m3Roc); the event is parsed after link up too
    uint8_t rocTok = 0, rocStatus = 0xff;
    uint8_t m3cipher = 0;                    // 0 = open, 4 = CCMP (BSS_INFO sec TLV)
    uint8_t apSupp = 0, apBasic = 0;         // OFDM rate bitmaps (6,9,12,18,24,36,48,54 -> bit 0..7)
    uint8_t apCck = 0, apBasicCck = 0;       // 2.4 GHz CCK rate bitmaps (1,2,5.5,11 -> bit 0..3)
    uint8_t apRsn[64] = {0};
    uint8_t apRsnLen = 0;
    uint8_t apGroupCipher = 0;               // RSN suite type: 1 WEP40, 2 TKIP, 4 CCMP, 5 WEP104 (0 unknown)
    uint8_t apPairCipher = 0;                // what the 4-way handshake will use: CCMP when offered, else TKIP
    char m3buf[8000] = {0};
    size_t m3len = 0;
    char m3res[400] = {0};
    char m3ssid[33] = {0};
    char m3psk[72] = {0};
    // step 3: authentication / association over the data TX ring
    uint8_t m3pmk[32] = {0};
    uint8_t m3wantFc = 0;                    // fc byte 0 of the management frame we are waiting for (0 = none)
    uint8_t m3rx[600] = {0};
    uint32_t m3rxLen = 0;
    int m3txSlot = 0;
    uint16_t m3tok = 0, m3aid = 0;
    uint32_t m3rxOther = 0, m3fwLogged = 0;
    bool m3hw = false;
    int8_t sarPwr[11];                       // ACPI dynamic SAR limit per mt76 SAR range (0.5 dBm), 127 none; read in m3HwPrep
    uint8_t hwEncap = 0;                     // efuse 0xa71 bits 1:0: selects the CLC tables meant for this module
    char clcCc[3] = {0};                     // country the CLC tables were last sent for
    // step 4: association complete -> 4-way handshake, keys, Ethernet interface, data path
    bool m3dataOn = false;                   // data frames from the AP are handled (set after association)
    bool m3wantEapol = false;
    bool m3hsApLeave = false;
    uint16_t m3hsApReason = 0;
    uint8_t m3eapol[420] = {0};
    uint32_t m3eapolLen = 0;
    // RX polling may deliver several EAPOL packets before the handshake gets CPU time.
    // Only the core worker produces/consumes this queue; no network-stack callback accesses it.
    static const uint32_t kEapolQueue = 8;
    struct EapolRx { uint32_t len; uint8_t data[420]; };
    EapolRx m3eapolQueue[kEapolQueue] = {};
    uint32_t m3eapolHead = 0, m3eapolTail = 0, m3eapolDrops = 0;
    bool m3EapolNext();
    uint8_t m3ptk[48] = {0};                 // KCK(16) KEK(16) TK(16)
    bool m3sleepy = false;                   // m3Pump sleeps instead of spinning once the link is up
    volatile bool m3linkUp = false;
    itlmt7925Eth *eth = nullptr;
    IOLock *txLock = nullptr;
    uint32_t stRxData = 0, stRxEapol = 0, stRxEth = 0, stRxDrop = 0, stTx = 0, stTxFail = 0, stNote = 0, stGrpTx = 0, stEcho = 0;
    int  m3Handshake();
    bool m3Eapol(const uint8_t *eapol, uint32_t len);
    int  m3Key(uint16_t wcid, bool pairwise, uint8_t keyId, const uint8_t *key, uint8_t keyLen, uint8_t cipher);
    bool m3RxData(const uint8_t *p, uint32_t len);
    bool m3TxData(const uint8_t *da, uint16_t ethertype, const uint8_t *payload, uint32_t plen, bool protect,
                  bool *full = nullptr);
    void m3Note(const char *dir, const uint8_t *eth, uint32_t len);
    // Post-mortem: the last Ethernet frames in either direction and one line of chip / ring / PCIe state, published as the
    // properties "wifi-frames" and "wifi-postmortem" when the firmware stops answering. chipRecover() redoes M1 + M2.
    struct FrameRec { uint32_t ms; uint16_t len, et, a, b; uint8_t dir, proto; };
    static const int kFrRing = 24;
    FrameRec frRing[kFrRing] = {};
    uint32_t frHead = 0;
    bool recoverWanted = false;
    uint32_t recoverCnt = 0;
    void frameNote(char dir, const uint8_t *eth, uint32_t len);
    void m3Postmortem(const char *tag);
    bool chipRecover();
    void m3Link();
    void nvramStat(const char *msg);
    bool m3Tx(const uint8_t *frame, uint32_t len, uint8_t type, uint8_t subtype, bool protect = false)
    {
        M3TxOpt o;
        o.protect = protect;
        return m3Tx(frame, len, type, subtype, o);
    }
    bool m3Tx(const uint8_t *frame, uint32_t len, uint8_t type, uint8_t subtype, const M3TxOpt &o);
    int  m3Run1();                           // one connection attempt (scan .. handshake .. link); m3Run() adds the fallback ladder
    int  m3PumpOnce();                       // service the rx rings once; non-zero if anything arrived
    void m3Teardown();                       // leave the AP (deauthentication, STA / BSS records) before connecting again
    bool m3RxCtl(const uint8_t *p, uint32_t len);   // Block Ack action frames and BlockAckReq from the AP
    bool m3RxMgmt(const uint8_t *p, uint32_t len);
    bool m3Xchg(const uint8_t *frame, uint32_t len, uint8_t subtype, uint8_t wantFc, uint32_t waitMs);
    int  m3Auth();
    int  m3Assoc();
    // HT/VHT (boot-arg itlmt_fast=1): advertise 11n/11ac in the association, give the firmware the AP's capabilities and let
    // its rate control choose MCS for unicast data instead of the fixed 6 Mb/s. Only used when the AP is on 5 GHz and has HT.
    bool m3fast = false;                     // requested by the boot-arg
    bool fastActive = false;                 // requested and the target AP supports it
    itl_ap_caps apCaps = {};
    uint8_t fastBw = 0, fastCenter = 0, fastNss = 1;   // operating width (CMD_CBW_*), center channel, usable streams
    uint32_t fastRate = 54;                  // estimated best PHY rate, Mb/s
    bool fastHe = false;                     // level 6 and the AP has HE: advertise and use 802.11ax
    bool fastAmsdu = false;                  // level 4: accept A-MSDU in the Block Ack agreement and unpack it
    bool fastAllow160 = false;               // level 5 and the BSS is 160 MHz wide: advertise 160 MHz
    void m3FastPlan();
    uint8_t fastSig(uint8_t level);          // features at `level` for the current AP, to skip levels that change nothing
    void m3Hex(char *out, size_t outLen, const uint8_t *p, uint32_t n);

    // ---- Block Ack, TX buffer tracking and the fallback ladder (itlmt7925_ba.cpp) ----
    // itlmt_fast=<level>: 1 HT/VHT rates, 2 + receive Block Ack (reorder buffer), 3 + transmit Block Ack, QoS access-category
    // queue, host-assigned sequence numbers and TXFREE-tracked buffers, 4 + A-MSDU receive, 5 + 160 MHz channels, 6 + HE (802.11ax).
    // If a level does not work (association or handshake fails, or no unicast frame comes back from the AP after the link is
    // up, or A-MSDUs cannot be unpacked, or the firmware reports nearly every transmission failed) the driver connects again
    // one level lower, skipping levels that would change nothing for this AP.
    uint8_t fastLevel = 0;                   // requested by the boot-arg
    uint8_t lvl = 0;                         // level of the current attempt, 0 = legacy 6 Mb/s
    uint8_t lvlCap = 255;                    // highest level not given up on the current network (reset when the network changes)
    char capSsid[33] = {0};                  // the network lvlCap belongs to: kept across disconnects and failed joins, so that a
    uint32_t capMs = 0;                      // retry from the user starts at the level that worked, not at itlmt_fast again (10 min)
    uint8_t capBand = 0;                     // band the cap was learned on (1 = 2.4 GHz, 2 = 5 GHz): another band starts over
    bool m3stepDown = false;                 // set when the attempt at `lvl` failed; m3Run() then retries one level lower
    bool m3stepRadio = false;                // ... because of radio conditions (tx failing), not because the AP rejects the level
    bool m3reachedAssoc = false;
    struct RxBaSess { itl_reorder r; itl_ba_slot *mem; uint32_t memBytes; };
    RxBaSess rxBa[8] = {};                      // receive sessions by TID (the AP is the originator)
    itl_ba_action baQ[6];                    // Block Ack action frames received, handled by baService() outside the rx path
    uint8_t baQn = 0;
    enum { TXBA_IDLE, TXBA_REQ, TXBA_ON, TXBA_GAVEUP };
    uint8_t txBaState = TXBA_IDLE, txBaToken = 0, txBaTries = 0;
    uint16_t txBaWin = 0;
    uint32_t txBaSentMs = 0, txBaNextMs = 0;
    volatile uint16_t txSn = 0;              // next sequence number of TID 0 (level 3)
    bool txPool = false;                     // level 3: TX staging buffers are released by TXFREE, not reused blindly
    bool txFreeSeen = false;
    // Staging slots of txData. One slot per ring descriptor, and well above the 64-frame Block Ack window: with 64 slots
    // every aggregate in flight held the whole pool and any retransmission produced "no slot" drops (13k of 316k frames
    // measured). The token is generation(5) | slot(8) = 13 bits, the same range the Linux driver uses for msdu ids.
    static const uint32_t kTxSlots = 256;
    uint64_t txBusy[kTxSlots / 64] = {0};    // staging slots in flight
    uint32_t txSlotT[kTxSlots] = {0};
    uint8_t txGen[kTxSlots] = {0};
    uint8_t txNext = 0;
    bool txIsBusy(uint32_t s) const { return (txBusy[s >> 6] >> (s & 63)) & 1; }
    void txSetBusy(uint32_t s) { txBusy[s >> 6] |= 1ull << (s & 63); }
    void txClrBusy(uint32_t s) { txBusy[s >> 6] &= ~(1ull << (s & 63)); }
    void txClrAll() { for (uint32_t i = 0; i < kTxSlots / 64; i++) txBusy[i] = 0; }
    uint32_t stTxUni = 0, stRxUni = 0, stRxAmsdu = 0, stTxFree = 0, stTxReclaim = 0, stTxNoSlot = 0, stTxFwFail = 0, stTxFwRetry = 0;
    uint32_t stBaReqRx = 0, stBaDecl = 0, stBaRxOn = 0, stBaTxOn = 0, stBaDel = 0, stBaBar = 0;
    uint32_t linkUpMs = 0, lastReorderMs = 0;
    // How long a frame waits in a Block Ack reorder buffer for a missing earlier one (boot-arg itlmt_reo=<ms>). mac80211 uses
    // 100 ms; measured here: 1258 timeouts in 536 s at 100 ms = 23 % of the time with the receive path held, while a hole is
    // either filled by the AP's retry within a few ms or never. 30 ms keeps the retries and cuts the stalls.
    uint32_t reoMs = 30;
    // Boot-arg itlmt_no160=1: never run a 160 MHz channel (level 5/6 stay 80 MHz; HE keeps working). A/B for 160 MHz links where
    // the AP re-sends ~9 % of the frames already received (its Block Acks from us do not arrive) and holes never fill.
    bool no160 = false;
    // Boot-arg itlmt_nopwr=1: no CLC / SAR power tables at join (the firmware's own defaults, as the benchmarks before a45e8c1
    // ran); the tables can then be sent at run time (ctlPwr) for a before/after comparison in one boot.
    bool noPwr = false;
    // A-MSDU receive stays off by default (levels 4..6 run without it): the round 26 matrix gave 5.6 MB/s at level 3 and 25-60 KB/s
    // at every level with A-MSDU in the Block Ack agreement, same AP / radio / tables. Boot-arg itlmt_amsdu=1 or itl_amsdu=1
    // (run time, with the next reconnect) turn it back on for the diagnosis.
    bool noAmsdu = true;
    uint32_t stAmsduAi[4] = {}, stAmsduN[5] = {}, stBundleOvf = 0;   // RXD4 payload format seen, subframes per packet (0..3, 4+), bundle full
    uint8_t pwrCeil = 40;                   // per-rate ceiling of the SKU tables, 0.5 dBm (m3TxPower)
    uint32_t statSecs = 0;                   // boot-arg itlmt_stat=<s>: stat-log period (default 5 s for 5 min, then 60 s)
    // Run-time control (IORegistryEntrySetCFProperties, administrator only; tools/itlctl.c). Taken by the link loop, so an A/B
    // does not need a reboot: itl_lvl = reconnect at that level, itl_no160, itl_reo = reorder timeout ms, itl_pwr = send the
    // power tables now with that per-rate ceiling (0.5 dBm).
    volatile uint32_t ctlLvl = 0, ctlPwr = 0;
    uint8_t lvlForce = 0;                    // level the next reconnect uses (set from ctlLvl), 0 = the ladder's own choice
    int  m3PowerSetup();                     // efuse hw type + CLC + SKU tables; best effort, 0 when the link may go on
    IOReturn setProperties(OSObject *props) override;
    // Where do the large frames go: classes of the Ethernet frame length (<128, <512, <1024, <1280, <1400, >=1400) at the RX ring,
    // after A-MSDU / header parsing, and when handed to the stack; big ICMP echoes (>= 1000 B) at the same stages and on TX.
    uint32_t szRing[6] = {}, szParsed[6] = {}, szDeliv[6] = {}, szOther[6] = {};
    uint32_t icmpRepParsed = 0, icmpRepDeliv = 0, icmpReqTx = 0;
    static uint8_t szClass(uint32_t n) { return n < 128 ? 0 : n < 512 ? 1 : n < 1024 ? 2 : n < 1280 ? 3 : n < 1400 ? 4 : 5; }
    static bool isBigEcho(const uint8_t *e, uint32_t n, uint8_t type) {
        return n >= 1000 && n >= 34 && e[12] == 0x08 && e[13] == 0x00 && e[23] == 1 && e[14 + ((e[14] & 15) * 4)] == type;
    }
    // one sample per second: [eth delivered, ring frames, tx, fw retries, tx no-slot stalls, reorder old, reorder timeouts]
    static const uint32_t kTsN = 90;
    uint32_t tsRing[kTsN][7] = {};
    uint32_t tsHead = 0, tsLastMs = 0, tsPrev[7] = {};
    void tsSample(uint32_t now);
    char rssiProbe[700] = {0};               // RXD layout samples of the first beacons with RX vector, for the signal decoder
    uint8_t rssiProbeN = 0;
    // A-MSDU receive (level 4): the hardware splits an A-MSDU into one RX packet per subframe (first / middle / last in RXD4),
    // each with the 802.11 header. The subframes of one MPDU are collected in a bundle and handed to the reorder buffer together.
    struct AmsduAsm { bool active; uint8_t tid; bool reorder; uint16_t sn; uint32_t used, t; uint8_t buf[ITL_BA_SLOT_BYTES]; };
    AmsduAsm amsduAsm = {};
    uint32_t stAmsduPkt = 0, stAmsduSub = 0, stAmsduBad = 0, stRxBigDrop = 0;
    uint32_t amsduLogged = 0, amsduBadLogged = 0, rxdLogged = 0;
    // 802.11 duplicate detection for unicast data outside a Block Ack reorder window: the AP resends an MPDU whose ACK it did not
    // hear (Retry bit set, same sequence number), and nothing below this driver drops it. Index = TID, 8 = non-QoS.
    uint16_t rxLastSn[9] = {};
    uint16_t rxLastValid = 0;
    uint32_t stRxDupL = 0;
    uint32_t stRxRetry = 0, stRxPkt = 0;     // unicast QoS data MPDUs with the Retry bit / all unicast QoS data MPDUs (AP resends)
    uint32_t txfWinFree = 0, txfWinFail = 0, txfBad = 0;   // TX failure watchdog (level >= 3), 5 s windows
    volatile bool ethStalled = false;        // the Ethernet output queue is stalled on a full TX pool (under txLock)
    uint32_t ethStallMs = 0;
    uint32_t m3RxAmsdu(const uint8_t *body, uint32_t blen, uint8_t ai, bool reorder, uint8_t tid, uint16_t sn);
    void amsduFlush();                       // hand the collected subframes to the reorder buffer
    void rxStore(const uint8_t *eb, uint32_t n, bool reorder, uint8_t tid, uint16_t sn, bool last);   // Ethernet frame -> stack / reorder buffer
    static void ethDeliverCb(void *ctx, const uint8_t *frame, uint32_t len);
    static void amsduFrameCb(void *ctx, const uint8_t *da, const uint8_t *sa, uint16_t et, const uint8_t *pl, uint32_t pn);
    char balog[1100] = {0};
    size_t balen = 0;
    void baLog(const char *fmt, ...);
    void nvramBa(const char *buf);           // itlb0..itlb2
    uint32_t nowMs();
    void baReset();                          // forget every session (state is lost on re-association)
    void baService();                        // called from the link loop
    void baRxRequest(const itl_ba_action &a);
    void baRxStop(uint8_t tid, bool sendDelba);
    void baTxStart();
    void baTxResponse(const itl_ba_action &a);
    void baTxStop(bool sendDelba);
    int  baStaCmd(uint8_t tid, bool recipient, bool enable, uint16_t ssn, uint16_t win, bool amsdu = false);
    bool baSendAction(const uint8_t *body, size_t blen, uint8_t tid);
    bool txSlotAlloc(uint32_t *slot, uint16_t *tok);
    void m3TxFree(const uint8_t *p, uint32_t len);
    void ethDeliver(const uint8_t *frame, uint32_t len);
    // target AP, captured from a beacon / probe response during the scan
    bool tgtFound = false;
    uint8_t tgtBssid[6] = {0};
    uint8_t tgtCh = 0;
    uint16_t tgtCap = 0, tgtBcnInt = 0;
    uint8_t tgtIe[1024] = {0};
    uint32_t tgtIeLen = 0;
    char m1buf[3072] = {0};
    size_t m1len = 0;
    bool m1Started = false;
    bool regPending = false;              // native mode: registerService() waits until the firmware MAC is known (publishService)
    void publishService();
    bool driverOwn();
    void dumpState();
    void holdLog();
    void nvramLog(const char *msg);       // survives reboot, readable from Windows
    void nvramChunks(const char *buf);    // whole m3 log -> itlk0..itlk7
    char logbuf[240] = {0};
    size_t loglen = 0;
    void note(const char *fmt, uint32_t a = 0, uint32_t b = 0, uint32_t c = 0);

    // ---- runtime control: command mailbox, supervisor loop, status for the menu bar app (itlmt7925_uc.cpp) ----
    enum { CMD_SCAN = 1, CMD_JOIN = 2, CMD_DISCONNECT = 4, CMD_AWDL_SYNC = 8 };
    // hasPmk: `pmk` is the ready pairwise master key (native Wi-Fi: userland's supplicant derived it), psk is empty then
    struct Net { char ssid[33]; char psk[72]; bool hasPmk; bool native; uint8_t pmk[32]; };
    IOLock *cmdLock = nullptr;
    volatile uint32_t cmdBits = 0;
    Net reqNet = {};                         // the network of the last join command (under cmdLock)
    uint32_t lastScanReqMs = 0;
    bool cmdPending(uint32_t mask) const { return (__atomic_load_n(&cmdBits, __ATOMIC_ACQUIRE) & mask) != 0; }
    uint32_t cmdTake(uint32_t mask, Net *join);
    Net candNets[4] = {};                    // candidates for the next m3Run1(), in priority order
    int candN = 0;
    int loadPlistNets(Net *out, int max);
    bool apInRange(const char *ssid, uint32_t maxAgeMs);
    void m3Supervise();                      // replaces a single m3Run(): connect, reconnect, obey commands
    void wifiState(const char *st, const char *err);
    void wifiLink();                         // ssid / channel / rssi / rate of the current link
    void wifiNets();                         // wifi-networks from aps[]
    void wifiScan();                         // wildcard scan, then wifiNets()
    void apSeen(const uint8_t *p, uint32_t len, uint32_t off, const char *ssid, uint8_t ch);   // beacon / probe response
    int8_t rxRssi(const uint8_t *p, uint32_t len, uint32_t hdrOff);
    char wstate[16] = {0};
    uint32_t scanGen = 0;
    volatile uint32_t scanBusy = 0;          // a scan is queued (CMD_SCAN) or running (native Wi-Fi reads it through ITL_NATIVE_NETS)
    // native Wi-Fi join bookkeeping, read by ITL_NATIVE_STATUS: njState is ITL_NATIVE_*, njSeq counts joins, njFail a stage code
    volatile uint32_t njState = 0, njSeq = 0, njFail = 0;
    IOReturn nativeScanReq(uint32_t *started);
    IOReturn nativeJoin(const struct ItlNativeJoin *j);
    void nativeStatus(struct ItlNativeStatus *s);
    void nativeNets(struct ItlNativeNets *n);
    volatile bool m3lost = false;            // the AP sent deauthentication / disassociation, or went silent
    char m3lostWhy[48] = {0};
    char evbuf[6000] = {0};                  // wifi-events: the last link events of this boot, one per line, oldest first
    size_t evlen = 0;
    void evLog(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
    uint32_t tgtLastBcnMs = 0, lastRxDataMs = 0;
    uint32_t tgtBcnCount = 0;                // beacons heard from tgtBssid while linked; reported in ItlNativeStatus.beaconCount
    int8_t tgtRssi = 0;
    void ethLink(bool up);
};

#endif
