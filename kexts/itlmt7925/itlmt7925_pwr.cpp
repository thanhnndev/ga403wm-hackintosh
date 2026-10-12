// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925 - transmit power tables, as Linux sets them up before the first association (mt7925_mcu_regd_update):
//   1. CLC (mt7925_mcu_set_clc): the per-country power tables that ship inside the RAM firmware (a region the firmware download
//      skips, FW_TYPE_CLC), handed back to the firmware with UNI SET_POWER_LIMIT tag 3 for the country in use.
//   2. rate power limits (mt7925_mcu_set_rate_txpower): SET_POWER_LIMIT tag 1, every channel of a band in batches of three, one
//      449-entry SKU table each; without device tree limits Linux fills every rate with the channel's target power, which is
//      the SAR limit from the ACPI tables of the Wi-Fi device (MTDS dynamic SAR, MTGS geo offsets; mt792x_acpi_sar.c).
// The driver used to send neither, and the firmware ran on whatever it starts with.
#include "itlmt7925.hpp"
#include "mt7925_regs.h"
#include "itl_power.h"

#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <string.h>

extern const uint8_t itl_fw_ram[], itl_fw_ram_end[];

static inline uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static inline void put16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }

#define ITL_EIO -5
#define ITL_EINVAL -22

// uniSend checks the sequence; power commands also require a successful command-result event.
int itlmt7925::powerCmd(const void *payload, size_t plen, const char *name)
{
    uint8_t ev[64];
    uint32_t evl = 0;
    int rc = uniSend(0x2c, payload, plen, false, ev, sizeof(ev), &evl, 3000);
    if (!rc && (evl < 52 || ev[36] != 1 || ev[44] != 0x2c || le32(ev + 48))) rc = ITL_EIO;
    if (rc) m3log("%s failed rc=%d", name, rc);
    return rc;
}

#define UNI_SET_POWER_LIMIT 0x2c
#define UNI_EFUSE_CTRL      0x2d
#define FW_TYPE_CLC         2
#define CLC_HDR             16              // struct mt7925_clc: len, idx, ver, t0 / t2 (10 bytes), then data

// ---------------------------------------------------------------------------------------------
// ACPI SAR tables (package of integers under the Wi-Fi device: \_SB.PCI0.GPP5.WLAN.MTDS / MTGS on the GA403WM)
// ---------------------------------------------------------------------------------------------
static int acpiTable(IOPCIDevice *pci, const char *name, uint8_t *out, uint32_t max)
{
    OSString *path = pci ? OSDynamicCast(OSString, pci->getProperty("acpi-path")) : nullptr;
    if (!path) return -1;
    IORegistryEntry *e = IORegistryEntry::fromPath(path->getCStringNoCopy());
    IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, e);
    OSObject *r = nullptr;
    int n = -1;
    if (dev && dev->evaluateObject(name, &r) == kIOReturnSuccess) {
        OSArray *a = OSDynamicCast(OSArray, r);
        if (a && a->getCount() <= max) {
            n = (int)a->getCount();
            for (int i = 0; i < n; i++) {
                OSNumber *v = OSDynamicCast(OSNumber, a->getObject((unsigned)i));
                if (!v) { n = -1; break; }
                out[i] = (uint8_t)v->unsigned32BitValue();
            }
        }
    }
    OSSafeReleaseNULL(r);
    OSSafeReleaseNULL(e);
    return n;
}

// mt792x_asar_fits(): which layout a table really has (some BIOSes label a v2 table v1)
// sarPwr[i] = mt792x_asar_range_pwr() for the world regulatory domain (geo row 2), which is the domain the driver gives the
// firmware (set_domain "00")
void itlmt7925::sarInit()
{
    int8_t *sar = sarPwr;
    char log[192];
    const size_t logLen = sizeof(log);
    uint8_t dyn[128], geo[128];
    int dl = acpiTable(pci, "MTDS", dyn, sizeof(dyn));
    int gl = acpiTable(pci, "MTGS", geo, sizeof(geo));
    int dynVer, geoVer;
    parseSar(dyn, dl, geo, gl, sar, &dynVer, &geoVer);
    if (!dynVer) { m3log("sar: none (MTDS len %d)", dl); return; }
    snprintf(log, logLen, "sar: MTDS v%d MTGS v%d -> 2g %d 5g %d/%d/%d/%d 6g %d (0.5 dBm)", dynVer, geoVer, sar[0], sar[1], sar[2], sar[3], sar[4], sar[5]);
    m3log("%s", log);
}

