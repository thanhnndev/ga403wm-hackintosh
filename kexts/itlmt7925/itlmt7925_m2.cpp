// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Portions derived from the Linux mt76 driver, Copyright (C) 2020, 2023 MediaTek Inc. (BSD-3-Clause-Clear)
// itlmt7925 - M2: UNI command transport, interface setup (dev/bss info) and a passive/active scan.
// Port of the connac3 path in Linux mt76 (BSD-3-Clause-Clear, Copyright (C) MediaTek Inc.):
//   mt7925/mcu.c            mt7925_mcu_fill_message (uni txd), mt7925_mcu_get_nic_capability, mt7925_mcu_hw_scan
//   mt76_connac_mcu.c       mt76_connac_mcu_uni_add_dev
//   mt7925/mac.c            mt7925_queue_rx_skb / mt7925_mac_fill_rx (RXD layout)
// Runs after M1 when boot-arg itlmt_m2=1. Scan results (beacons / probe responses) come in on the band0 RX ring and are
// parsed heuristically (the 802.11 header is located inside the RXD groups by pattern), then published as "m2-res".
#include "itlmt7925.hpp"
#include "mt7925_regs.h"

#include <string.h>
#include <stdarg.h>
#include <libkern/libkern.h>

#define ITL_TIMEOUT -110
#define ITL_EIO     -5
#define ITL_EINVAL  -22

static inline uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static inline void put32(uint8_t *p, uint32_t v) { memcpy(p, &v, 4); }
static inline void put16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }
static inline void membar() { __sync_synchronize(); }

#define MCU_UNI_DEV_INFO_UPDATE 0x01
#define MCU_UNI_BSS_INFO_UPDATE 0x02
#define MCU_UNI_CHIP_CONFIG     0x0e
#define MCU_UNI_SCAN_REQ        0x16
#define UNI_EVENT_SCAN_DONE     0x0e
#define UNI_CHIP_CONFIG_NIC_CAPA 0x3
#define MT_NIC_CAP_MAC_ADDR     7

#define UNI_OPT_ACK   (1u << 0)
#define UNI_OPT_UNI   (1u << 1)
#define UNI_OPT_SET   (1u << 2)

void itlmt7925::m2log(const char *fmt, ...)
{
    char tmp[320];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    IOLog("itlmt7925: M2 %s\n", tmp);
    size_t n = strlen(tmp);
    if (m2len + n + 2 < sizeof(m2buf)) {
        memcpy(m2buf + m2len, tmp, n);
        m2len += n;
        m2buf[m2len++] = ';';
        m2buf[m2len] = 0;
    }
    setProperty("m2-log", m2buf);
}

// ---------------------------------------------------------------------------------------------
// RX ring helpers (same refill scheme as rxWait)
// ---------------------------------------------------------------------------------------------
bool itlmt7925::ringPeek(itl_ring &r, const uint8_t **data, uint32_t *len, int *bi)
{
    if (!r.n) return false;
    uint8_t *d = r.desc.va + r.tail * 16;
    uint32_t ctrl = le32(d + 4);
    if (!(ctrl & MT_DMA_CTL_DMA_DONE)) return false;
    membar();                            // acquire DMA writes before accessing the cached frame buffer
    *len = (ctrl >> 16) & 0x3fff;
    *bi = r.slotBuf[r.tail];
    *data = r.buf.va + (size_t)*bi * MT_RX_BUF_SIZE;
    return true;
}

void itlmt7925::ringRelease(itl_ring &r, int bi)
{
    uint8_t *nd = r.desc.va + r.head * 16;
    put32(nd + 0, (uint32_t)(r.buf.pa + (uint64_t)bi * MT_RX_BUF_SIZE));
    put32(nd + 8, 0);
    put32(nd + 12, 0);
    put32(nd + 4, MT_DMA_CTL_SD_LEN0(MT_RX_BUF_SIZE));
    r.slotBuf[r.head] = (uint16_t)bi;
    r.head = (r.head + 1) % r.n;
    r.tail = (r.tail + 1) % r.n;
    membar();
    wr(r.regs + Q_CPU_IDX, (uint32_t)r.head);
}

// One-line snapshot of everything that could explain a silent firmware.
void itlmt7925::m2State(const char *tag)
{
    m2log("%s: lp=%08x misc=%08x dummy=%08x glo=%08x txwm cpu=%u dma=%u rxevt cpu=%u dma=%u tail=%d rxdat dma=%u evs=%u fwlog=%u",
          tag, rdA(MT_CONN_ON_LPCTL), rdA(MT_CONN_ON_MISC), rdA(MT_WFDMA_DUMMY_CR), rdA(MT_WFDMA0_GLO_CFG),
          rd(txWm.regs + Q_CPU_IDX), rd(txWm.regs + Q_DMA_IDX) & 0xffff, rd(rxEvt.regs + Q_CPU_IDX),
          rd(rxEvt.regs + Q_DMA_IDX) & 0xffff, rxEvt.tail, rxData.n ? rd(rxData.regs + Q_DMA_IDX) & 0xffff : 0, evCount,
          fwLogCnt);
}

