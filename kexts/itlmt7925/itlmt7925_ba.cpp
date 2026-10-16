// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925 - Block Ack (A-MPDU), TX buffer tracking and logging for the HT/VHT/HE mode (boot-arg itlmt_fast=2 or higher).
//
//  * RX: the AP sends an ADDBA request; we tell the firmware (STA_REC_BA, recipient), answer with an ADDBA response and put the
//    frames of that TID back in order with itl_reorder (the hardware acknowledges the A-MPDUs but does not reorder).
//  * TX (level 3): after a few frames we send an ADDBA request for TID 0; on the response STA_REC_BA (originator) lets the
//    firmware aggregate our QoS data. Sequence numbers of TID 0 are assigned here (m3TxData) so that the starting sequence number is known.
//  * TXFREE (level 3): TX staging buffers are released when the firmware says it is done with them (PKT_TYPE_TXRX_NOTIFY,
//    mt7925_mac_tx_free), not by counting. If those events turn out not to arrive, a slot is reclaimed after 30 ms.
// Everything here runs on the m3 thread except m3TxFree's lock, which it shares with m3Tx (network stack thread).
// Port of: mt7925_ampdu_action / mt7925_mcu_sta_ba (mcu.c, main.c), mt76 agg-rx.c, mt7925_mac_tx_free (mac.c).
#include "itlmt7925.hpp"
#include "mt7925_regs.h"

#include <string.h>
#include <stdarg.h>
#include <libkern/libkern.h>
#include <kern/clock.h>
#include <mach/mach_time.h>

#define UNI_STA_REC_UPDATE 0x03
#define M3_BSS_IDX 0
#define M3_AP_WCID 1
#define STA_REC_BA 6
#define MT_BA_TYPE_ORIGINATOR 1
#define MT_BA_TYPE_RECIPIENT  2

static inline uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static inline void put16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }

struct BaLock {
    IOLock *l;
    explicit BaLock(IOLock *x) : l(x) { if (l) IOLockLock(l); }
    ~BaLock() { if (l) IOLockUnlock(l); }
};

uint32_t itlmt7925::nowMs()
{
    uint64_t ns = 0;
    absolutetime_to_nanoseconds(mach_absolute_time(), &ns);
    return (uint32_t)(ns / 1000000ull);
}