// mt7925_mcu_read_eeprom(): EFUSE_CTRL query of the 16-byte block holding off
int itlmt7925::efuseRead(uint32_t off, uint8_t *val)
{
    uint8_t req[32];
    bzero(req, sizeof(req));
    put16(req + 4, 1);                                       // tag
    put16(req + 6, sizeof(req) - 4);
    uint32_t a = off & ~15u;
    memcpy(req + 8, &a, 4);
    static uint8_t ev[160];
    uint32_t evl = 0;
    int rc = uniSend(UNI_EFUSE_CTRL, req, sizeof(req), true, ev, sizeof(ev), &evl, 3000);
    if (rc) return rc;
    // Linux (mt7925_mcu_read_eeprom) only takes data[off % 16] of the 124-byte event: rsv[4], tag, len, ver, addr, valid, size,
    // magic, type, rsv1[4], data[32] after the 44-byte RXD, and checks none of the header fields. Do the same; when a header
    // field is not what was asked for, keep the first bytes in m3-log (bytes 40..135: end of the RXD + the payload).
    if (evl < 44 + 48 + 16) { m3log("efuse ev too short len=%u", evl); return ITL_EIO; }
    if (ev[44 + 4] != 1 || ev[44 + 5] != 0 || le32(ev + 44 + 12) != a || !le32(ev + 44 + 16)) {
        for (uint32_t o = 40; o < 136 && o < evl; o += 32) {
            char hex[2 * 32 + 1];
            uint32_t n = evl - o < 32 ? evl - o : 32;
            for (uint32_t i2 = 0; i2 < n; i2++) snprintf(hex + 2 * i2, 3, "%02x", ev[o + i2]);
            m3log("efuse ev len=%u want=%x +%u: %s", evl, a, o, hex);
        }
    }
    *val = ev[44 + 48 + (off & 15)];
    return 0;
}

// ---------------------------------------------------------------------------------------------
// CLC: __mt7925_mcu_set_clc() for the POWER and POWER_EXT tables
// ---------------------------------------------------------------------------------------------
static const uint8_t *clcRegion(uint32_t *len)
{
    const uint8_t *fw = itl_fw_ram;
    size_t fwlen = (size_t)(itl_fw_ram_end - itl_fw_ram);
    if (fwlen < FW_TRAILER_SIZE) return nullptr;
    const uint8_t *tr = fw + fwlen - FW_TRAILER_SIZE;
    uint32_t nreg = tr[2];
    if (nreg * FW_REGION_SIZE + FW_TRAILER_SIZE > fwlen) return nullptr;
    size_t offset = 0;
    const size_t payloadLen = fwlen - FW_TRAILER_SIZE - nreg * FW_REGION_SIZE;
    for (uint32_t i = 0; i < nreg; i++) {
        const uint8_t *rg = tr - (nreg - i) * FW_REGION_SIZE;
        uint32_t l = le32(rg + 20);
        if (l > payloadLen - offset) return nullptr;
        if ((rg[24] & FW_FEATURE_NON_DL) && rg[25] == FW_TYPE_CLC) { *len = l; return fw + offset; }
        offset += l;
    }
    return nullptr;
}

// sends the rules of one table for country cc; returns the number sent, -1 on a command failure
int itlmt7925::clcSend(const uint8_t *clc, const char *cc, uint8_t env, uint8_t idx)
{
    uint32_t clen = le32(clc);
    const uint8_t *data = clc + CLC_HDR;
    uint32_t begin, end;
    if (!clcRuleBounds(clc, clen, &begin, &end)) return -1;
    const uint8_t *pos = data + begin, *last = data + end;
    static uint8_t req[84 + 2048];
    int sent = 0;
    for (; pos + 8 <= last; pos += 8) {                      // rule: alpha2[2], type[2], seg_idx, flag, rsv[2]
        if (pos[0] != (uint8_t)cc[0] || pos[1] != (uint8_t)cc[1]) continue;
        uint32_t so, sl;
        if (!clcSegmentBounds(clc, clen, pos[4], &so, &sl)) return -1;
        bzero(req, 84);
        put16(req + 4, 3);                                   // tag
        put16(req + 6, (uint16_t)(84 + sl - 4));
        req[8] = clc[5];                                     // ver
        put16(req + 10, (uint16_t)sl);                       // size
        req[12] = idx;
        req[13] = env;
        req[16] = pos[0]; req[17] = pos[1];
        req[18] = pos[2]; req[19] = pos[3];
        memcpy(req + 84, data + so, sl);
        if (powerCmd(req, 84 + sl, "clc_segment")) return -1;
        sent++;
    }
    return sent;
}