// ---------------------------------------------------------------------------------------------
// UNI command: 48 byte txd (mt76_connac2_mcu_uni_txd) + payload on the WM ring, wait for the event with the same seq.
// evOut receives the whole event (rxd + payload), payload starting at offset 40.
// Scan results (beacons / probe responses) are delivered on the MCU event ring (ring 0) as 802.11 frame packets, not on the data
// ring (mt7925_queue_rx_skb: PKT_TYPE_NORMAL, sw_type FRAME, or RX_EVENT with flag 1 -> NORMAL_MCU).
static bool rxIsFrame(const uint8_t *p, uint32_t len)
{
    // enum rx_pkt_type: TXS 0, TXRXV 1, NORMAL 2, RX_DUP_RFB 3, RX_TMR 4, RETRIEVE 5, TXRX_NOTIFY 6, RX_EVENT 7, NORMAL_MCU 8
    if (len < 16) return false;
    uint32_t d0 = le32(p), type = d0 >> 27, flag = (d0 >> 16) & 0xf, sw = d0 >> 16;
    if (type != 2 && (sw & 0x380f) == 0x3801) return true;
    return type == 2 || type == 8 || (type == 7 && flag == 1);
}

// ---------------------------------------------------------------------------------------------
int itlmt7925::uniSend(uint8_t cid, const void *payload, size_t plen, bool query, uint8_t *evOut, size_t evMax,
                       uint32_t *evLen, uint32_t timeoutMs)
{
    if (48 + plen > 4096) return ITL_EINVAL;
    uint8_t seq = ++mcuSeq & 0xf;
    if (!seq) seq = ++mcuSeq & 0xf;

    uint8_t *p = txWm.buf.va;
    bzero(p, 48);
    uint32_t total = (uint32_t)(48 + plen);
    put32(p + 0, (total & 0xffff) | (2u << 23) | (0x20u << 25));    // TX_BYTES | PKT_FMT=CMD | Q_IDX=RX_Q0
    put32(p + 4, 1u << 14);                                          // HDR_FORMAT = CMD (connac3 layout: bits 15:14, mt76_connac3_mac.h)
    put16(p + 32, (uint16_t)(total - 32));                           // uni_txd->len
    put16(p + 34, cid);                                              // uni_txd->cid
    p[37] = MCU_PKT_ID;
    p[39] = seq;
    uint8_t opt = query ? (UNI_OPT_ACK | UNI_OPT_UNI) : (UNI_OPT_ACK | UNI_OPT_UNI | UNI_OPT_SET);
    if (cid == MCU_UNI_CHIP_CONFIG) opt &= ~UNI_OPT_ACK;            // HIF_CTRL / CHIP_CONFIG
    p[43] = opt;                                                     // s2d_index (p[42]) stays H2N = 0
    memcpy(p + 48, payload, plen);

    if (evLen) *evLen = 0;
    if (!txKick(txWm, total)) return ITL_TIMEOUT;

    itl_ring &r = rxEvt;
    for (uint32_t us = 0; us < timeoutMs * 1000; us += 50) {
        const uint8_t *ev; uint32_t len; int bi;
        while (ringPeek(r, &ev, &len, &bi)) {
            if (rxIsFrame(ev, len)) { rxPkts++; rxFrameDump(ev, len); rxParseFrame(ev, len); ringRelease(r, bi); continue; }
            bool match = len >= 44 && ev[37] == seq;
            evCount++;
            m3Event(ev, len);
            if (len >= 44 && ev[36] == 0x04) fwLogCnt++;
            if (len >= 44 && ev[36] != 0x04)    // eid 4 = firmware log, too chatty
                m2log("ev eid=%02x seq=%u len=%u%s", ev[36], ev[37], len, match ? " <match" : "");
            if (len >= 44 && ev[36] == UNI_EVENT_SCAN_DONE) scanDone = true;
            if (match && evOut && evMax) {
                uint32_t c = len > evMax ? (uint32_t)evMax : len;
                memcpy(evOut, ev, c);
                if (evLen) *evLen = c;
            }
            ringRelease(r, bi);
            if (match) return 0;
        }
        rxDataPoll();
        IODelay(50);
    }
    m2log("no response cid=%02x seq=%u", cid, seq);
    m2State("noresp");
    return ITL_TIMEOUT;
}

