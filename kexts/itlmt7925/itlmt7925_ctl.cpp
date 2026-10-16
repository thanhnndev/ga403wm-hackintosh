// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925 - run-time control and data-path measurements for A/B tests inside one boot (tools/itlctl.c, tools/itl-ab.sh).
//
//  * setProperties(): administrator only (IORegistryEntrySetCFProperties). Requests are only recorded here; the link loop takes
//    them (ctlPoll), because they send MCU commands or tear the link down.
//        itl_lvl   1..6   reconnect at exactly that fast level (the AP's own limits still apply; lvlCap is not touched)
//        itl_no160 0/1    run 160 MHz channels as 80 MHz (takes effect with the reconnect)
//        itl_reo   5..500 Block Ack reorder timeout in ms (immediate)
//        itl_pwr   1..127 send the CLC + SKU power tables now, per-rate ceiling in 0.5 dBm (40 = 20 dBm)
//  * tsSample(): one line per second of the data path (ts-log) and the size-class counters (rx-log): where large frames go.
#include "itlmt7925.hpp"

#include <IOKit/IOUserClient.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <string.h>
#include <kern/task.h>

static bool ctlNum(OSDictionary *d, const char *key, uint32_t *v)
{
    OSNumber *n = OSDynamicCast(OSNumber, d->getObject(key));
    if (!n) return false;
    *v = n->unsigned32BitValue();
    return true;
}

IOReturn itlmt7925::setProperties(OSObject *props)
{
    OSDictionary *d = OSDynamicCast(OSDictionary, props);
    if (!d) return kIOReturnBadArgument;
    if (IOUserClient::clientHasPrivilege(current_task(), kIOClientPrivilegeAdministrator) != kIOReturnSuccess)
        return kIOReturnNotPrivileged;
    uint32_t v = 0;
    char log[96];
    log[0] = 0;
    if (ctlNum(d, "itl_no160", &v)) {
        no160 = v != 0;
        snprintf(log + strlen(log), sizeof(log) - strlen(log), "no160=%u ", v != 0);
    }
    if (ctlNum(d, "itl_amsdu", &v)) {
        noAmsdu = v == 0;
        snprintf(log + strlen(log), sizeof(log) - strlen(log), "amsdu=%u ", v != 0);
    }
    if (ctlNum(d, "itl_reo", &v) && v >= 5 && v <= 500) {
        reoMs = v;
        snprintf(log + strlen(log), sizeof(log) - strlen(log), "reo=%u ", v);
    }
    if (ctlNum(d, "itl_pwr", &v) && v >= 1 && v <= 127) {
        pwrCeil = (uint8_t)v;
        ctlPwr = v;
        snprintf(log + strlen(log), sizeof(log) - strlen(log), "pwr=%u ", v);
    }
    if (ctlNum(d, "itl_lvl", &v) && v >= 1 && v <= 6) {
        if (v > fastLevel) v = fastLevel;                    // the boot-arg is the ceiling (ring sizes depend on it)
        if (v) {
            lvlForce = (uint8_t)v;
            ctlLvl = v;
            snprintf(log + strlen(log), sizeof(log) - strlen(log), "lvl=%u ", v);
        }
    }
    if (!log[0]) return kIOReturnBadArgument;
    evLog("ctl: %s", log);
    return kIOReturnSuccess;
}

// Link loop: take the requests recorded by setProperties().
void itlmt7925::ctlPoll()
{
    uint32_t p = ctlPwr;
    if (p) {
        ctlPwr = 0;
        clcCc[0] = 0;                                        // m3PowerSetup sends the CLC tables again as well
        m3PowerSetup();
        evLog("ctl: power tables sent, ceiling %u rc=%s", p, clcCc[0] ? "ok" : "failed");
    }
    uint32_t l = ctlLvl;
    if (l) {
        ctlLvl = 0;
        m3stepDown = m3stepRadio = true;                     // m3Run() reconnects at lvlForce; the cap for this network stays
        evLog("ctl: leaving level %u for %u", lvl, l);
    }
}

// One sample per second of the counters that say where the throughput goes, and the size-class table.
void itlmt7925::tsSample(uint32_t now)
{
    if (now - tsLastMs < 1000) return;
    tsLastMs = now;
    uint32_t ri = 0, ro = 0, rt = 0;
    for (int t = 0; t < 8; t++) { ri += rxBa[t].r.nIn; ro += rxBa[t].r.nOld; rt += rxBa[t].r.nTimeout; }
    (void)ri;
    const uint32_t cur[7] = { stRxEth, rxPkts, stTx, stTxFwRetry, stTxNoSlot, ro, rt };
    uint32_t *row = tsRing[tsHead % kTsN];
    for (int i = 0; i < 7; i++) row[i] = cur[i] - tsPrev[i], tsPrev[i] = cur[i];
    tsHead++;

    static char ts[kTsN * 40 + 8];
    size_t n = 0;
    uint32_t cnt = tsHead < kTsN ? tsHead : kTsN;
    for (uint32_t k = 0; k < cnt && n + 40 < sizeof(ts); k++) {
        const uint32_t *r = tsRing[(tsHead - cnt + k) % kTsN];
        n += (size_t)snprintf(ts + n, sizeof(ts) - n, "%u,%u,%u,%u,%u,%u,%u;", r[0], r[1], r[2], r[3], r[4], r[5], r[6]);
    }
    if (n >= sizeof(ts)) n = sizeof(ts) - 1;
    ts[n] = 0;
    setProperty("ts-log", ts);                               // eth,ring,tx,fwretry,noslot,old,timeout per second, oldest first

    char s[640];
    snprintf(s, sizeof(s),
             "ring=%u/%u/%u/%u/%u/%u parsed=%u/%u/%u/%u/%u/%u deliv=%u/%u/%u/%u/%u/%u other=%u/%u/%u/%u/%u/%u echo>=1000B rx=%u/%u tx=%u lvl=%u no160=%u pwr=%u"
             " noam=%u ai=%u/%u/%u/%u subs=%u/%u/%u/%u/%u ovf=%u bigdrop=%u",
             szRing[0], szRing[1], szRing[2], szRing[3], szRing[4], szRing[5],
             szParsed[0], szParsed[1], szParsed[2], szParsed[3], szParsed[4], szParsed[5],
             szDeliv[0], szDeliv[1], szDeliv[2], szDeliv[3], szDeliv[4], szDeliv[5],
             szOther[0], szOther[1], szOther[2], szOther[3], szOther[4], szOther[5],
             icmpRepParsed, icmpRepDeliv, icmpReqTx, lvl, no160 ? 1 : 0, clcCc[0] ? pwrCeil : 0,
             noAmsdu ? 1 : 0, stAmsduAi[0], stAmsduAi[1], stAmsduAi[2], stAmsduAi[3],
             stAmsduN[0], stAmsduN[1], stAmsduN[2], stAmsduN[3], stAmsduN[4], stBundleOvf, stRxBigDrop);
    setProperty("rx-log", s);
}
