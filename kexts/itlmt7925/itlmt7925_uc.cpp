// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925 - runtime control: a user client (scan / join / disconnect, ABI in itl_uc_abi.h), the supervisor loop that owns
// the connection after M2, and the registry properties the menu bar app reads (wifi-*).
//
// Threading: everything that touches the chip runs on the single worker thread (m1Main -> m3Supervise). The user client only
// writes the command mailbox under cmdLock; the worker takes the commands between steps. Nothing here sleeps in the
// user client's context.
#include "itlmt7925.hpp"
#include "itl_uc_abi.h"

#include <IOKit/IOUserClient.h>
#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>
#include <stdarg.h>
#include <string.h>

enum { ITL_SEC_OPEN, ITL_SEC_WEP, ITL_SEC_WPA, ITL_SEC_WPA2, ITL_SEC_WPA23, ITL_SEC_WPA3, ITL_SEC_ENT };
static const char *const kSecName[] = { "open", "wep", "wpa", "wpa2", "wpa2/wpa3", "wpa3", "enterprise" };

static inline uint32_t le32p(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }

// ---------------------------------------------------------------------------------------------------------------------------
// User client
// ---------------------------------------------------------------------------------------------------------------------------
class itlmt7925UC : public IOUserClient {
    OSDeclareDefaultStructors(itlmt7925UC)

public:
    bool initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args, IOExternalMethodDispatch *dispatch,
                            OSObject *target, void *reference) override;

private:
    itlmt7925 *drv = nullptr;
    bool allowed = false;
};

#define super IOUserClient
OSDefineMetaClassAndStructors(itlmt7925UC, IOUserClient)

bool itlmt7925UC::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties)
{
    if (!super::initWithTask(owningTask, securityToken, type, properties)) return false;
    // Like the system Wi-Fi menu: root, or the user logged in at the console. A remote (ssh) session of another user is refused.
    allowed = clientHasPrivilege(owningTask, kIOClientPrivilegeAdministrator) == kIOReturnSuccess ||
              clientHasPrivilege(owningTask, kIOClientPrivilegeLocalUser) == kIOReturnSuccess;
    return true;
}

bool itlmt7925UC::start(IOService *provider)
{
    drv = OSDynamicCast(itlmt7925, provider);
    return drv && super::start(provider);
}

IOReturn itlmt7925UC::clientClose()
{
    terminate();
    return kIOReturnSuccess;
}

IOReturn itlmt7925UC::externalMethod(uint32_t selector, IOExternalMethodArguments *a, IOExternalMethodDispatch *,
                                     OSObject *, void *)
{
    if (!drv || !a) return kIOReturnNotAttached;
    if (!allowed) return kIOReturnNotPrivileged;
    switch (selector) {
    case kItlUcScan:
        return drv->ucScan();
    case kItlUcDisconnect:
        return drv->ucDisconnect();
    case kItlUcJoin: {
        if (a->structureInputSize != sizeof(itl_uc_join) || !a->structureInput) return kIOReturnBadArgument;
        itl_uc_join j;
        memcpy(&j, a->structureInput, sizeof(j));
        IOReturn r = kIOReturnBadArgument;
        size_t sl = strnlen(j.ssid, sizeof(j.ssid)), pl = strnlen(j.psk, sizeof(j.psk));
        if (j.abi == ITL_UC_ABI_VERSION && sl >= 1 && sl <= 32 && pl >= 8 && pl <= 63) r = drv->ucJoin(j.ssid, j.psk);
        bzero(&j, sizeof(j));
        return r;
    }
    default:
        return kIOReturnUnsupported;
    }
}

#undef super