// ---------------------------------------------------------------------------------------------
// Beacon / probe response parsing
// ---------------------------------------------------------------------------------------------
// Where the 802.11 frame starts inside an RX buffer. The firmware prepends 32 bytes of RXD and then, depending on the flags
// in RXD1/RXD2, the optional groups: GROUP_4 (fc/seq), GROUP_1 (IV), GROUP_2 (timestamp), GROUP_3 (P-RXV) each 16 bytes,
// GROUP_5 (C-RXV, only with GROUP_3) another 24, plus RXD2.HDR_OFFSET (mt76_connac2_mac.h MT_RXD1_NORMAL_GROUP_*, and
// mt7925_mac_fill_rx(), which pulls exactly these). In station mode the firmware sends frames without any group, which is why
// a fixed offset of 32 was right for the data and beacon paths - but with the sniffer on, GROUP_4 shows up and a fixed 32
// lands on the group instead of the frame (docs/ROADMAP-AWDL.md §10.19).
static uint32_t rxHdrOff(const uint8_t *p, uint32_t len)
{
    if (len < 32) return len;
    uint32_t rxd1 = (uint32_t)p[4] | ((uint32_t)p[5] << 8) | ((uint32_t)p[6] << 16) | ((uint32_t)p[7] << 24);
    uint32_t rxd2 = (uint32_t)p[8] | ((uint32_t)p[9] << 8) | ((uint32_t)p[10] << 16) | ((uint32_t)p[11] << 24);
    uint32_t off = 32;
    if (rxd1 & (1u << 14)) off += 16;                       // GROUP_4
    if (rxd1 & (1u << 11)) off += 16;                       // GROUP_1
    if (rxd1 & (1u << 12)) off += 16;                       // GROUP_2
    if (rxd1 & (1u << 13)) {                                // GROUP_3
        off += 16;
        if (rxd1 & (1u << 15)) off += 24;                   // GROUP_5 (C-RXV)
    }
    off += 2 * ((rxd2 >> 14) & 3);                          // HDR_OFFSET, in 2-byte units (mt7925_mac_fill_rx: hdr_gap =
                                                            // rxd - skb->data + 2 * remove_pad)
    return off <= len ? off : 32;
}

// Searches a buffer for a byte pattern. Used by the AWDL RX forensics: the question "is there an AWDL frame in this buffer, and
// where" has to be answered by the content, not by a computed offset (docs/ROADMAP-AWDL.md §10.22).
static bool rxFind(const uint8_t *p, uint32_t len, const uint8_t *pat, uint32_t n, uint32_t *off)
{
    if (!p || len < n) return false;
    for (uint32_t i = 0; i + n <= len; i++) {
        if (memcmp(p + i, pat, n) == 0) { if (off) *off = i; return true; }
    }
    return false;
}