int itlmt7925::m3Clc(const char *cc, uint8_t env)
{
    uint32_t len = 0;
    const uint8_t *base = clcRegion(&len);
    if (!base) { m3log("clc: no CLC region in the firmware"); return ITL_EINVAL; }
    const uint8_t *tbl[2] = {nullptr, nullptr};
    for (uint32_t off = 0; off + CLC_HDR <= len;) {
        const uint8_t *c = base + off;
        uint32_t l = le32(c);
        uint8_t idx = c[4];
        if (idx >= 4 || l < CLC_HDR || l > len - off) break;
        if (idx < 2 && !tbl[idx] && (c[7] & 3) == hwEncap) tbl[idx] = c;   // t0.type & MT_EE_HW_TYPE_ENCAP
        off += l;
    }
    int n[2] = {0, 0};
    bool world[2] = {false, false};
    for (uint8_t i = 0; i < 2; i++) {
        if (!tbl[i]) continue;
        n[i] = clcSend(tbl[i], cc, env, i);
        if (n[i] == 0) { world[i] = true; n[i] = clcSend(tbl[i], "00", 1, i); }   // no rule for cc: world, indoor
    }
    m3log("clc %c%c env %u encap %u: power %d%s ext %d%s", cc[0], cc[1], env, hwEncap, n[0], world[0] ? "(00)" : "", n[1],
          world[1] ? "(00)" : "");
    if (!tbl[0] || n[0] <= 0 || (tbl[1] && n[1] <= 0)) return ITL_EIO;
    memcpy(clcCc, cc, 2); clcCc[2] = 0;
    return 0;
}

// ---------------------------------------------------------------------------------------------
// rate power limits: mt7925_mcu_rate_txpower_band() for 2.4 and 5 GHz
// ---------------------------------------------------------------------------------------------
// mt7925_mcu_build_sku() with every rate at the same limit v (unused entries 127 = no limit)
int itlmt7925::m3TxPower()
{
    static const uint8_t ch2[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
    static const uint8_t ch5[] = { 36,  38,  40,  42,  44,  46,  48,  50,  52,  54,  56,  58,  60,  62,  64, 100,
                                  102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122, 124, 126, 128, 132, 134,
                                  136, 138, 140, 142, 144, 149, 151, 153, 155, 157, 159, 161, 165, 167};
    static uint8_t msg[52 + 3 * (1 + SKU_LEN)];
    int cmds = 0, rc = 0;
    for (int b = 0; b < 2 && !rc; b++) {
        bool g2 = b == 0;
        const uint8_t *list = g2 ? ch2 : ch5;
        int n = g2 ? (int)sizeof(ch2) : (int)sizeof(ch5);
        for (int i = 0; i < n && !rc; i += 3) {
            int num = n - i < 3 ? n - i : 3;
            uint32_t len = 52 + (uint32_t)num * (1 + SKU_LEN);
            bzero(msg, 52);
            put16(msg + 4, 1);                               // tag
            put16(msg + 6, (uint16_t)(len - 4));
            msg[12] = (uint8_t)num;                          // n_chan
            msg[13] = g2 ? 1 : 2;                            // band
            msg[14] = i + num == n;                          // last_msg
            msg[16] = (uint8_t)clcCc[0]; msg[17] = (uint8_t)clcCc[1];
            for (int j = 0; j < num; j++) {
                uint8_t ch = list[i + j];
                uint32_t freq = g2 ? (ch == 14 ? 2484u : 2407u + 5u * ch) : 5000u + 5u * ch;
                uint8_t *e = msg + 52 + (unsigned)j * (1 + SKU_LEN);
                e[0] = ch;
                // The world domain supplies a conservative 20 dBm ceiling; CLC may lower it further.
                int8_t limit = sarFor(sarPwr, freq);
                if (limit > 40) limit = 40;
                buildSku((int8_t *)e + 1, limit, g2);
            }
            rc = powerCmd(msg, len, "txpower_batch");
            cmds++;
        }
    }
    m3log("txpower: %d commands, world ceiling 40, SAR 2g %d 5g %d (0.5 dBm) rc=%d",
          cmds, sarFor(sarPwr, 2437), sarFor(sarPwr, 5200), rc);
    return rc;
}