IOReturn itlmt7925::newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                                  IOUserClient **handler)
{
    if (!handler) return kIOReturnBadArgument;
    // Exclusive native datapath owns radio policy; legacy menu app must not
    // send scan/join/disconnect commands behind IO80211's back.
    if (nativeMode) { *handler = nullptr; return kIOReturnUnsupported; }
    itlmt7925UC *uc = OSTypeAlloc(itlmt7925UC);
    if (!uc) return kIOReturnNoMemory;
    if (!uc->initWithTask(owningTask, securityID, type, properties)) { uc->release(); return kIOReturnError; }
    if (!uc->attach(this)) { uc->release(); return kIOReturnError; }
    if (!uc->start(this)) { uc->detach(this); uc->release(); return kIOReturnError; }
    *handler = uc;
    return kIOReturnSuccess;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Command mailbox (user client side: never blocks on the chip)
// ---------------------------------------------------------------------------------------------------------------------------
IOReturn itlmt7925::ucScan()
{
    if (!m3On || !cmdLock || !wstate[0]) return kIOReturnNotReady;
    IOLockLock(cmdLock);
    uint32_t now = nowMs();
    IOReturn r = kIOReturnSuccess;
    if (lastScanReqMs && now - lastScanReqMs < 10000) r = kIOReturnBusy;     // a scan takes the radio off the AP's channel
    else { lastScanReqMs = now ? now : 1; cmdBits |= CMD_SCAN; }
    IOLockUnlock(cmdLock);
    return r;
}

IOReturn itlmt7925::ucJoin(const char *ssid, const char *psk)
{
    if (!m3On || !cmdLock || !wstate[0]) return kIOReturnNotReady;
    IOLockLock(cmdLock);
    strlcpy(reqNet.ssid, ssid, sizeof(reqNet.ssid));
    strlcpy(reqNet.psk, psk, sizeof(reqNet.psk));
    cmdBits = (cmdBits & ~(uint32_t)CMD_DISCONNECT) | (uint32_t)CMD_JOIN;
    IOLockUnlock(cmdLock);
    return kIOReturnSuccess;
}

IOReturn itlmt7925::ucDisconnect()
{
    if (!m3On || !cmdLock || !wstate[0]) return kIOReturnNotReady;
    IOLockLock(cmdLock);
    cmdBits = (cmdBits & ~(uint32_t)CMD_JOIN) | (uint32_t)CMD_DISCONNECT;
    bzero(&reqNet, sizeof(reqNet));
    IOLockUnlock(cmdLock);
    return kIOReturnSuccess;
}

// Takes the commands in `mask` out of the mailbox; a join also hands over (and wipes) its network.
uint32_t itlmt7925::cmdTake(uint32_t mask, Net *join)
{
    if (!cmdLock) return 0;
    IOLockLock(cmdLock);
    uint32_t got = cmdBits & mask;
    cmdBits &= ~got;
    if (got & CMD_JOIN) {
        if (join) *join = reqNet;
        bzero(&reqNet, sizeof(reqNet));
    }
    IOLockUnlock(cmdLock);
    return got;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Status for user space
// ---------------------------------------------------------------------------------------------------------------------------
static void setNum(IOService *s, const char *key, long long v)
{
    OSNumber *n = OSNumber::withNumber((unsigned long long)v, 32);
    if (n) { s->setProperty(key, n); n->release(); }
}

void itlmt7925::wifiState(const char *st, const char *err)
{
    strlcpy(wstate, st, sizeof(wstate));
    setProperty("wifi-state", st);
    if (err) setProperty("wifi-error", err);
}

// wifi-events: what happened to the link and why, with seconds since boot. The kext's IOLog output does not reach dmesg or the
// unified log on this machine, and m3-log / ba-log are overwritten by the next attempt, so this is the history to read after a
// flaky session: ioreg -rc itlmt7925 -l | grep wifi-events
void itlmt7925::evLog(const char *fmt, ...)
{
    char line[160];
    int n = snprintf(line, sizeof(line), "%us ", nowMs() / 1000);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line + n, sizeof(line) - (size_t)n, fmt, ap);
    va_end(ap);
    size_t len = strlen(line);
    while (evlen && evlen + len + 2 > sizeof(evbuf)) {          // drop the oldest lines until the new one fits
        size_t cut = 0;
        while (cut < evlen && evbuf[cut] != '\n') cut++;
        if (cut < evlen) cut++;
        memmove(evbuf, evbuf + cut, evlen - cut);
        evlen -= cut;
    }
    memcpy(evbuf + evlen, line, len);
    evlen += len;
    evbuf[evlen++] = '\n';
    evbuf[evlen] = 0;
    setProperty("wifi-events", evbuf);
}

void itlmt7925::wifiLink()
{
    setProperty("wifi-ssid", m3ssid);
    setNum(this, "wifi-channel", tgtCh);
    setNum(this, "wifi-rssi", tgtRssi);
    setNum(this, "wifi-rate", fastActive ? fastRate : 54);
}

void itlmt7925::wifiNets()
{
    uint32_t now = nowMs();
    OSArray *arr = OSArray::withCapacity((unsigned)nAps);
    if (!arr) return;
    for (int i = 0; i < nAps; i++) {
        const itl_ap &a = aps[i];
        if (!a.ssid[0] || now - a.seenMs > 180000) continue;                // hidden networks, and anything not seen for 3 min
        OSDictionary *d = OSDictionary::withCapacity(5);
        OSString *ss = OSString::withCString(a.ssid);
        OSString *sc = OSString::withCString(kSecName[a.sec < 7 ? a.sec : 0]);
        OSNumber *ch = OSNumber::withNumber(a.ch, 32);
        OSNumber *rs = OSNumber::withNumber((unsigned long long)(long long)a.rssi, 32);
        OSNumber *ag = OSNumber::withNumber((now - a.seenMs) / 1000, 32);
        if (d && ss && sc && ch && rs && ag) {
            d->setObject("ssid", ss); d->setObject("security", sc); d->setObject("channel", ch);
            d->setObject("rssi", rs); d->setObject("age", ag);
            arr->setObject(d);
        }
        if (ag) ag->release();
        if (rs) rs->release();
        if (ch) ch->release();
        if (sc) sc->release();
        if (ss) ss->release();
        if (d) d->release();
    }
    setProperty("wifi-networks", arr);
    arr->release();
    setNum(this, "wifi-scan-gen", scanGen);
}

void itlmt7925::wifiScan()
{
    __atomic_store_n(&scanBusy, 1, __ATOMIC_RELEASE);
    wifiState("scanning", nullptr);
    m2Scan(nullptr);
    scanGen++;
    wifiNets();
    __atomic_store_n(&scanBusy, 0, __ATOMIC_RELEASE);
}

// ---------------------------------------------------------------------------------------------------------------------------
// Native Wi-Fi control (platform functions of itlmt7925_eth.cpp, called by the interface of itlmt7925Native)
// ---------------------------------------------------------------------------------------------------------------------------
IOReturn itlmt7925::nativeScanReq(uint32_t *started)
{
    *started = 0;
    if (!m3On || !cmdLock || !wstate[0]) return kIOReturnNotReady;
    IOLockLock(cmdLock);
    uint32_t now = nowMs();
    if ((cmdBits & CMD_SCAN) || __atomic_load_n(&scanBusy, __ATOMIC_ACQUIRE)) *started = 1;      // join the queued / running scan
    else if (lastScanReqMs && now - lastScanReqMs < 10000) *started = 0;                          // cache is current: caller delivers it
    else {
        lastScanReqMs = now ? now : 1;
        cmdBits |= CMD_SCAN;
        __atomic_store_n(&scanBusy, 1, __ATOMIC_RELEASE);
        *started = 1;
    }
    IOLockUnlock(cmdLock);
    return kIOReturnSuccess;
}

IOReturn itlmt7925::nativeJoin(const ItlNativeJoin *j)
{
    if (!m3On || !cmdLock || !wstate[0]) return kIOReturnNotReady;
    if (!j || j->version != 1 || !j->ssidLen || j->ssidLen > 32) return kIOReturnBadArgument;
    IOLockLock(cmdLock);
    bzero(&reqNet, sizeof(reqNet));
    memcpy(reqNet.ssid, j->ssid, j->ssidLen);
    memcpy(reqNet.pmk, j->pmk, sizeof(reqNet.pmk));
    reqNet.hasPmk = true;
    reqNet.native = true;
    njFail = 0;
    njState = ITL_NATIVE_CONNECTING;
    njSeq++;
    cmdBits = (cmdBits & ~(uint32_t)CMD_DISCONNECT) | (uint32_t)CMD_JOIN;
    IOLockUnlock(cmdLock);
    return kIOReturnSuccess;
}

// Whole elements only, at most `max` bytes.
static uint16_t ieWhole(const uint8_t *ie, uint32_t len, uint32_t max)
{
    uint32_t n = 0;
    while (n + 2 <= len && n + 2 + ie[n + 1] <= len && n + 2 + ie[n + 1] <= max) n += 2 + ie[n + 1];
    return (uint16_t)n;
}

static uint32_t failCode(const char *stage)
{
    if (!strncmp(stage, "nocred", 6)) return 1;
    if (!strncmp(stage, "scan", 4)) return 2;
    if (!strncmp(stage, "roc-fail", 8)) return 3;
    if (!strncmp(stage, "auth-fail", 9)) return 4;
    if (!strncmp(stage, "assoc-fail", 10)) return 5;
    if (!strncmp(stage, "hs-fail", 7)) return 6;
    return 7;
}

void itlmt7925::nativeStatus(ItlNativeStatus *s)
{
    bzero(s, sizeof(*s));
    s->version = 1;
    uint32_t st = njState;
    // a join in progress hides an old link that is still being torn down
    s->state = st == ITL_NATIVE_CONNECTING ? ITL_NATIVE_CONNECTING
             : m3linkUp ? ITL_NATIVE_UP
             : st == ITL_NATIVE_FAILED ? ITL_NATIVE_FAILED : ITL_NATIVE_IDLE;
    s->joinSeq = njSeq;
    s->failStage = njFail;
    s->scanGen = scanGen;
    s->scanBusy = __atomic_load_n(&scanBusy, __ATOMIC_ACQUIRE);
    memcpy(s->bssid, tgtBssid, 6);
    s->channel = tgtCh;
    s->rssi = tgtRssi;
    s->rateMbps = fastActive ? fastRate : 54;
    size_t n = strnlen(m3ssid, 32);
    memcpy(s->ssid, m3ssid, n);
    s->ssidLen = (uint8_t)n;
    s->capability = tgtCap;
    s->beaconInterval = tgtBcnInt;
    s->beaconCount = tgtBcnCount;
    uint32_t il = tgtIeLen < sizeof(tgtIe) ? tgtIeLen : (uint32_t)sizeof(tgtIe);
    s->ieLen = ieWhole(tgtIe, il, ITL_NATIVE_IE_MAX);
    memcpy(s->ie, tgtIe, s->ieLen);
    // negotiated sets (apCaps is parsed when the fast plan is made, itlmt7925_m3.cpp m3FastPlan)
    s->fastActive = (fastActive && m3linkUp) ? 1 : 0;
    s->fastNss = 0;
    s->fastHe = 0;
    s->fastBw = 0;
    bzero(s->htMcs, sizeof(s->htMcs));
    s->vhtMcs = s->heMcs = 0xffff;
    if (s->fastActive) {
        const uint8_t nss = fastNss > ITL_CAPS_MAX_NSS ? (uint8_t)ITL_CAPS_MAX_NSS : fastNss;
        s->fastNss = nss;
        s->fastHe = fastHe ? 1 : 0;
        s->fastBw = fastBw;
        if (apCaps.ht)
            for (uint8_t i = 0; i < nss && i < 10; i++) s->htMcs[i] = apCaps.mcsRx[i];
        if (apCaps.vht) {
            uint16_t m = 0xffff;
            for (uint8_t ss = 0; ss < nss; ss++) {
                const uint16_t v = (apCaps.vhtRxMcs >> (2 * ss)) & 3;
                m = (uint16_t)((m & ~(3u << (2 * ss))) | (v << (2 * ss)));
            }
            s->vhtMcs = m;
        }
        if (fastHe && apCaps.he) {
            uint16_t m = 0xffff;
            for (uint8_t ss = 0; ss < nss; ss++) {
                const uint16_t v = (apCaps.heRx80 >> (2 * ss)) & 3;
                m = (uint16_t)((m & ~(3u << (2 * ss))) | (v << (2 * ss)));
            }
            s->heMcs = m;
        }
    }
}

void itlmt7925::nativeNets(ItlNativeNets *out)
{
    out->version = 1;
    out->count = 0;
    out->scanGen = scanGen;
    out->scanBusy = __atomic_load_n(&scanBusy, __ATOMIC_ACQUIRE);
    if (!out->aps) return;
    uint32_t now = nowMs();
    int total = nAps;
    for (int i = 0; i < total && out->count < out->max && i < ITL_NATIVE_AP_MAX; i++) {
        const itl_ap &a = aps[i];
        ItlNativeAp &o = out->aps[out->count];
        bzero(&o, sizeof(o));
        memcpy(o.bssid, a.bssid, 6);
        o.channel = a.ch;
        o.security = a.sec;
        o.rssi = a.rssi;
        size_t n = strnlen(a.ssid, 32);
        memcpy(o.ssid, a.ssid, n);
        o.ssidLen = (uint8_t)n;
        o.probeResponse = a.probe;
        o.capability = a.cap;
        o.beaconInterval = a.bcnInt;
        o.ieLen = a.ieLen <= ITL_NATIVE_IE_MAX ? a.ieLen : 0;
        memcpy(o.ie, a.ie, o.ieLen);
        o.ageMs = now - a.seenMs;
        out->count++;
    }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Beacon / probe response bookkeeping: signal and security of every AP (called by rxParseFrame)
// ---------------------------------------------------------------------------------------------------------------------------
// Signal from the RX vector (RXD group 3). The 802.11 header was located by pattern at `hdrOff`. Group bits in RXD1 (bit 16 up:
// 1, 2, 3, 4, 5, seen on hardware: d1=0x80070001 for a data frame with the header at byte 86). Group order after the 32-byte
// base: 4 (16), 1 (16), 2 (8 or 16), 3 = RX vector (16), 5 (96); the header follows with up to 16 bytes of padding. A layout is
// only used if the header sits there, and a value only if every chain's RCPI gives a plausible, consistent dBm; otherwise
// the signal is "unknown" (0). The first samples go to the registry (rssi-probe) to pin the layout down.
int8_t itlmt7925::rxRssi(const uint8_t *p, uint32_t len, uint32_t hdrOff)
{
    if (len < 36) return 0;
    uint32_t d1 = le32p(p + 4);
    if (rssiProbeN < 4 && ((d1 >> 18) & 1) && hdrOff + 4 <= len) {
        size_t n = strlen(rssiProbe);
        n += (size_t)snprintf(rssiProbe + n, sizeof(rssiProbe) - n, "%sd1=%08x d2=%08x hdr@%u:", rssiProbeN ? " | " : "", d1,
                              le32p(p + 8), hdrOff);
        for (uint32_t o = 32; o < hdrOff && o < 112 && n + 3 < sizeof(rssiProbe); o++)
            n += (size_t)snprintf(rssiProbe + n, sizeof(rssiProbe) - n, "%02x", p[o]);
        rssiProbeN++;
        setProperty("rssi-probe", rssiProbe);
    }
    static const uint8_t g1bit[2] = { 16, 11 }, g2len[2] = { 8, 16 }, dw[2] = { 3, 1 };
    for (int h = 0; h < 2; h++) {
        uint32_t b = g1bit[h];
        bool g1 = (d1 >> b) & 1, g2 = (d1 >> (b + 1)) & 1, g3 = (d1 >> (b + 2)) & 1, g4 = (d1 >> (b + 3)) & 1,
             g5 = (d1 >> (b + 4)) & 1;
        if (!g3) continue;
        for (int L = 0; L < 2; L++) {
            uint32_t rxv = 32 + (g4 ? 16 : 0) + (g1 ? 16 : 0) + (g2 ? g2len[L] : 0);
            uint32_t end = rxv + 16 + (g5 ? 96 : 0);
            if (hdrOff < end || hdrOff > end + 16 || rxv + 16 > len) continue;
            for (int k = 0; k < 2; k++) {
                const uint8_t *r = p + rxv + 4 * dw[k];
                int best = -128, n = 0, lo = 0, hi = -128;
                for (int c = 0; c < 4; c++) {
                    if (r[c] == 0 || r[c] == 255) continue;
                    int dbm = ((int)r[c] - 220) / 2;
                    if (dbm < -100 || dbm > -5) { n = -1; break; }
                    if (dbm > best) best = dbm;
                    if (!n || dbm < lo) lo = dbm;
                    if (dbm > hi) hi = dbm;
                    n++;
                }
                if (n > 0 && hi - lo <= 25) return (int8_t)best;
            }
        }
    }
    return 0;
}

static uint8_t secFromIes(const uint8_t *ie, const uint8_t *end, uint16_t cap)
{
    bool rsn = false, wpa = false, psk = false, sae = false, eap = false;
    while (ie + 2 <= end && ie + 2 + ie[1] <= end) {
        uint8_t id = ie[0], l = ie[1];
        const uint8_t *v = ie + 2;
        if (id == 48 && l >= 8) {
            rsn = true;
            uint32_t pc = (uint32_t)(v[6] | (v[7] << 8)), o = 8 + 4 * pc;
            if (o + 2 <= l) {
                uint32_t ac = (uint32_t)(v[o] | (v[o + 1] << 8));
                for (uint32_t i = 0; i < ac && o + 2 + 4 * i + 4 <= l; i++) {
                    const uint8_t *s = v + o + 2 + 4 * i;
                    if (s[0] != 0x00 || s[1] != 0x0f || s[2] != 0xac) continue;
                    if (s[3] == 2 || s[3] == 6) psk = true;
                    else if (s[3] == 8 || s[3] == 24) sae = true;
                    else if (s[3] == 1 || s[3] == 5) eap = true;
                }
            }
        } else if (id == 221 && l >= 4 && v[0] == 0x00 && v[1] == 0x50 && v[2] == 0xf2 && v[3] == 1) {
            wpa = true;
        }
        ie += 2 + l;
    }
    if (rsn) {
        if (psk && sae) return ITL_SEC_WPA23;
        if (psk) return ITL_SEC_WPA2;
        if (sae) return ITL_SEC_WPA3;
        if (eap) return ITL_SEC_ENT;
        return ITL_SEC_WPA2;
    }
    if (wpa) return ITL_SEC_WPA;
    return (cap & 0x10) ? ITL_SEC_WEP : ITL_SEC_OPEN;
}

void itlmt7925::apSeen(const uint8_t *p, uint32_t len, uint32_t off, const char *ssid, uint8_t ch)
{
    const uint8_t *f = p + off;
    const uint8_t *bssid = f + 16;
    uint32_t now = nowMs();
    int8_t rssi = rxRssi(p, len, off);
    if (m3linkUp && !memcmp(bssid, tgtBssid, 6)) {
        tgtLastBcnMs = now ? now : 1;
        tgtBcnCount++;
        if (rssi) tgtRssi = tgtRssi ? (int8_t)((tgtRssi * 3 + rssi) / 4) : rssi;
    }
    int k = -1;
    for (int i = 0; i < nAps; i++) if (!memcmp(aps[i].bssid, bssid, 6)) { k = i; break; }
    if (k < 0) {
        if (nAps < (int)(sizeof(aps) / sizeof(aps[0]))) k = nAps++;
        else {                                                                // full: replace the AP heard from longest ago
            k = 0;
            for (int i = 1; i < nAps; i++) if (now - aps[i].seenMs > now - aps[k].seenMs) k = i;
        }
        bzero(&aps[k], sizeof(aps[k]));
        memcpy(aps[k].bssid, bssid, 6);
    }
    itl_ap &a = aps[k];
    a.ch = ch;
    if (ssid[0] || !a.ssid[0]) strlcpy(a.ssid, ssid, sizeof(a.ssid));       // a probe response names a hidden network
    if (rssi) a.rssi = a.rssi ? (int8_t)((a.rssi + rssi) / 2) : rssi;
    a.sec = secFromIes(f + 36, p + len, (uint16_t)(f[34] | (f[35] << 8)));
    a.seenMs = now;
    a.probe = f[0] == 0x50;                                                  // probe response (a beacon is 0x80)
    a.bcnInt = (uint16_t)(f[32] | (f[33] << 8));
    a.cap = (uint16_t)(f[34] | (f[35] << 8));
    const uint8_t *ies = f + 36, *iend = p + len;
    uint16_t il = iend > ies ? ieWhole(ies, (uint32_t)(iend - ies), ITL_NATIVE_IE_MAX) : 0;
    memcpy(a.ie, ies, il);
    a.ieLen = il;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Supervisor: connect, stay connected, obey the user client
// ---------------------------------------------------------------------------------------------------------------------------
int itlmt7925::loadPlistNets(Net *out, int max)
{
    int n = 0;
    for (int i = 1; i <= 4 && n < max; i++) {
        char ks[16], kp[16];
        snprintf(ks, sizeof(ks), i == 1 ? "itl_ssid" : "itl_ssid%d", i);
        snprintf(kp, sizeof(kp), i == 1 ? "itl_psk" : "itl_psk%d", i);
        OSString *s = OSDynamicCast(OSString, getProperty(ks));
        OSString *k = OSDynamicCast(OSString, getProperty(kp));
        if (!s || !k || !s->getLength() || s->getLength() > 32 || k->getLength() < 8 || k->getLength() > 63) continue;
        strlcpy(out[n].ssid, s->getCStringNoCopy(), sizeof(out[n].ssid));
        strlcpy(out[n].psk, k->getCStringNoCopy(), sizeof(out[n].psk));
        n++;
    }
    return n;
}

static const char *failText(const char *stage)
{
    if (!strncmp(stage, "nocred", 6)) return "no network configured";
    if (!strncmp(stage, "scan", 4)) return "network not found";
    if (!strncmp(stage, "roc-fail", 8)) return "radio did not get the channel";
    if (!strncmp(stage, "auth-fail", 9)) return "the access point refused authentication";
    if (!strncmp(stage, "assoc-fail", 10)) return "the access point refused association";
    if (!strncmp(stage, "hs-fail", 7)) return "key handshake failed";
    return "connection failed";
}

// Seen by a scan within maxAgeMs (beacon or probe response). Hidden networks never are; see the probe-all round below.
bool itlmt7925::apInRange(const char *ssid, uint32_t maxAgeMs)
{
    uint32_t now = nowMs();
    for (int i = 0; i < nAps; i++) if (!strcmp(aps[i].ssid, ssid) && now - aps[i].seenMs <= maxAgeMs) return true;
    return false;
}

void itlmt7925::m3Supervise()
{
    Net boot[4];
    int nb = loadPlistNets(boot, 4);
    Net user = {};
    bool haveUser = false, want = nb > 0, everUp = false, away = false, bootScan = true;   // aps[] holds the M2 boot scan
    bool userNative = false;                                 // the current `user` network was asked for by the Family (ITL_NATIVE_JOIN)
    uint32_t fails = 0, nextTry = 0, lastProbeAll = nowMs();
    wifiNets();                                              // the boot scan (M2) already filled aps[]
    wifiState(want ? "connecting" : "idle", "");
    m3log("supervisor: %d configured network(s)", nb);
    for (;;) {
        Net j;
        uint32_t c = cmdTake(CMD_SCAN | CMD_JOIN | CMD_DISCONNECT, &j);
        if (c & CMD_DISCONNECT) {
            want = false; haveUser = false; fails = 0; away = false; userNative = false;
            bzero(&user, sizeof(user));
            if (njState != ITL_NATIVE_FAILED) njState = ITL_NATIVE_IDLE;
            m3log("supervisor: disconnect");
            wifiState("idle", "");
        }
        if (c & CMD_JOIN) {
            // Another network, or a cap learned more than 10 min ago: start from itlmt_fast again. The cap survives a disconnect
            // and a failed join of the same network (the Family retries from the start each time; every retry used to spend
            // 30+ s walking down the same ladder again).
            if (strcmp(capSsid, j.ssid) != 0 || nowMs() - capMs > 600000) {
                lvlCap = 255;
                capBand = 0;
                strlcpy(capSsid, j.ssid, sizeof(capSsid));
            }
            user = j;
            userNative = j.native;
            haveUser = true; want = true; everUp = false; fails = 0; nextTry = 0; away = false;
            m3log("supervisor: join ssid len=%u", (unsigned)strlen(user.ssid));
        }
        bzero(&j, sizeof(j));
        if (c & CMD_SCAN) {
            wifiScan();
            wifiState(want ? (away ? "idle" : "connecting") : "idle", nullptr);
        }
        uint32_t now = nowMs();
        if (want && (int32_t)(now - nextTry) >= 0) {
            // Only networks a scan sees right now are tried: the joined one first, then itl_ssid..itl_ssid4. A network the
            // user just picked is tried as asked. Every 5 min every configured network gets the directed probes too
            // (hidden SSIDs never show in a wildcard scan). Out of range of all of them: idle, wildcard scan every 30 s
            // (the menu bar app's auto-join of its own saved networks runs on those scans).
            bool fresh = haveUser && !everUp && fails == 0;
            bool probeAll = now - lastProbeAll >= 300000;
            if (!fresh && !(c & CMD_SCAN) && !bootScan) { wifiScan(); now = nowMs(); }
            bootScan = false;
            if (probeAll) lastProbeAll = now;
            candN = 0;
            if (haveUser && (fresh || probeAll || apInRange(user.ssid, 60000))) candNets[candN++] = user;
            for (int i = 0; i < nb && candN < 4; i++) {
                if (haveUser && !strcmp(boot[i].ssid, user.ssid)) continue;
                if (probeAll || apInRange(boot[i].ssid, 60000)) candNets[candN++] = boot[i];
            }
            if (!candN) {
                if (!away) { m3log("supervisor: no configured network in range"); evLog("no configured network in range"); }
                away = true;
                wifiState("idle", "no saved network in range");
                nextTry = nowMs() + 30000;
                continue;
            }
            away = false;
            wifiState("connecting", "");
            setProperty("wifi-ssid", candNets[0].ssid);
            uint32_t up0 = linkUpMs;
            m3lost = false;
            m3lostWhy[0] = 0;
            int rc = m3Run();
            bzero(candNets, sizeof(candNets));
            candN = 0;
            bool wasUp = linkUpMs != up0;
            everUp |= wasUp;
            m3log("supervisor: attempt rc=%d up=%d lost=%d (%s)", rc, wasUp ? 1 : 0, m3lost ? 1 : 0, m3res);
            if (recoverWanted && recoverCnt < 8) {                       // the firmware stopped answering: cold start again
                recoverWanted = false;
                bool ok = chipRecover();
                bootScan = true;                                         // M2 scanned: aps[] is fresh
                wifiNets();
                if (njState == ITL_NATIVE_UP) njState = ITL_NATIVE_IDLE;
                if (ok) { fails = 0; nextTry = 0; wifiState(want ? "connecting" : "idle", ""); continue; }
            }
            recoverWanted = false;
            if (cmdPending(CMD_JOIN | CMD_DISCONNECT)) continue;          // the user changed the plan while we were connecting
            if (userNative && !wasUp) {
                // The join the Family asked for did not work: report it once and stop; the Family decides what happens next.
                njFail = failCode(m3res);
                njState = ITL_NATIVE_FAILED;
                userNative = false; haveUser = false; want = nb > 0; fails = 0; away = false;
                bzero(&user, sizeof(user));
                wifiState("failed", failText(m3res));
                evLog("native join failed: %s", failText(m3res));
                m3log("supervisor: native join failed (%s)", m3res);
                nextTry = nowMs() + 5000;
                continue;
            }
            if (njState == ITL_NATIVE_UP && !m3linkUp) njState = ITL_NATIVE_IDLE;   // link went away; a reconnect needs no new join
            if (wasUp) fails = 0;
            fails++;
            static const uint32_t backoff[5] = { 1000, 3000, 5000, 10000, 30000 };
            nextTry = nowMs() + backoff[fails < 5 ? fails : 4];
            const char *why = wasUp ? (m3lostWhy[0] ? m3lostWhy : "link lost") : failText(m3res);
            if (haveUser && !everUp && fails >= 3) {                     // a network the user picked never worked: stop trying
                haveUser = false;
                want = nb > 0;                                           // the configured networks, if any, take over again
                wifiState("failed", why);
                m3log("supervisor: giving up on the joined network: %s", why);
            } else {
                wifiState(wasUp ? "connecting" : "failed", why);
            }
            continue;
        }
        m3PumpOnce();                                                    // idle: keep the rings drained
        IOSleep(50);
    }
}