void itlmt7925::rxParseFrame(const uint8_t *p, uint32_t len)
{
    if (awdlRocActive) {                                     // diagnostics for the AWDL receive half (docs §10.13)
        awdlRocFrames++;
        if (p[13] == awdlRocCh) awdlRocOnCh++;               // RXD3 CH_FREQ says the radio really was on the parked channel
        if (awdlRxDumped < 6 && (awdlRocFrames <= 3 || (awdlRocFrames % 100) == 1)) {   // periodic, so the last one survives in the m3-log ring
            uint32_t o = rxHdrOff(p, len);
            if (o + 12 <= len) {
                awdlRxDumped++;
                m3log("awdl rx hdr off=%u rxd=%08x %08x %08x %08x | %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x (roc=%u)",
                      o, le32(p), le32(p + 4), le32(p + 8), le32(p + 12),
                      p[o], p[o + 1], p[o + 2], p[o + 3], p[o + 4], p[o + 5], p[o + 6], p[o + 7],
                      p[o + 8], p[o + 9], p[o + 10], p[o + 11], awdlRocFrames);
            }
        }
        // What the firmware actually hands the host inside a ROC window, by frame class. The question this answers is not
        // "did we hear an AWDL frame" but "does this firmware forward management frames from other devices at all" - if the
        // histogram is beacons and data only, no amount of AWDL work will ever see a peer.
        uint32_t hdr = rxHdrOff(p, len);
        uint8_t fcSeen = 0;
        bool haveFc = false;
        for (uint32_t off = hdr; off + 24 <= len && off < hdr + 8; off++) {
            uint8_t fc = p[off];
            if ((fc & 0x3) != 0 || p[off + 1] != 0) continue;            // protocol version 0, duration 0
            const uint8_t *a2 = p + off + 10;
            if ((a2[0] & 1) || !(a2[0] | a2[1] | a2[2] | a2[3] | a2[4] | a2[5])) continue;
            fcSeen = fc; haveFc = true;
            break;
        }
        if (haveFc && fcSeen == 0x80) { awdlBcn++; awdlRxFc[0]++; }
        else if (haveFc && ((fcSeen & 0xf0) == 0x40 || (fcSeen & 0xf0) == 0x50)) awdlRxFc[1]++;
        else if (haveFc && (fcSeen & 0x0c) == 0) awdlRxFc[fcSeen == 0xd0 ? 2 : 3]++;
        else awdlRxFc[4]++;

        // Forensics: does the buffer the firmware handed us contain an AWDL frame at all? The classifier above can only say
        // "some frame with fc 0xd0 arrived", which a false positive in a data payload also satisfies. These three patterns are
        // unambiguous: Apple's OUI (00:17:f2) anywhere, the AWDL action header (7f 00 17 f2 08) and AWDL's BSSID
        // (00:25:00:ff:94:73). If the OUI shows up but the header does not, the frame is there and the offset is wrong; if
        // neither shows up, the firmware is not delivering AWDL frames on this interface at all.
        {
            static const uint8_t kOui[3] = { 0x00, 0x17, 0xf2 };
            static const uint8_t kSig[5] = { 0x7f, 0x00, 0x17, 0xf2, 0x08 };
            static const uint8_t kBss[6] = { 0x00, 0x25, 0x00, 0xff, 0x94, 0x73 };
            uint32_t oOui = 0, oSig = 0, oBss = 0;
            bool hOui = rxFind(p, len, kOui, sizeof(kOui), &oOui);
            bool hSig = rxFind(p, len, kSig, sizeof(kSig), &oSig);
            bool hBss = rxFind(p, len, kBss, sizeof(kBss), &oBss);
            if (hOui) awdlOuiHits++;
            if (hSig) awdlSigHits++;
            if (hBss) awdlBssidHits++;
            if ((awdlForensics < 4 || (awdlRocFrames % 250) == 1) && (hOui || hSig || hBss || awdlForensics < 4)) {
                awdlForensics++;
                m3log("awdl rx fx len=%u hdr=%u oui=%u@%u sig=%u@%u bss=%u@%u", len, hdr, hOui ? 1 : 0, oOui,
                      hSig ? 1 : 0, oSig, hBss ? 1 : 0, oBss);
                char h1[3 * 24 + 1];
                uint32_t n1 = len - hdr; if (n1 > 24) n1 = 24;
                for (uint32_t i = 0; i < n1; i++) snprintf(h1 + i * 3, 4, "%02x ", p[hdr + i]);
                h1[n1 ? n1 * 3 - 1 : 0] = 0;
                m3log("awdl fx hdr@%u: %s", hdr, h1);
                if (hSig && oSig + 32 <= len) {
                    char h2[3 * 32 + 1];
                    for (uint32_t i = 0; i < 32; i++) snprintf(h2 + i * 3, 4, "%02x ", p[oSig + i]);
                    h2[32 * 3 - 1] = 0;
                    m3log("awdl fx sig@%u: %s", oSig, h2);
                }
            }
        }
    }
    if (txPool && len >= 8 && (le32(p) >> 27) == 6) { m3TxFree(p, len); return; }           // TXRX_NOTIFY: buffers the firmware is done with
    if (m3dataOn && m3RxData(p, len)) return;
    if (m3dataOn && lvl >= 1 && m3RxCtl(p, len)) return;                                     // Block Ack action frame / BlockAckReq
    if (m3wantFc && m3RxMgmt(p, len)) return;
    if ((m3linkUp || m3wantEapol) && len >= 32 + 26) {                  // deauthentication / disassociation from our AP: the link is gone
        for (uint32_t off = 32; off + 26 <= len && off < 160; off++) {
            uint8_t fc = p[off];
            if ((fc != 0xc0 && fc != 0xa0) || p[off + 1] != 0) continue;
            if (memcmp(p + off + 10, tgtBssid, 6) != 0 || memcmp(p + off + 16, tgtBssid, 6) != 0) continue;
            if (memcmp(p + off + 4, mac, 6) != 0 && !(p[off + 4] & 1)) continue;
            if (m3wantEapol) {
                m3hsApLeave = true;
                m3hsApReason = (uint16_t)(p[off + 24] | (p[off + 25] << 8));
                m3log("eapol AP %s reason=%u", fc == 0xc0 ? "deauthentication" : "disassociation", m3hsApReason);
                return;
            }
            snprintf(m3lostWhy, sizeof(m3lostWhy), "%s from the AP, reason %u", fc == 0xc0 ? "deauthentication" : "disassociation",
                     (unsigned)(p[off + 24] | (p[off + 25] << 8)));
            m3lost = true;
            return;
        }
    }
    // 802.11 mgmt header (24) + beacon fixed fields (12) + at least one IE; the frame sits after the RXD groups,
    // so look for "FC=beacon/probe-resp, addr2 == addr3" instead of decoding the group flags.
    // The scan path must keep the plain station-mode offset: this is the live link's scan/associate path and a frame that
    // is missed here costs the association (docs/ROADMAP-AWDL.md §10.20). Only the AWDL probes use rxHdrOff().
    if (len < 32 + 36 + 2) return;
    uint32_t chfreq = p[13];                           // RXD3 CH_FREQ
    for (uint32_t off = 32; off + 36 + 2 <= len && off < 160; off++) {
        uint8_t fc = p[off];
        if ((fc != 0x80 && fc != 0x50) || p[off + 1] != 0) continue;
        if (memcmp(p + off + 10, p + off + 16, 6) != 0) continue;     // TA == BSSID for an AP
        if (p[off + 10] & 1) continue;                                // not multicast
        if (fc == 0x80 && (p[off + 4] & p[off + 5] & p[off + 6] & p[off + 7] & p[off + 8] & p[off + 9]) != 0xff) continue;

        const uint8_t *ie = p + off + 36, *end = p + len;
        char ssid[33] = {0};
        uint8_t ch = 0;
        while (ie + 2 <= end && ie + 2 + ie[1] <= end) {
            uint8_t id = ie[0], l = ie[1];
            if (id == 0 && l <= 32) { memcpy(ssid, ie + 2, l); ssid[l] = 0; }
            else if (id == 3 && l >= 1) ch = ie[2];                   // DS parameter set
            else if (id == 61 && l >= 1 && !ch) ch = ie[2];           // HT operation: primary channel
            ie += 2 + l;
        }
        if (!ch) ch = (uint8_t)chfreq;
        for (int i = 0; i < (int)(sizeof(ssid)) && ssid[i]; i++)
            if (ssid[i] < 0x20 || ssid[i] > 0x7e) ssid[i] = '?';

        rxBeacons++;
        if (ch < sizeof(chHist)) chHist[ch]++;
        m3Capture(p + off, len - off, ssid, ch);
        apSeen(p, len, off, ssid, ch);
        return;
    }
    // Phase 3 RX probe (docs/ROADMAP-AWDL.md): management Action frames heard during the ROC window on the social channel.
    // An AWDL action frame is 24-byte header + the awdl_action prefix: category 0x7f, Apple OUI 00:17:f2, type 8, version 1.0,
    // subtype 0 (PSF) / 3 (MIF), then TLVs (OWL src/frame.h, and the Family's parser checks the same 0x17/0xf2/8). The header
    // is validated first because data frames contain 0xd0 too.
    // The frame is searched for by signature rather than by a computed offset: the sniffer buffer's layout (groups, padding)
    // is not yet pinned down, and a wrong offset silently discards every real AWDL frame. A match requires the full AWDL
    // signature, so group words and data frames cannot masquerade as action frames. The whole buffer is scanned, not just the
    // first 160 bytes: the sniffer adds RXD groups and the frame can sit behind them (docs/ROADMAP-AWDL.md §10.22).
    for (uint32_t off = 32; off + 40 <= len; off++) {
        if (p[off] != 0xd0 || p[off + 1] != 0) continue;
        const uint8_t *a1 = p + off + 4, *a2 = p + off + 10, *a3 = p + off + 16;
        if ((a1[0] & 1) && (a1[0] & a1[1] & a1[2] & a1[3] & a1[4] & a1[5]) != 0xff) continue;
        if ((a2[0] & 1) || !(a2[0] | a2[1] | a2[2] | a2[3] | a2[4] | a2[5])) continue;
        if ((a3[0] & 1) || !(a3[0] | a3[1] | a3[2] | a3[3] | a3[4] | a3[5])) continue;
        if (p[off + 2] != 0 || p[off + 3] != 0) continue;
        bool awdlAf = p[off + 24] == 0x7f && p[off + 25] == 0x00 && p[off + 26] == 0x17 && p[off + 27] == 0xf2 &&
                      p[off + 28] == 0x08;
        if (!awdlAf) {
            // A vendor-specific action frame that is not AWDL's: dump it, so a near miss can be recognised (a Block Ack request
            // from the AP, a vendor frame of the infra BSS, or an AWDL frame whose header is not where we think it is).
            awdlNearMiss++;
            if (awdlNearMiss <= 6) {
                char hex[3 * 40 + 1];
                uint32_t n = len - off; if (n > 40) n = 40;
                for (uint32_t i = 0; i < n; i++) snprintf(hex + i * 3, 4, "%02x ", p[off + i]);
                hex[n ? n * 3 - 1 : 0] = 0;
                m3log("awdl af near miss off=%u sa=%02x%02x%02x%02x%02x%02x %s", off, a2[0], a2[1], a2[2], a2[3], a2[4],
                      a2[5], hex);
            }
            continue;
        }
        awdlAfSeen++;
        {                                    // queued for the peer manager (the AWDL interface drains this ring)
            uint32_t head = awdlRxHead;
            if ((head - __atomic_load_n(&awdlRxTail, __ATOMIC_ACQUIRE)) < 4) {
                AwdlRxSlot &s = awdlRxRing[head & 3];
                uint32_t n = len - off; if (n > sizeof(s.data)) n = sizeof(s.data);
                memcpy(s.data, p + off, n);
                s.len = n;
                __atomic_store_n(&awdlRxHead, head + 1, __ATOMIC_RELEASE);
            }
        }
        if (awdlAfDumped < 10) {
            awdlAfDumped++;
            char hex[3 * 48 + 1];
            uint32_t n = len - off; if (n > 48) n = 48;
            for (uint32_t i = 0; i < n; i++) snprintf(hex + i * 3, 4, "%02x ", p[off + i]);
            hex[n ? n * 3 - 1 : 0] = 0;
            m3log("awdl af rx len=%u awdl=1 ch=%u cat=%02x type=%02x sub=%02x sa=%02x%02x%02x%02x%02x%02x %s",
                  len - off, awdlRocCh, p[off + 24], p[off + 28], p[off + 30],
                  a2[0], a2[1], a2[2], a2[3], a2[4], a2[5], hex);
        }
        return;
    }
    rxOther++;
    if (m3dataOn) szOther[szClass(len > 120 ? len - 120 : 0)]++;
}