// ---------------------------------------------------------------------------------------------
// log: its own short buffer (NVRAM itlb0..itlb2), because the connect log is already full by the time the link is up
// ---------------------------------------------------------------------------------------------
void itlmt7925::baLog(const char *fmt, ...)
{
    char tmp[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    IOLog("itlmt7925: BA %s\n", tmp);
    size_t n = strlen(tmp);
    if (balen + n + 2 >= sizeof(balog)) {
        // keep the first 300 bytes (what was negotiated), drop the oldest 400 after them
        const size_t keep = 300, drop = 400;
        if (balen > keep + drop) {
            memmove(balog + keep, balog + keep + drop, balen - keep - drop);
            balen -= drop;
            balog[balen] = 0;
        } else {
            return;
        }
    }
    memcpy(balog + balen, tmp, n);
    balen += n;
    balog[balen++] = ';';
    balog[balen] = 0;
    setProperty("ba-log", balog);
    nvramBa(balog);
}

// ---------------------------------------------------------------------------------------------
// session state
// ---------------------------------------------------------------------------------------------
void itlmt7925::ethDeliver(const uint8_t *frame, uint32_t len)
{
    stRxEth++;
    szDeliv[szClass(len)]++;
    if (isBigEcho(frame, len, 0)) icmpRepDeliv++;
    m3Note("rx", frame, len);
    ethRx(frame, len);
}

void itlmt7925::ethDeliverCb(void *ctx, const uint8_t *frame, uint32_t len)
{
    ((itlmt7925 *)ctx)->ethDeliver(frame, len);
}

// The reorder buffer hands over bundles: the Ethernet frames of one MPDU, each with a 2-byte length (itl_bundle_add).
void itlmt7925::baDeliverCb(void *ctx, const uint8_t *blob, uint32_t len)
{
    itl_bundle_each(blob, len, ethDeliverCb, ctx);
}

void itlmt7925::baReset()
{
    for (int t = 0; t < 8; t++) {
        if (rxBa[t].mem) {
            itl_reorder_stop(&rxBa[t].r, baDeliverCb, this);
            IOFree(rxBa[t].mem, rxBa[t].memBytes);
        }
        bzero(&rxBa[t], sizeof(rxBa[t]));
    }
    amsduAsm.active = false;
    amsduAsm.used = 0;
    baQn = 0;
    txBaState = TXBA_IDLE;
    txBaTries = 0;
    txBaNextMs = 0;
    BaLock lk(txLock);
    txClrAll();
}

// STA_REC_UPDATE with one STA_REC_BA TLV (mt7925_mcu_sta_ba). tid, direction, enable, starting sequence number, window.
int itlmt7925::baStaCmd(uint8_t tid, bool recipient, bool enable, uint16_t ssn, uint16_t win, bool amsdu)
{
    uint8_t b[8 + 16];
    bzero(b, sizeof(b));
    b[0] = M3_BSS_IDX;
    b[1] = M3_AP_WCID & 0xff;                                // wlan_idx_lo
    b[2] = 1;                                                // tlv_num
    b[4] = 1;                                                // is_tlv_append
    b[5] = 0;                                                // muar_idx
    b[6] = M3_AP_WCID >> 8;
    uint8_t *t = b + 8;
    put16(t, STA_REC_BA);
    put16(t + 2, 16);
    t[4] = tid;
    t[5] = recipient ? MT_BA_TYPE_RECIPIENT : MT_BA_TYPE_ORIGINATOR;
    t[6] = amsdu ? 1 : 0;                                    // amsdu: the agreement allows A-MSDU (level 4, receive side)
    t[7] = enable ? (uint8_t)(1u << tid) : 0;                // ba_en bitmap
    put16(t + 8, ssn);
    put16(t + 10, win);
    static uint8_t ev[512];
    uint32_t evl = 0;
    int rc = uniSend(UNI_STA_REC_UPDATE, b, sizeof(b), false, ev, sizeof(ev), &evl, 3000);
    int st = evl >= 52 ? (int)le32(ev + 48) : -1;
    baLog("sta_rec_ba %s %s tid=%u ssn=%u win=%u am=%d rc=%d st=%d", recipient ? "rx" : "tx", enable ? "on" : "off", tid, ssn, win, amsdu ? 1 : 0, rc, st);
    return (rc == 0 && (st == 0 || st == -1)) ? 0 : -1;
}

// Management (Action) frame to the AP: header + `body` (starting at the category byte).
bool itlmt7925::baSendAction(const uint8_t *body, size_t blen, uint8_t tid)
{
    uint8_t f[24 + 16];
    if (blen > 16) return false;
    bzero(f, 24);
    f[0] = 0xd0;                                             // action
    memcpy(f + 4, tgtBssid, 6);
    memcpy(f + 10, mac, 6);
    memcpy(f + 16, tgtBssid, 6);
    memcpy(f + 24, body, blen);
    M3TxOpt o;
    o.tid = tid;                                             // MT_TX_ADDBA (2) for an ADDBA request, as mt7925_mac_write_txwi_80211
    return m3Tx(f, (uint32_t)(24 + blen), 0, 13, o);
}

// ---------------------------------------------------------------------------------------------
// RX agreement (we are the recipient)
// ---------------------------------------------------------------------------------------------
void itlmt7925::baRxRequest(const itl_ba_action &a)
{
    stBaReqRx++;
    uint8_t tid = a.tid;
    uint16_t win = itl_reorder_size(a.bufsize);
    bool ok = false;
    bool am = fastAmsdu && a.amsdu;                          // level 4: unpack A-MSDUs the AP sends inside the A-MPDUs
    if (lvl >= 2 && fastActive && a.immediate) {
        if (rxBa[tid].mem) baRxStop(tid, false);             // the AP starts the agreement again
        uint32_t bytes = (uint32_t)win * (uint32_t)sizeof(itl_ba_slot);
        itl_ba_slot *mem = (itl_ba_slot *)IOMalloc(bytes);
        if (mem) {
            bzero(mem, bytes);
            if (baStaCmd(tid, true, true, a.ssn, win, am) == 0) {   // firmware first, as mac80211 does (drv_ampdu_action RX_START)
                itl_reorder_start(&rxBa[tid].r, mem, a.ssn, win);
                rxBa[tid].mem = mem;
                rxBa[tid].memBytes = bytes;
                ok = true;
                stBaRxOn++;
            } else {
                IOFree(mem, bytes);
            }
        }
    }
    uint8_t body[16];
    size_t n = itl_addba_resp_build(body, a.token, ok ? ITL_STATUS_SUCCESS : ITL_STATUS_DECLINED, tid, ok ? win : 0, ok && am, 0);
    bool sent = baSendAction(body, n, 0);
    if (!ok) stBaDecl++;
    baLog("rx addba tid=%u ssn=%u buf=%u amsdu=%d -> %s win=%u am=%d sent=%d", tid, a.ssn, a.bufsize, a.amsdu ? 1 : 0, ok ? "accept" : "decline", win, ok && am ? 1 : 0, sent ? 1 : 0);
}

void itlmt7925::baRxStop(uint8_t tid, bool sendDelba)
{
    if (!rxBa[tid].mem) return;
    itl_reorder_stop(&rxBa[tid].r, baDeliverCb, this);
    baStaCmd(tid, true, false, 0, 0);
    IOFree(rxBa[tid].mem, rxBa[tid].memBytes);
    baLog("rx ba tid=%u stopped (in=%u buf=%u flush=%u to=%u)", tid, rxBa[tid].r.nIn, rxBa[tid].r.nBuffered, rxBa[tid].r.nFlushed, rxBa[tid].r.nTimeout);
    bzero(&rxBa[tid], sizeof(rxBa[tid]));
    if (sendDelba) {
        uint8_t body[16];
        size_t n = itl_delba_build(body, tid, false, ITL_REASON_QSTA_LEAVE);
        baSendAction(body, n, 0);
    }
}

// ---------------------------------------------------------------------------------------------
// TX agreement (we are the originator), TID 0 only
// ---------------------------------------------------------------------------------------------
void itlmt7925::baTxStart()
{
    txBaToken++;
    if (!txBaToken) txBaToken = 1;
    txBaTries++;
    uint16_t ssn = txSn;
    uint8_t body[16];
    size_t n = itl_addba_req_build(body, txBaToken, 0, ITL_BA_MAX_WIN, ssn, 0, false);
    bool sent = baSendAction(body, n, 2);                    // TXD TID = MT_TX_ADDBA
    txBaState = TXBA_REQ;
    txBaSentMs = nowMs();
    baLog("tx addba req tok=%u ssn=%u try=%u sent=%d", txBaToken, ssn, txBaTries, sent ? 1 : 0);
}

void itlmt7925::baTxResponse(const itl_ba_action &a)
{
    if (txBaState != TXBA_REQ || a.token != txBaToken || a.tid != 0) {
        baLog("tx addba resp ignored (state=%u tok=%u/%u tid=%u)", txBaState, a.token, txBaToken, a.tid);
        return;
    }
    if (a.status != ITL_STATUS_SUCCESS) {
        baLog("tx addba declined status=%u", a.status);
        txBaState = TXBA_GAVEUP;
        return;
    }
    uint16_t win = a.bufsize ? (a.bufsize > ITL_BA_MAX_WIN ? ITL_BA_MAX_WIN : a.bufsize) : ITL_BA_MAX_WIN;
    uint16_t ssn = txSn;                                     // the next frame to go out; earlier ones were sent unaggregated
    if (baStaCmd(0, false, true, ssn, win) == 0) {
        txBaState = TXBA_ON;
        txBaWin = win;
        stBaTxOn++;
        baLog("tx ba on win=%u ssn=%u amsdu=%d", win, ssn, a.amsdu ? 1 : 0);
    } else {
        txBaState = TXBA_GAVEUP;
    }
}

void itlmt7925::baTxStop(bool sendDelba)
{
    if (txBaState == TXBA_ON) {
        baStaCmd(0, false, false, 0, 0);
        if (sendDelba) {
            uint8_t body[16];
            size_t n = itl_delba_build(body, 0, true, ITL_REASON_QSTA_LEAVE);
            baSendAction(body, n, 0);
        }
    }
    txBaState = TXBA_IDLE;
    txBaNextMs = nowMs() + 5000;                             // may be tried again later (txBaTries limits it)
}

// ---------------------------------------------------------------------------------------------
// Block Ack action frames and BlockAckReq from the AP: only queued here (we are inside the rx path, where talking to the
// firmware would re-enter it); baService() does the work.
// ---------------------------------------------------------------------------------------------
bool itlmt7925::m3RxCtl(const uint8_t *p, uint32_t len)
{
    for (uint32_t off = 32; off + 20 <= len && off < 240; off++) {
        uint8_t fc0 = p[off];
        if (fc0 == 0xd0) {                                   // Action
            if (off + 24 + 6 > len) continue;
            if (memcmp(p + off + 4, mac, 6) != 0 || memcmp(p + off + 10, tgtBssid, 6) != 0) continue;
            itl_ba_action a;
            if (itl_ba_action_parse(p + off + 24, len - off - 24, &a)) {
                if (baQn < sizeof(baQ) / sizeof(baQ[0])) baQ[baQn++] = a;
            }
            return true;
        }
        if (fc0 == 0x84) {                                   // BlockAckReq: the AP gave up on frames before ssn
            uint8_t tid;
            uint16_t ssn;
            if (!itl_bar_parse(p + off, len - off, mac, tgtBssid, &tid, &ssn)) continue;
            if (rxBa[tid].r.active) {
                itl_reorder_bar(&rxBa[tid].r, ssn, baDeliverCb, this);
                stBaBar++;
            }
            return true;
        }
    }
    return false;
}

void itlmt7925::baService()
{
    while (baQn) {
        itl_ba_action a = baQ[0];
        baQn--;
        for (uint8_t i = 0; i < baQn; i++) baQ[i] = baQ[i + 1];
        switch (a.action) {
        case ITL_BA_ACT_ADDBA_REQ:
            baRxRequest(a);
            break;
        case ITL_BA_ACT_ADDBA_RESP:
            baTxResponse(a);
            break;
        case ITL_BA_ACT_DELBA:
            stBaDel++;
            baLog("delba tid=%u initiator=%d reason=%u", a.tid, a.initiator ? 1 : 0, a.reason);
            if (a.initiator) baRxStop(a.tid, false);          // the AP (originator) ends its aggregation towards us
            else if (a.tid == 0) baTxStop(false);             // the AP (recipient) ends ours
            break;
        }
    }
    if (lvl >= 3 && fastActive && m3linkUp) {
        uint32_t now = nowMs();
        if (txBaState == TXBA_IDLE && stTxUni >= 10 && now >= txBaNextMs && txBaTries < 4) baTxStart();
        else if (txBaState == TXBA_REQ && now - txBaSentMs > 1500) {
            baLog("tx addba timeout");
            txBaState = TXBA_IDLE;
            txBaNextMs = now + 3000;
        }
    }
}

// ---------------------------------------------------------------------------------------------
// TX staging slots (level 3)
// ---------------------------------------------------------------------------------------------
// Caller holds txLock. A slot stays busy until TXFREE returns its token; after `reclaim` ms it is taken back anyway.
bool itlmt7925::txSlotAlloc(uint32_t *slot, uint16_t *tok)
{
    uint32_t now = nowMs();
    uint32_t reclaim = txFreeSeen ? 300 : 30;
    for (uint32_t i = 0; i < kTxSlots; i++) {
        uint32_t s = (txNext + i) & (kTxSlots - 1);
        if (txIsBusy(s)) {
            if ((uint32_t)(now - txSlotT[s]) < reclaim) continue;
            stTxReclaim++;
        }
        txSetBusy(s);
        txSlotT[s] = now;
        txGen[s] = (uint8_t)((txGen[s] % 31) + 1);           // 1..31, so a late TXFREE of an earlier use does not free this one
        *slot = s;
        *tok = (uint16_t)(((uint32_t)txGen[s] << 8) | s);              // 13 bits: generation(5) | slot(8)
        txNext = (uint8_t)((s + 1) & (kTxSlots - 1));
        return true;
    }
    return false;
}

// PKT_TYPE_TXRX_NOTIFY: tx_free[0] type|msdu_cnt, tx_free[1] version (>= 4), then per wcid pair / header / two 15-bit msdu ids.
void itlmt7925::m3TxFree(const uint8_t *p, uint32_t len)
{
    if (len < 12) return;
    uint32_t d0 = le32(p), d1 = le32(p + 4);
    uint32_t total = (d0 >> 16) & 0x3ff, ver = (d1 >> 16) & 0xf;
    static bool warned = false;
    if (ver < 4) {
        if (!warned) { warned = true; baLog("txfree ver=%u (<4): ignored", ver); }
        return;
    }
    uint32_t count = 0;
    bool kick = false;
    {
        BaLock lk(txLock);
        uint32_t freed0 = stTxFree;
        for (const uint8_t *c = p + 8; count < total && c + 4 <= p + len; c += 4) {
            uint32_t info = le32(c);
            if (info & (1u << 31)) continue;                     // new wcid pair
            if (info & (1u << 30)) {                             // header: attempts and status of the frames that follow
                uint32_t cnt = (info >> 24) & 0xf, st = (info >> 28) & 3;
                stTxFwRetry += cnt ? cnt - 1 : 0;
                if (st) stTxFwFail++;
                continue;
            }
            for (int i = 0; i < 2; i++) {
                uint32_t id = (info >> (15 * i)) & 0x7fff;
                if (id == 0x7fff) continue;
                count++;
                uint32_t s = id & (kTxSlots - 1);
                if (txIsBusy(s) && txGen[s] == (id >> 8)) {
                    txClrBusy(s);
                    stTxFree++;
                    txFreeSeen = true;
                }
            }
        }
        if (ethStalled && stTxFree != freed0) { ethStalled = false; kick = true; }
    }
    if (kick) ethTxKick();                                   // outside txLock: the queue calls back into m3Tx
}