void itlmt7925::rxFrameDump(const uint8_t *p, uint32_t len)
{
    if (rxDump >= 3) return;
    rxDump++;
    m2log("rxframe#%u len=%u d0=%08x d1=%08x d2=%08x d3=%08x pkt_type=%u", rxPkts, len, le32(p), le32(p + 4),
          len >= 12 ? le32(p + 8) : 0, len >= 16 ? le32(p + 12) : 0, le32(p) >> 27);
}

void itlmt7925::rxDataPoll()
{
    if (!rxData.n) return;
    const uint8_t *p; uint32_t len; int bi;
    int guard = 0;
    while (guard++ < 64 && ringPeek(rxData, &p, &len, &bi)) {
        rxPkts++;
        if (rxDump < 3) {
            rxDump++;
            m2log("rx#%u len=%u d0=%08x d1=%08x d2=%08x d3=%08x pkt_type=%u", rxPkts, len, le32(p), le32(p + 4),
                  len >= 12 ? le32(p + 8) : 0, len >= 16 ? le32(p + 12) : 0, le32(p) >> 27);
        }
        rxParseFrame(p, len);
        ringRelease(rxData, bi);
    }
    ethFlush();
}

void itlmt7925::m2Publish()
{
    size_t n = 0;
    m2res[0] = 0;
    n += (size_t)snprintf(m2res + n, sizeof(m2res) - n, "rx=%u bcn=%u oth=%u ap=%d sd=%d@%ums h:", rxPkts, rxBeacons, rxOther, nAps,
                  scanDone ? 1 : 0, scanMs);
    for (unsigned c = 0; c < sizeof(chHist) && n + 12 < sizeof(m2res); c++)
        if (chHist[c]) n += (size_t)snprintf(m2res + n, sizeof(m2res) - n, "%u=%u,", c, chHist[c]);
    n += (size_t)snprintf(m2res + n, sizeof(m2res) - n, ":");
    for (int i = 0; i < nAps && n + 40 < sizeof(m2res); i++)
        n += (size_t)snprintf(m2res + n, sizeof(m2res) - n, " %s/%u/%02x%02x", aps[i].ssid, aps[i].ch, aps[i].bssid[4],
                      aps[i].bssid[5]);
    setProperty("m2-res", m2res);
}

// Scan sequence
// ---------------------------------------------------------------------------------------------
int itlmt7925::m2Scan(const char *ssidArg)
{
    static uint8_t ev[512];
    uint32_t evl = 0;
    int rc;
    const uint8_t *e; uint32_t l; int bi;
    scanDone = false;
    bzero(chHist, sizeof(chHist));
    apGen++;                                              // this scan's generation: entries heard from now on carry it
    // SCAN_REQ: hdr{seq_num, bss_idx, pad[2]} + scan_req + ssid + bssid + channel + misc TLVs
    static uint8_t sc[4 + 20 + 368 + 16 + 136 + 12];
    bzero(sc, sizeof(sc));
    uint8_t *w = sc;
    w[0] = (uint8_t)(++scanSeq & 0x7f) | 0x80;                 // seq_num | band_idx << 7 (band_idx 0xff truncates to 0x80)
    w[1] = 0;                        // bss_idx
    w += 4;
    put16(w + 0, 1); put16(w + 2, 20);              // UNI_SCAN_REQ
    w[4] = 1;                                         // active scan
    w[5] = 2;                                         // probe_req_num
    w[6] = 1u << 5;                                   // SCAN_FUNC_SPLIT_SCAN
    put16(w + 8, 60);                                 // channel_min_dwell_time (ms): the firmware default (~35 ms) misses most beacons
    put16(w + 10, 120);                               // channel_dwell_time
    w += 20;
    put16(w + 0, 10); put16(w + 2, 368);            // UNI_SCAN_SSID
    if (ssidArg && ssidArg[0]) {                        // directed probe request
        w[4] = 1u << 2; w[5] = 1;                       // ssid_type: specific, ssids_num
        uint32_t sl = (uint32_t)strlen(ssidArg);
        put32(w + 8, sl);
        memcpy(w + 12, ssidArg, sl);
    } else w[4] = 1;                                    // ssid_type: wildcard
    w += 368;
    put16(w + 0, 11); put16(w + 2, 16);             // UNI_SCAN_BSSID
    memset(w + 4, 0xff, 6);
    w += 16;
    put16(w + 0, 12); put16(w + 2, 136);            // UNI_SCAN_CHANNEL
    // Every 2.4 GHz channel a network is commonly on (1..13 - 12/13 are the usual pick for routers outside the US), then the
    // complete 5 GHz set including the DFS bands (52..64 and 100..144). DFS was missing until round 27: the channel domain
    // (m3HwPrep) always allowed those channels, but the scan never visited them, so APs sitting on a DFS channel - the common
    // pick for 80 MHz in auto mode - never showed up in the Wi-Fi list. Whether the firmware probes passively on DFS with the
    // scan marked active is a hardware question (the TLV carries no per-channel flags; Linux's mt7925 sends the same shape).
    static const uint8_t chans[][2] = { {1, 1}, {1, 2}, {1, 3}, {1, 4}, {1, 5}, {1, 6}, {1, 7}, {1, 8}, {1, 9}, {1, 10}, {1, 11},
                                        {1, 12}, {1, 13},
                                        {2, 36}, {2, 40}, {2, 44}, {2, 48}, {2, 52}, {2, 56}, {2, 60}, {2, 64},
                                        {2, 100}, {2, 104}, {2, 108}, {2, 112}, {2, 116}, {2, 120}, {2, 124}, {2, 128},
                                        {2, 132}, {2, 136}, {2, 140}, {2, 144},
                                        {2, 149}, {2, 153}, {2, 157}, {2, 161}, {2, 165} };
    w[4] = 4;                                         // specified channels
    w[5] = sizeof(chans) / sizeof(chans[0]);
    for (unsigned i = 0; i < sizeof(chans) / sizeof(chans[0]); i++) { w[8 + 2 * i] = chans[i][0]; w[9 + 2 * i] = chans[i][1]; }
    w += 136;
    put16(w + 0, 14); put16(w + 2, 12);             // UNI_SCAN_MISC (random_mac left zero)
    rc = uniSend(MCU_UNI_SCAN_REQ, sc, sizeof(sc), false, ev, sizeof(ev), &evl, 3000);
    m2log("scan_req rc=%d status=%u cid=%02x", rc, evl >= 52 ? le32(ev + 48) : 0xdead, evl >= 41 ? ev[40] : 0);

    scanMs = 0;
    // 5. collect: events + beacons until SCAN_DONE (or 15 s)
    for (uint32_t ms = 0; ms < 15000; ms++) {
        rxDataPoll();
        while (ringPeek(rxEvt, &e, &l, &bi)) {
            if (rxIsFrame(e, l)) { rxPkts++; rxFrameDump(e, l); rxParseFrame(e, l); ringRelease(rxEvt, bi); continue; }
            if (l >= 44 && e[36] != 0x04 && evLogged++ < 12) m2log("ev eid=%02x seq=%u len=%u", e[36], e[37], l);
            if (l >= 44 && e[36] == UNI_EVENT_SCAN_DONE) scanDone = true;
            m3Event(e, l);
            ringRelease(rxEvt, bi);
        }
        if (scanDone && !scanMs) scanMs = ms;
        if (scanDone) {
            // a little extra time for beacons still in flight
            for (int i = 0; i < 300; i++) { rxDataPoll(); if (m3sleepy) IOSleep(1); else IODelay(1000); }
            break;
        }
        if ((ms % 1000) == 999) m2Publish();
        if (m3sleepy) IOSleep(1); else IODelay(1000);  // after the first link: sleep, do not spin a CPU for the whole scan
    }
    m2Publish();
    m2log("scan finished done=%d@%ums rx=%u bcn=%u aps=%d", scanDone ? 1 : 0, scanMs, rxPkts, rxBeacons, nAps);
    return rc;
}

// ---------------------------------------------------------------------------------------------
int itlmt7925::m2Run()
{
    static uint8_t ev[512];
    uint32_t evl = 0;
    int rc;

    m2log("armed");
    m2State("start");
    // flush anything that arrived while M1 finished
    for (int i = 0; i < 100; i++) { rxDataPoll(); IODelay(1000); }
    const uint8_t *e; uint32_t l; int bi;
    while (ringPeek(rxEvt, &e, &l, &bi)) {
        if (rxIsFrame(e, l)) { ringRelease(rxEvt, bi); continue; }
        if (l >= 44 && e[36] != 0x04) m2log("pre ev eid=%02x seq=%u len=%u", e[36], e[37], l);
        ringRelease(rxEvt, bi);
    }

    // 1. NIC capability -> MAC address
    uint8_t cap[8] = {0, 0, 0, 0, UNI_CHIP_CONFIG_NIC_CAPA, 0, 4, 0};      // rsv[4], tag, len(= sizeof - 4)
    rc = uniSend(MCU_UNI_CHIP_CONFIG, cap, sizeof(cap), false, ev, sizeof(ev), &evl, 3000);
    m2log("nic capa rc=%d evlen=%u", rc, evl);
    if (rc) {
        // second attempt: take driver ownership again and wait a moment, in case the firmware went to sleep
        bool own = driverOwn();
        IOSleep(1500);
        m2log("retry after driverOwn=%d", own ? 1 : 0);
        rc = uniSend(MCU_UNI_CHIP_CONFIG, cap, sizeof(cap), true, ev, sizeof(ev), &evl, 3000);   // option with ACK
        m2log("nic capa retry rc=%d evlen=%u", rc, evl);
    }
    bool gotMac = false;
    // The event is rxd (44 bytes) + {n_element, rsv[2]} + TLVs {tag, len, data}; try neighbouring bases in case the layout differs.
    static const uint8_t bases[3] = {44, 40, 48};
    for (int bi2 = 0; rc == 0 && !gotMac && bi2 < 3; bi2++) {
        const uint8_t *q = ev + bases[bi2];
        const uint8_t *end = ev + evl;
        if (q + 4 > end) continue;
        uint16_t n = (uint16_t)(q[0] | (q[1] << 8));
        q += 4;
        for (uint16_t i = 0; i < n && q + 4 <= end; i++) {
            uint16_t tag = (uint16_t)(q[0] | (q[1] << 8)), tl = (uint16_t)(q[2] | (q[3] << 8));
            if (tl < 4 || q + tl > end) break;
            if (tag == MT_NIC_CAP_MAC_ADDR && tl >= 10) { memcpy(mac, q + 4, 6); gotMac = true; }
            q += tl;
        }
        if (gotMac) m2log("nic capa base=%u n=%u", bases[bi2], n);
    }
    if (!gotMac && rc == 0)
        m2log("nic capa hex@40: %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x",
              ev[40], ev[41], ev[42], ev[43], ev[44], ev[45], ev[46], ev[47], ev[48], ev[49], ev[50], ev[51], ev[52], ev[53],
              ev[54], ev[55], ev[56], ev[57], ev[58], ev[59], ev[60], ev[61], ev[62], ev[63]);
    if (!gotMac) { static const uint8_t def[6] = {0x02, 0x11, 0x22, 0x33, 0x44, 0x55}; memcpy(mac, def, 6); }
    // Native interface: the firmware's own address is used when it is a usable unicast one (not zero, not group-addressed), and
    // it is published as IOMACAddress on this service for the native kext (the Ethernet front end that used to publish it is
    // disabled in native mode). Otherwise the locally administered placeholder of the earlier stages stays.
    if (nativeMode) {
        static const uint8_t nativeMac[6] = {0x02, 0x00, 0x79, 0x25, 0x00, 0x01};
        const bool zero = !(mac[0] | mac[1] | mac[2] | mac[3] | mac[4] | mac[5]);
        const bool usable = gotMac && !zero && !(mac[0] & 1);
        if (!usable) memcpy(mac, nativeMac, 6);
        // The Family sets the locally administered bit on the interface address (its "private address" step: dc:.. becomes
        // de:..) while setMacAddress is refused, so a globally unique address on air and the interface's one differ in that
        // bit alone: DHCP answers were addressed to the interface address, which no station on the AP has (joined, no data
        // back, only EAPOL ever received). Using the address with the bit already set makes the two the same.
        mac[0] |= 0x02;
        setProperty("IOMACAddress", mac, 6);
        setProperty("itlmt_mac_source", usable ? "firmware+LA" : "placeholder");
        publishService();                                    // the native kext matches now and reads IOMACAddress at start
    }
    m2log("mac=%02x:%02x:%02x:%02x:%02x:%02x%s", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], gotMac ? "" : " (default)");

    // 2. DEV_INFO_UPDATE: {omac_idx, band_idx, pad[2]} + {tag=0 (ACTIVE), len=12, active, link_idx, omac_addr}
    uint8_t dev[16];
    bzero(dev, sizeof(dev));
    dev[0] = 0; dev[1] = 0xff;
    put16(dev + 4, 0); put16(dev + 6, 12);
    dev[8] = 1; dev[9] = 0;
    memcpy(dev + 10, mac, 6);
    rc = uniSend(MCU_UNI_DEV_INFO_UPDATE, dev, sizeof(dev), false, ev, sizeof(ev), &evl, 3000);
    m2log("dev_info rc=%d status=%u cid=%02x", rc, evl >= 52 ? le32(ev + 48) : 0xdead, evl >= 41 ? ev[40] : 0);

    // 3. BSS_INFO_UPDATE basic: {bss_idx, pad[3]} + mt76_connac_bss_basic_tlv (32 bytes)
    uint8_t bss[4 + 32];
    bzero(bss, sizeof(bss));
    uint8_t *b = bss + 4;
    put16(b + 0, 0);                 // tag UNI_BSS_INFO_BASIC
    put16(b + 2, 32);                // len
    b[4] = 1;                        // active
    b[5] = 0;                        // omac_idx
    b[6] = 0;                        // hw_bss_idx
    b[7] = 0xff;                     // band_idx
    put32(b + 8, 0x10001);           // CONNECTION_INFRA_STA
    b[12] = 1;                       // conn_state
    b[13] = 0;                       // wmm_idx
    put16(b + 20, 19);               // bmc_tx_wlan_idx = WTBL_RESERVED
    put16(b + 26, 19);               // sta_idx
    b[31] = 0;                       // link_idx
    rc = uniSend(MCU_UNI_BSS_INFO_UPDATE, bss, sizeof(bss), false, ev, sizeof(ev), &evl, 3000);
    m2log("bss_info rc=%d status=%u cid=%02x", rc, evl >= 52 ? le32(ev + 48) : 0xdead, evl >= 41 ? ev[40] : 0);

    if (m3On) m3HwPrep();            // channel domain must be known to the firmware before it scans (Linux sends it at start)
    rc = m2Scan(nullptr);
    return rc;
}
