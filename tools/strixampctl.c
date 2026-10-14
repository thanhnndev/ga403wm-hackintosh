// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// strixampctl: userland controller for the CS35L56 speaker amps of the GA403WM, talking to the StrixAmp kext
// (kexts/StrixAmp). All amp policy lives here so sequences can be changed without rebooting: bring-up, firmware (wmfw +
// bin) download, play / pause, volume. Needs root (the kext refuses anything else).
//
//   cc -O2 -Wall -o strixampctl tools/strixampctl.c -framework IOKit -framework CoreFoundation
//   sudo strixampctl status
//   sudo strixampctl init --vol -24
//   strixampctl fwload --dry wmfw.wmfw amp1.bin amp2.bin        (offline: parses and prints, never opens the kext)
//
// Register map, mailbox commands and sequences follow the Linux cs35l56 / cs_dsp drivers (Cirrus Logic, GPL-2.0): facts
// (register numbers, command codes, file formats) only, no code is copied (NOTICE.md).
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include "../kexts/StrixAmp/StrixAmpProto.h"
#include "../macos/RogAudio/RogAudioSettings.h"

// ---- chip constants ----------------------------------------------------------------------------------------------------
enum {
    R_DEVID = 0x0, R_REVID = 0x4, R_OTPID = 0x10,
    R_ASP1_ENABLES1 = 0x4800, R_ASP1_CONTROL1 = 0x4804, R_ASP1_CONTROL2 = 0x4808, R_ASP1_CONTROL3 = 0x480C,
    R_ASP1_FRAME_CONTROL1 = 0x4810, R_ASP1_FRAME_CONTROL5 = 0x4820, R_ASP1_DATA_CONTROL1 = 0x4830,
    R_ASP1_DATA_CONTROL5 = 0x4840,
    R_ASP1TX1 = 0x4C20, R_ASP1TX2 = 0x4C24, R_ASP1TX3 = 0x4C28, R_ASP1TX4 = 0x4C2C,
    R_DP3_CH1 = 0x4C70, R_DP3_CH2 = 0x4C74, R_DP3_CH3 = 0x4C78, R_DP3_CH4 = 0x4C7C,
    R_IRQ1_MASK_1 = 0xE090, R_IRQ1_MASK_8 = 0xE0AC, R_IRQ1_MASK_18 = 0xE0D4, R_IRQ1_MASK_20 = 0xE0DC,
    R_MBOX = 0x11020,
    R_FW_VER = 0x2800010, R_HALO_STATE = 0x28021E0, R_PM_CUR_STATE = 0x2804308,
    R_USER_MUTE = 0x3400024, R_USER_VOLUME = 0x340002C, R_POSTURE = 0x3400094, R_PROT_STATUS = 0x34000D8,
    R_ACTUAL_PS = 0x3400150,
};
enum {
    MB_PING = 0x0A000000, MB_PLAY = 0x0B000001, MB_PAUSE = 0x0B000002, MB_REINIT = 0x0B000003,
    MB_NO_HIBERNATE = 0x02000003, MB_ALLOW_HIBERNATE = 0x02000004, MB_SHUTDOWN = 0x02000005, MB_SYS_RESET = 0x02000007,
};
// cs35l56 region bases (b0)
enum {
    BASE_XM_PACKED = 0x2000000, BASE_XM_UNPACKED24 = 0x2800000, BASE_YM_PACKED = 0x2C00000,
    BASE_YM_UNPACKED24 = 0x3400000, BASE_PM_PACKED = 0x3800000,
};
enum { T_ABS = 0xf0, T_ALG = 0xf2, T_META = 0xfc, T_NAME = 0xfe, T_INFO = 0xff,
       T_ADSP2_XM = 5, T_ADSP2_YM = 6, T_PM_PACKED = 0x10, T_XM_PACKED = 0x11, T_YM_PACKED = 0x12,
       T_XM_LONG = 0xf405, T_YM_LONG = 0xf406, T_XM_PACKED_LONG = 0xf411, T_YM_PACKED_LONG = 0xf412 };

// ---- transport ---------------------------------------------------------------------------------------------------------
static int g_dry;                 // 1: never touch the kext, log operations and emulate DSP memory reads
static int g_verbose;
static io_connect_t g_conn;

static int g_quiet;               // daemon: no complaints while the kext / amps are not there yet

static int sa_open(void)
{
    io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("StrixAmp"));
    if (!svc) { if (!g_quiet) fprintf(stderr, "StrixAmp service not found (kext not loaded?)\n"); return -1; }
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) {
        if (!g_quiet) fprintf(stderr, "IOServiceOpen: 0x%x%s\n", kr, getuid() ? " (run with sudo)" : "");
        g_conn = 0;
        return -1;
    }
    return 0;
}

static int sa_call(const uint8_t *in, size_t inlen, uint8_t *out, size_t *outlen)
{
    kern_return_t kr = IOConnectCallStructMethod(g_conn, kSaSelExec, in, inlen, out, outlen);
    if (kr != KERN_SUCCESS) { if (!g_quiet) fprintf(stderr, "IOConnectCallStructMethod: 0x%x\n", kr); return -1; }
    return 0;
}

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
// emulated memory for --dry: list of writes, newest wins on read
struct EmuW { uint32_t reg; uint32_t len; uint8_t *d; };
static struct EmuW *g_emu; static size_t g_emu_n;
static void emu_write(uint32_t reg, const uint8_t *d, uint32_t len)
{
    g_emu = realloc(g_emu, (g_emu_n + 1) * sizeof(*g_emu));
    g_emu[g_emu_n].reg = reg; g_emu[g_emu_n].len = len;
    g_emu[g_emu_n].d = malloc(len); memcpy(g_emu[g_emu_n].d, d, len);
    g_emu_n++;
}
static int emu_byte(uint32_t addr, uint8_t *b)
{
    for (size_t i = g_emu_n; i-- > 0;)
        if (addr >= g_emu[i].reg && addr < g_emu[i].reg + g_emu[i].len) { *b = g_emu[i].d[addr - g_emu[i].reg]; return 1; }
    return 0;
}
static void emu_read(uint32_t reg, uint8_t *out, uint32_t len)
{
    // XM unpacked24 window is a view of XM packed: word k = 24 bits at packed bytes 3k..3k+2
    for (uint32_t i = 0; i < len; i += 4) {
        uint32_t a = reg + i;
        uint8_t w[4] = { 0, 0, 0, 0 };
        if (a >= BASE_XM_UNPACKED24 && a < BASE_XM_UNPACKED24 + 0x8000) {
            // packed memory: 4 x 24 bit words in 3 big-endian 32 bit words, LE bit packing (a_j = (W0 | W1<<32 | W2<<64) >> 24j)
            uint32_t k = (a - BASE_XM_UNPACKED24) / 4, g = k / 4, j = k % 4;
            uint8_t gb[12] = { 0 };
            for (int q = 0; q < 12; q++) emu_byte(BASE_XM_PACKED + 12 * g + q, &gb[q]);
            unsigned __int128 x = 0;
            for (int q = 0; q < 3; q++) x |= (unsigned __int128)be32(gb + 4 * q) << (32 * q);
            uint32_t v = (uint32_t)((x >> (24 * j)) & 0xFFFFFF);
            w[1] = v >> 16; w[2] = v >> 8; w[3] = v;
        } else {
            for (int j = 0; j < 4; j++) emu_byte(a + j, &w[j]);
        }
        memcpy(out + i, w, 4);
    }
}

static void put32(uint8_t *p, uint32_t v) { memcpy(p, &v, 4); }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }

// One operation, one round trip. data/dlen: payload for wblock; rd/rlen: result buffer.
static int sa_op(uint8_t op, uint8_t addr, uint32_t reg, uint32_t a, uint32_t b, uint16_t len, const uint8_t *payload,
                 uint8_t *rd, uint32_t rdcap, uint32_t *rdlen)
{
    uint8_t in[STRIXAMP_MAX_IO], out[STRIXAMP_MAX_IO];
    struct SaOpHdr h = { op, addr, len, reg, a, b };
    size_t n = sizeof(h) + (op == kSaOpWBlock ? len : 0);
    if (n > sizeof(in)) return -1;
    memcpy(in, &h, sizeof(h));
    if (op == kSaOpWBlock) memcpy(in + sizeof(h), payload, len);
    if (g_dry) {
        if (g_verbose) fprintf(stderr, "  op %u addr 0x%02x reg 0x%08x a 0x%x b 0x%x len %u\n", op, addr, reg, a, b, len);
        if (op == kSaOpWBlock) emu_write(reg, payload, len);
        else if (op == kSaOpWrite32) { uint8_t t[4]; put32(t, 0); t[0] = a >> 24; t[1] = a >> 16; t[2] = a >> 8; t[3] = a; emu_write(reg, t, 4); }
        else if (op == kSaOpRBlock && rd) emu_read(reg, rd, len < rdcap ? len : rdcap);
        else if ((op == kSaOpRead32 || op == kSaOpPoll) && rd) { emu_read(reg, rd, 4); }
        if (rdlen) *rdlen = (op == kSaOpRBlock) ? len : 4;
        return 0;
    }
    size_t outlen = sizeof(out);
    if (sa_call(in, n, out, &outlen)) return -1;
    if (outlen < sizeof(struct SaRespHdr)) { fprintf(stderr, "short response\n"); return -1; }
    struct SaRespHdr r;
    memcpy(&r, out, sizeof(r));
    if (r.status) {
        if (!g_quiet) fprintf(stderr, "op %u addr 0x%02x reg 0x%08x failed: 0x%x\n", op, addr, reg, (unsigned)r.status);
        return r.status;
    }
    if (rd && r.len) { memcpy(rd, out + sizeof(r), r.len < rdcap ? r.len : rdcap); }
    if (rdlen) *rdlen = r.len;
    return 0;
}

// value from the kernel is host order; the chip's big-endian decoding is already done there
static int r32(uint8_t a, uint32_t reg, uint32_t *v)
{
    uint8_t d[4] = { 0 };
    uint32_t l = 0;
    int rc = sa_op(kSaOpRead32, a, reg, 0, 0, 0, NULL, d, 4, &l);
    if (rc == 0) *v = g_dry ? be32(d) : le32(d);
    return rc;
}
static int w32(uint8_t a, uint32_t reg, uint32_t v) { return sa_op(kSaOpWrite32, a, reg, v, 0, 0, NULL, NULL, 0, NULL); }
static int ub(uint8_t a, uint32_t reg, uint32_t mask, uint32_t v) { return sa_op(kSaOpUBits, a, reg, mask, v, 0, NULL, NULL, 0, NULL); }
static int sleepms(uint32_t ms) { if (g_dry) return 0; return sa_op(kSaOpSleep, 0, 0, ms, 0, 0, NULL, NULL, 0, NULL); }
static int poll(uint8_t a, uint32_t reg, uint32_t mask, uint32_t want, uint16_t timeoutMs, uint32_t *last)
{
    uint8_t d[4] = { 0 }; uint32_t l = 0;
    int rc = sa_op(kSaOpPoll, a, reg, mask, want, timeoutMs, NULL, d, 4, &l);
    if (last && l == 4) *last = le32(d);
    return rc;
}
static int rblock(uint8_t a, uint32_t reg, uint8_t *buf, uint32_t len)
{
    uint32_t done = 0;
    while (done < len) {
        uint32_t n = len - done > 1024 ? 1024 : len - done, l = 0;
        int rc = sa_op(kSaOpRBlock, a, reg + done, 0, 0, (uint16_t)n, NULL, buf + done, n, &l);
        if (rc) return rc;
        done += n;
    }
    return 0;
}
static int wblock(uint8_t a, uint32_t reg, const uint8_t *buf, uint32_t len)
{
    uint32_t done = 0;
    while (done < len) {
        uint32_t n = len - done > 2048 ? 2048 : len - done;
        int rc = sa_op(kSaOpWBlock, a, reg + done, 0, 0, (uint16_t)n, buf + done, NULL, 0, NULL);
        if (rc) return rc;
        done += n;
    }
    return 0;
}
static int mbox(uint8_t a, uint32_t cmd)
{
    int rc = w32(a, R_MBOX, cmd);
    if (rc) return rc;
    return poll(a, R_MBOX, 0xFFFFFFFF, 0, 20, NULL);
}

// ---- sequences ---------------------------------------------------------------------------------------------------------
// volume field: bits 15:6 signed, 0.25 dB steps
static uint32_t vol_raw(double dB) { int v = (int)(dB * 4.0 + (dB < 0 ? -0.5 : 0.5)); if (v < -400) v = -400; if (v > 0) v = 0; return ((uint32_t)v & 0x3FF) << 6; }

static int amp_status(uint8_t a)
{
    uint32_t devid = 0, revid = 0, otp = 0, fw = 0, halo = 0, prot = 0, pm = 0, ps = 0, asp = 0, vol = 0, mute = 0;
    if (r32(a, R_DEVID, &devid)) { printf("amp 0x%02x: no answer\n", a); return -1; }
    r32(a, R_REVID, &revid); r32(a, R_OTPID, &otp); r32(a, R_FW_VER, &fw); r32(a, R_HALO_STATE, &halo);
    r32(a, R_PROT_STATUS, &prot); r32(a, R_PM_CUR_STATE, &pm); r32(a, R_ACTUAL_PS, &ps); r32(a, R_ASP1_ENABLES1, &asp);
    r32(a, R_USER_VOLUME, &vol); r32(a, R_USER_MUTE, &mute);
    int vi = (int)((vol >> 6) & 0x3FF); if (vi & 0x200) vi -= 0x400;
    printf("amp 0x%02x: DEVID %08x REVID %02x OTPID %u fw %u.%u.%u HALO_STATE %u PROT_STATUS %08x (%s) PM_CUR_STATE %u "
           "ACTUAL_PS %u ASP1_EN %08x vol %.2f dB mute %u\n",
           a, devid, revid, otp, fw >> 16, (fw >> 8) & 0xff, fw & 0xff, halo, prot,
           (prot & 1) ? "firmware MISSING" : "firmware patched", pm, ps, asp, vi / 4.0, mute & 1);
    return 0;
}

static int amp_diag(uint8_t a)
{
    static const struct { uint32_t reg; const char *name; } regs[] = {
        {0x2014, "GLOBAL_ENABLES"}, {0x2018, "BLOCK_ENABLES"}, {0x201C, "BLOCK_ENABLES2"},
        {0x2C04, "REFCLK_INPUT"}, {0x2C0C, "GLOBAL_SAMPLE_RATE"},
        {0x4800, "ASP1_ENABLES1"}, {0x4804, "ASP1_CONTROL1"}, {0x4808, "ASP1_CONTROL2"},
        {0x4810, "ASP1_FRAME_CONTROL1"}, {0x4820, "ASP1_FRAME_CONTROL5"},
        {0x480C, "ASP1_CONTROL3"}, {0x4830, "ASP1_DATA_CONTROL1"}, {0x4840, "ASP1_DATA_CONTROL5"},
        {0x4C00, "DACPCM1_INPUT"}, {0x4C08, "DACPCM2_INPUT"},
        {0x4C40, "DSP1RX1_INPUT"}, {0x4C44, "DSP1RX2_INPUT"},
        {0xE004, "IRQ1_STATUS"}, {0xE010, "IRQ1_EINT_1"}, {0xE02C, "IRQ1_EINT_8"},
        {0xE054, "IRQ1_EINT_18"}, {0xE05C, "IRQ1_EINT_20"},
        {0x25E2040, "DSP1_AHBM_DEBUG0"}, {0x25E2044, "DSP1_AHBM_DEBUG1"},
        {0x2B805C0, "DSP1_SCRATCH1"}, {0x2B805C8, "DSP1_SCRATCH2"},
        {0x2B805D0, "DSP1_SCRATCH3"}, {0x2B805D8, "DSP1_SCRATCH4"},
    };
    int failed = amp_status(a) != 0;
    for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
        uint32_t value = 0;
        if (r32(a, regs[i].reg, &value)) { failed = 1; continue; }
        printf("amp 0x%02x %-22s [%08x] = %08x\n", a, regs[i].name, regs[i].reg, value);
    }
    return failed;
}

// hw_init interrupt masks + register patch + HDA DAI config + known user-control defaults (volume given), then no auto-hibernate
static int amp_init(uint8_t a, double volDb, int afterFw)
{
    int rc = 0;
    if (!afterFw) {
        // hw_init: unmask nothing but the short/temp error sources
        if ((rc = w32(a, R_IRQ1_MASK_20, 0xFFFFFFFF))) return rc;
        if ((rc = ub(a, R_IRQ1_MASK_1, 0x80000000, 0))) return rc;
        if ((rc = ub(a, R_IRQ1_MASK_8, 0x80000000, 0))) return rc;
    }
    static const uint32_t seq[][2] = {
        { R_DP3_CH1, 0x18 }, { R_DP3_CH2, 0x19 }, { R_DP3_CH3, 0x29 }, { R_DP3_CH4, 0x28 }, { R_IRQ1_MASK_18, 0x1f7df0ff },
        { R_ASP1_CONTROL1, 0x21 }, { R_ASP1_CONTROL2, 0x20200200 }, { R_ASP1_CONTROL3, 0x3 },
        { R_ASP1_FRAME_CONTROL1, 0x03020100 }, { R_ASP1_FRAME_CONTROL5, 0x00020100 },
        { R_ASP1_DATA_CONTROL5, 0x18 }, { R_ASP1_DATA_CONTROL1, 0x18 }, { R_ASP1_ENABLES1, 0 },
        { R_ASP1TX1, 0x18 }, { R_ASP1TX2, 0x19 }, { R_ASP1TX3, 0x20 }, { R_ASP1TX4, 0x28 },
    };
    for (size_t i = 0; i < sizeof(seq) / sizeof(seq[0]); i++)
        if ((rc = w32(a, seq[i][0], seq[i][1]))) return rc;
    if ((rc = w32(a, R_USER_MUTE, 0))) return rc;
    if ((rc = w32(a, R_USER_VOLUME, vol_raw(volDb)))) return rc;
    if ((rc = w32(a, R_POSTURE, 0))) return rc;
    return mbox(a, MB_NO_HIBERNATE);
}

static int amp_play(uint8_t a, uint32_t txmask)
{
    uint32_t ps = 0;
    int rc = mbox(a, MB_PLAY);
    if (rc) return rc;
    poll(a, R_ACTUAL_PS, 0xFFFFFFFF, 0, 50, &ps);       // PS0 == 0
    return ub(a, R_ASP1_ENABLES1, (1u << 16) | (1u << 17) | txmask, (1u << 16) | (1u << 17) | txmask);
}
static int amp_pause(uint8_t a)
{
    int rc = mbox(a, MB_PAUSE);
    int rc2 = ub(a, R_ASP1_ENABLES1, (1u << 16) | (1u << 17) | 0xF, 0);
    return rc ? rc : rc2;
}

// ---- firmware ----------------------------------------------------------------------------------------------------------
static uint8_t *slurp(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return NULL; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *b = malloc(n + 4);
    if (!b || fread(b, 1, n, f) != (size_t)n) { fprintf(stderr, "%s: read error\n", path); fclose(f); return NULL; }
    fclose(f);
    *len = n;
    return b;
}

static int type_base(int type, uint32_t *base)
{
    switch (type) {
    case T_PM_PACKED: *base = BASE_PM_PACKED; return 0;
    case T_XM_PACKED: *base = BASE_XM_PACKED; return 0;
    case T_YM_PACKED: *base = BASE_YM_PACKED; return 0;
    case T_ADSP2_XM:  *base = BASE_XM_UNPACKED24; return 0;
    case T_ADSP2_YM:  *base = BASE_YM_UNPACKED24; return 0;
    }
    return -1;
}
static uint32_t region_to_reg(int type, uint32_t base, uint32_t offset)
{
    switch (type) {
    case T_ADSP2_XM: case T_ADSP2_YM: return base + offset * 4;
    case T_XM_PACKED: case T_YM_PACKED: return (base + offset * 3) & ~3u;
    case T_PM_PACKED: return base + offset * 5;
    }
    return offset;
}

struct Alg { uint32_t id, ver, xm, ym; };
struct FwCtx { struct Alg algs[64]; int nalgs; uint32_t fwId; };

static int load_wmfw(uint8_t a, const uint8_t *d, size_t n, int *writes)
{
    if (n < 16 || memcmp(d, "WMFW", 4)) { fprintf(stderr, "wmfw: bad magic\n"); return -1; }
    uint32_t hlen = le32(d + 4);
    if (d[10] != 4) { fprintf(stderr, "wmfw: core %u is not HALO (4)\n", d[10]); return -1; }
    size_t pos = 12 + 16;        // header + adsp2 sizes (xm ym pm zm)
    pos += 12;                   // footer: timestamp (8), checksum (4)
    if (pos != hlen) { fprintf(stderr, "wmfw: header length %u != %zu\n", hlen, pos); return -1; }
    int regions = 0;
    while (pos + 8 <= n) {
        uint32_t off = le32(d + pos) & 0xffffff, type = d[pos + 3], len = le32(d + pos + 4);
        if (len > n - pos - 8) { fprintf(stderr, "wmfw: region %d overruns file\n", regions); return -1; }
        uint32_t reg = 0, base;
        switch (type) {
        case T_INFO: case T_NAME: case T_ALG: case T_META: break;
        case T_ABS: reg = off; break;
        case T_PM_PACKED: case T_XM_PACKED: case T_YM_PACKED: case T_ADSP2_XM: case T_ADSP2_YM:
            if (type_base(type, &base)) return -1;
            reg = region_to_reg(type, base, off);
            break;
        default: fprintf(stderr, "wmfw: unknown region type 0x%x (skipped)\n", type);
        }
        if (reg && len) {
            if (len & 3) { fprintf(stderr, "wmfw: region %d length %u not word aligned\n", regions, len); return -1; }
            if (g_verbose) fprintf(stderr, "wmfw region %d type 0x%02x off %u len %u -> reg 0x%08x\n", regions, type, off, len, reg);
            if (wblock(a, reg, d + pos + 8, len)) return -1;
            (*writes)++;
        }
        pos += 8 + len;
        regions++;
    }
    return 0;
}

static int read_algs(uint8_t a, struct FwCtx *ctx)
{
    uint8_t hdr[40];
    if (rblock(a, BASE_XM_UNPACKED24, hdr, sizeof(hdr))) return -1;
    uint32_t nalgs = be32(hdr + 36);
    ctx->fwId = be32(hdr + 12);
    ctx->nalgs = 0;
    ctx->algs[ctx->nalgs++] = (struct Alg){ be32(hdr + 12), be32(hdr + 16), be32(hdr + 20), be32(hdr + 28) };
    if (nalgs > 60) { fprintf(stderr, "implausible algorithm count %u\n", nalgs); return -1; }
    if (nalgs) {
        uint8_t buf[60 * 24];
        if (rblock(a, BASE_XM_UNPACKED24 + 40, buf, nalgs * 24)) return -1;
        for (uint32_t i = 0; i < nalgs; i++) {
            const uint8_t *p = buf + i * 24;
            ctx->algs[ctx->nalgs++] = (struct Alg){ be32(p), be32(p + 4), be32(p + 8), be32(p + 16) };
        }
    }
    fprintf(stderr, "firmware id 0x%06x ver %u.%u.%u, %u algorithm(s)\n", ctx->fwId, be32(hdr + 16) >> 16, (be32(hdr + 16) >> 8) & 0xff,
            be32(hdr + 16) & 0xff, nalgs);
    return 0;
}

static int fw_string(const uint8_t *d, size_t n, size_t *pos, unsigned width,
                     const uint8_t **str, size_t *length)
{
    if (*pos > n || n - *pos < width) return -1;
    size_t len = width == 1 ? d[*pos] : le16(d + *pos);
    size_t field = (len + width + 3) & ~(size_t)3;
    if (field > n - *pos) return -1;
    if (str) *str = d + *pos + width;
    if (length) *length = len;
    *pos += field;
    return 0;
}

// Resolve read-only DSP diagnostics from the firmware's control descriptors and live algorithm table.
static int amp_fwdiag(uint8_t a, const uint8_t *d, size_t n)
{
    struct FwCtx ctx;
    if (n < 40 || memcmp(d, "WMFW", 4) || d[10] != 4 || d[11] != 3) return -1;
    uint32_t version = 0;
    if (r32(a, R_FW_VER, &version) || version != 0x030b10) {
        fprintf(stderr, "fwdiag requires live firmware 3.11.16, got %06x\n", version);
        return -1;
    }
    if (read_algs(a, &ctx)) return -1;
    size_t pos = le32(d + 4);
    if (pos < 40 || pos > n) return -1;
    unsigned found = 0;
    while (pos < n) {
        if (n - pos < 8) return -1;
        unsigned type = d[pos + 3];
        size_t len = le32(d + pos + 4);
        pos += 8;
        if (len > n - pos) return -1;
        const uint8_t *data = d + pos;
        pos += len;
        if (type != T_ALG) continue;
        if (len < 4) return -1;
        uint32_t id = le32(data);
        size_t p = 4;
        if (fw_string(data, len, &p, 1, NULL, NULL) ||
            fw_string(data, len, &p, 2, NULL, NULL) || len - p < 4) return -1;
        unsigned count = le32(data + p);
        p += 4;
        for (unsigned c = 0; c < count; c++) {
            if (len - p < 8) return -1;
            unsigned offset = le16(data + p), mem = le16(data + p + 2);
            size_t size = le32(data + p + 4);
            p += 8;
            if (size > len - p) return -1;
            size_t end = p + size, nameLen;
            const uint8_t *name;
            if (fw_string(data, end, &p, 1, &name, &nameLen) ||
                fw_string(data, end, &p, 1, NULL, NULL) ||
                fw_string(data, end, &p, 2, NULL, NULL) || end - p < 8) return -1;
            char label[256];
            if (nameLen >= sizeof(label)) return -1;
            memcpy(label, name, nameLen); label[nameLen] = 0;
            unsigned bytes = le32(data + p + 4);
            p = end;
            if (g_verbose) fprintf(stderr, "control alg=%06x mem=%u offset=%u bytes=%u name=%s\n", id, mem, offset, bytes, label);
            if (strncmp(label, "FW_", 3) && strncmp(label, "AS_", 3) &&
                strncmp(label, "FU21_", 5) && strncmp(label, "FU23_", 5) &&
                !strstr(label, "OP_LVL") && strcmp(label, "ABNORMAL_MUTE") &&
                strcmp(label, "CAL_STATUS") && strcmp(label, "CAL_SET_STATUS") &&
                strcmp(label, "SHORT_DETECTED") && strcmp(label, "ASP_MIX_ENABLE")) continue;
            if (mem != T_ADSP2_XM && mem != T_ADSP2_YM) continue;
            for (int k = 0; k < ctx.nalgs; k++) {
                if (ctx.algs[k].id != id) continue;
                uint32_t base = mem == T_ADSP2_XM ? BASE_XM_UNPACKED24 : BASE_YM_UNPACKED24;
                uint32_t alg = mem == T_ADSP2_XM ? ctx.algs[k].xm : ctx.algs[k].ym;
                uint32_t reg = region_to_reg(mem, base, alg + offset), value;
                if (bytes < 4 || r32(a, reg, &value)) return -1;
                printf("amp 0x%02x [%08x] = %08x %s (%u bytes)\n", a, reg, value, label, bytes);
                found++;
                break;
            }
        }
    }
    return found ? 0 : -1;
}

static int load_bin(uint8_t a, const uint8_t *d, size_t n, struct FwCtx *ctx, int *writes, int *skipped)
{
    if (n < 16 || memcmp(d, "WMDR", 4)) { fprintf(stderr, "bin: bad magic\n"); return -1; }
    uint32_t rev = be32(d + 8) & 0xff;
    if (rev < 1 || rev > 3) { fprintf(stderr, "bin: unsupported format %u\n", rev); return -1; }
    size_t pos = le32(d + 4);
    int blocks = 0;
    while (pos + 16 <= n) {
        // struct wmfw_coeff_item: le16 offset, le16 type, le32 id, le32 ver, le32 offset32, le32 len, data[]
        uint32_t type = le16(d + pos + 2), offset = le16(d + pos), id = le32(d + pos + 4), off32 = le32(d + pos + 12),
                 len = le32(d + pos + 16);
        if (pos + 20 > n || len > n - pos - 20) { fprintf(stderr, "bin: block %d overruns file\n", blocks); return -1; }
        const uint8_t *data = d + pos + 20;
        uint32_t reg = 0;
        int rtype = (int)type;
        if (type == (T_NAME << 8) || type == (T_INFO << 8) || type == (T_META << 8)) {
            /* no write */
        } else if (type == (T_ABS << 8)) {
            reg = offset;
        } else {
            if (type == T_XM_LONG || type == T_YM_LONG || type == T_XM_PACKED_LONG || type == T_YM_PACKED_LONG) {
                offset = off32;
                rtype = (int)(type & 0xff);
            }
            if (rtype == T_ADSP2_XM || rtype == T_ADSP2_YM || rtype == T_XM_PACKED || rtype == T_YM_PACKED ||
                rtype == T_PM_PACKED) {
                int found = 0;
                uint32_t base;
                type_base(rtype, &base);
                for (int i = 0; i < ctx->nalgs; i++) {
                    if (ctx->algs[i].id != id) continue;
                    uint32_t algBase = (rtype == T_ADSP2_XM || rtype == T_XM_PACKED) ? ctx->algs[i].xm : ctx->algs[i].ym;
                    reg = region_to_reg(rtype, base, algBase) + offset;
                    found = 1;
                    break;
                }
                if (!found) { fprintf(stderr, "bin block %d: no region for algorithm 0x%x (type 0x%x), skipped\n", blocks, id, rtype); (*skipped)++; }
            } else {
                fprintf(stderr, "bin block %d: unknown type 0x%x skipped\n", blocks, type);
                (*skipped)++;
            }
        }
        if (reg && len) {
            if (len & 3) { fprintf(stderr, "bin block %d: length %u not word aligned, skipped\n", blocks, len); (*skipped)++; }
            else {
                if (g_verbose) fprintf(stderr, "bin block %d type 0x%x alg 0x%x off %u len %u -> reg 0x%08x\n", blocks, type, id, offset, len, reg);
                if (wblock(a, reg, data, len)) return -1;
                (*writes)++;
            }
        }
        pos += (20 + len + 3) & ~3u;
        blocks++;
    }
    return 0;
}

// Linux order: shutdown ROM, download, system reset + boot wait, re-apply the register setup (the reset clears it),
// clear FIRMWARE_MISSING, audio re-init.
static int amp_fwload(uint8_t a, const uint8_t *wmfw, size_t wn, const uint8_t *bin, size_t bn, double volDb)
{
    int rc, writes = 0, skipped = 0;
    struct FwCtx ctx;
    uint32_t v = 0;
    if (!g_dry) {
        if ((rc = mbox(a, MB_SHUTDOWN))) return rc;
        if ((rc = poll(a, R_PM_CUR_STATE, 0xFFFFFFFF, 1, 250, &v))) { fprintf(stderr, "PM_CUR_STATE %u, wanted 1\n", v); return rc; }
    }
    if (load_wmfw(a, wmfw, wn, &writes)) return -1;
    if (read_algs(a, &ctx)) return -1;
    if (bin && load_bin(a, bin, bn, &ctx, &writes, &skipped)) return -1;
    fprintf(stderr, "amp 0x%02x: %d block write(s), %d skipped\n", a, writes, skipped);
    if (g_dry) return 0;
    // system reset: HALO_STATE = 0, then the reset command; no mailbox ack expected
    if ((rc = w32(a, R_HALO_STATE, 0))) return rc;
    if ((rc = w32(a, R_MBOX, MB_SYS_RESET))) return rc;
    sleepms(3);
    if ((rc = poll(a, R_HALO_STATE, 0xFFFFFFFF, 2, 300, &v)) && v < 2) { fprintf(stderr, "boot wait: HALO_STATE %u\n", v); return rc; }
    if ((rc = amp_init(a, volDb, 1))) return rc;
    if ((rc = ub(a, R_PROT_STATUS, 1, 0))) return rc;
    return mbox(a, MB_REINIT);
}


static uint8_t g_amps[2] = { 0x30, 0x31 };
static int g_namps = 2;

// ---- one-shot bring-up ---------------------------------------------------------------------------------------------------
// speaker-ID strap as read by the kext from GPIO 104: 0 / 1, or -1 when the kext could not read it
static int kext_spkid(void)
{
    uint8_t d[sizeof(struct SaInfo)];
    uint32_t l = 0;
    struct SaInfo si;
    if (sa_op(kSaOpInfo, 0, 0, 0, 0, 0, NULL, d, sizeof(d), &l) || l < sizeof(si)) return -1;
    memcpy(&si, d, sizeof(si));
    return (si.reserved & 1) ? (int)((si.reserved >> 1) & 1) : -1;
}

static int slurp_path(const char *dir, const char *name, uint8_t **buf, size_t *len)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", dir, name);
    *buf = slurp(path, len);
    return *buf ? 0 : -1;
}

static int each(int (*fn)(uint8_t));
static int amp_up(const char *fwdir, int spkid, double volDb, int forceFw)
{
    for (int k = 0; k < g_namps; k++) {
        uint8_t a = g_amps[k];
        uint32_t devid = 0, prot = 0;
        int rc = r32(a, R_DEVID, &devid);
        if (rc || devid != 0x00035A56) { fprintf(stderr, "amp 0x%02x: not a CS35L56 (rc %d, DEVID %08x)\n", a, rc, devid); return 1; }
        if ((rc = r32(a, R_PROT_STATUS, &prot))) return 1;
        int missing = prot & 1;
        printf("amp 0x%02x: firmware %s\n", a, missing ? "missing, downloading" : (forceFw ? "present, reloading (--force-fw)" : "already running"));
        if (missing || forceFw) {
            char name[96];
            uint8_t *w = NULL, *b = NULL;
            size_t wn = 0, bn = 0;
            snprintf(name, sizeof(name), "cs35l56-b0-dsp1-misc-10431044-spkid%d-amp%d.bin", spkid, k + 1);
            if (slurp_path(fwdir, "CS35L56_Rev3.11.16.wmfw", &w, &wn) || slurp_path(fwdir, name, &b, &bn)) return 1;
            rc = amp_fwload(a, w, wn, b, bn, volDb);
            free(w); free(b);
            if (rc) { fprintf(stderr, "amp 0x%02x: firmware download failed (%d)\n", a, rc); return 1; }
        } else if ((rc = amp_init(a, volDb, 0))) {
            fprintf(stderr, "amp 0x%02x: init failed (%d)\n", a, rc);
            return 1;
        }
    }
    for (int k = 0; k < g_namps; k++)
        if (amp_play(g_amps[k], 1u << k)) { fprintf(stderr, "amp 0x%02x: play failed\n", g_amps[k]); return 1; }
    return each(amp_status) ? 1 : 0;
}


// Keep the amps up across boot, sleep / wake and amp resets. Runs forever; the LaunchDaemon starts it at boot.
static int amp_daemon(const char *fwdir, int spkid, double volDb, const char *settingsPath)
{
    g_quiet = 1;
    int lastState = -1;
    double appliedVolume = NAN;
    int appliedMute = -1;
    RogAudioSettings settings = { .volume = volDb, .strength = 1, .noise = 1 };
    for (;;) {
        rog_settings_read(settingsPath, &settings);
        volDb = settings.volume;
        if (!g_conn && sa_open()) { sleep(5); continue; }
        uint32_t prot[2] = {0}, asp[2] = {0}, ps[2] = {0};
        int state = 2;                                  // 0 unreachable, 1 needs bring-up, 2 up
        for (int k = 0; k < g_namps; k++) {
            uint32_t devid = 0;
            uint8_t a = g_amps[k];
            if (r32(a, R_DEVID, &devid) || devid != 0x00035A56 ||
                r32(a, R_PROT_STATUS, &prot[k]) || r32(a, R_ASP1_ENABLES1, &asp[k]) ||
                r32(a, R_ACTUAL_PS, &ps[k])) { state = 0; break; }
            if ((prot[k] & 1) || (asp[k] & 0x30000) != 0x30000 || ps[k] != 0) state = 1;
        }
        if (state != lastState) {
            printf("strixamp: state %d (30: prot %08x asp %08x ps %u; 31: prot %08x asp %08x ps %u)\n",
                   state, prot[0], asp[0], ps[0], prot[1], asp[1], ps[1]);
            fflush(stdout); lastState = state;
        }
        if (state == 2 && (appliedVolume != volDb || appliedMute != settings.muted)) {
            int rc = 0;
            for (int k = 0; k < g_namps; k++) {
                // Mute first when requested; lower/set volume before an unmute.
                if (settings.muted) rc |= w32(g_amps[k], R_USER_MUTE, 1);
                rc |= w32(g_amps[k], R_USER_VOLUME, vol_raw(volDb));
                if (!settings.muted) rc |= w32(g_amps[k], R_USER_MUTE, 0);
            }
            if (!rc) {
                appliedVolume = volDb; appliedMute = settings.muted;
                printf("strixamp: controls volume %.1f dB mute %d\n", volDb, settings.muted); fflush(stdout);
            }
        }
        FILE *status = fopen("/var/run/strixamp-status.plist.tmp", "w");
        if (status) {
            fprintf(status, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
                "<key>state</key><integer>%d</integer><key>updated</key><real>%.0f</real>"
                "<key>volume</key><real>%.2f</real><key>muted</key><%s/>"
                "</dict></plist>", state, (double)time(NULL), appliedVolume == appliedVolume ? appliedVolume : volDb,
                appliedMute == 1 ? "true" : "false");
            fclose(status);
            rename("/var/run/strixamp-status.plist.tmp", "/var/run/strixamp-status.plist");
        }
        if (state == 1) {
            int sid = spkid >= 0 ? spkid : kext_spkid();
            if (sid < 0) { printf("strixamp: speaker ID unknown, not touching the amps\n"); fflush(stdout); sleep(30); continue; }
            g_quiet = 0;
            int rc = amp_up(fwdir, sid, volDb, 0);
            if (!rc && settings.muted)
                for (int k = 0; k < g_namps; k++) rc |= w32(g_amps[k], R_USER_MUTE, 1);
            appliedVolume = NAN; appliedMute = -1;
            g_quiet = 1;
            printf("strixamp: bring-up %s (speaker ID %d)\n", rc ? "FAILED" : "ok", sid);
            fflush(stdout);
            sleep(rc ? 30 : 2);
            lastState = -1;
            continue;
        }
        sleep(3);
    }
}

// ---- CLI ---------------------------------------------------------------------------------------------------------------

static int each(int (*fn)(uint8_t))
{
    int rc = 0;
    for (int i = 0; i < g_namps; i++) { int r = fn(g_amps[i]); if (r) rc = r; }
    return rc;
}

static void usage(void)
{
    fprintf(stderr,
        "usage: strixampctl [-a 30|31] [-v] [--dry] <command>\n"
        "  info | probe | status | diag (read-only clock, routing and IRQ snapshot)\n"
        "  fwdiag <wmfw>              read-only named DSP clock, mute, error and level controls\n"
        "  r <reg> [words] | w <reg> <val> | ub <reg> <mask> <val>\n"
        "  init [--vol dB]             register setup in the order of the Linux HDA driver (default -30 dB)\n"
        "  fwload [--vol dB] <wmfw> <bin 0x30> [bin 0x31]\n"
        "  daemon [same options as up]  keep the amps up: re-run up whenever they report firmware missing or are not playing\n"
        "  up [--vol dB] [--fw DIR] [--spkid 0|1] [--force-fw]\n"
        "                              one shot: firmware if the amps report it missing, register setup, play\n"
        "  play | pause | vol <dB> | mute <0|1>\n"
        "  --dry parses firmware files offline (fwload only)\n");
}

int main(int argc, char **argv)
{
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "-a") && i + 1 < argc) { g_amps[0] = (uint8_t)strtoul(argv[++i], NULL, 16); g_namps = 1; }
        else if (!strcmp(argv[i], "-v")) g_verbose = 1;
        else if (!strcmp(argv[i], "--dry")) g_dry = 1;
        else { usage(); return 2; }
    }
    if (i >= argc) { usage(); return 2; }
    const char *cmd = argv[i++];
    double vol = -30;
    if (!g_dry && strcmp(cmd, "daemon") && sa_open()) return 1;
    if (!strcmp(cmd, "diag")) return each(amp_diag) ? 1 : 0;
    if (!strcmp(cmd, "fwdiag")) {
        if (i + 1 != argc || g_dry) return 2;
        size_t n;
        uint8_t *data = slurp(argv[i], &n);
        if (!data) return 1;
        int failed = 0;
        for (int k = 0; k < g_namps; k++) if (amp_fwdiag(g_amps[k], data, n)) failed = 1;
        free(data);
        return failed;
    }

    if (!strcmp(cmd, "info")) {
        uint8_t d[sizeof(struct SaInfo)]; uint32_t l;
        if (sa_op(kSaOpInfo, 0, 0, 0, 0, 0, NULL, d, sizeof(d), &l)) return 1;
        struct SaInfo si; memcpy(&si, d, sizeof(si));
        printf("protocol %u, unsafe writes %s, address mask 0x%x, speaker ID %s\n", si.protoVersion, (si.flags & 1) ? "ON" : "off",
               si.i2cAddrMask, (si.reserved & 1) ? ((si.reserved & 2) ? "1" : "0") : "unknown");
        return 0;
    }
    if (!strcmp(cmd, "probe") || !strcmp(cmd, "status")) {
        uint8_t all[3] = { 0x30, 0x31, 0x3A };
        if (!strcmp(cmd, "probe")) {
            for (int k = 0; k < 3; k++) {
                uint32_t id = 0, rv = 0;
                int rc = r32(all[k], R_DEVID, &id);
                if (!rc) r32(all[k], R_REVID, &rv);
                printf("0x%02x: %s DEVID %08x REVID %02x\n", all[k], rc ? "no answer" : "ok", id, rv);
            }
            return 0;
        }
        return each(amp_status) ? 1 : 0;
    }
    if (!strcmp(cmd, "r") && i < argc) {
        uint32_t reg = strtoul(argv[i], NULL, 0), n = i + 1 < argc ? strtoul(argv[i + 1], NULL, 0) : 1;
        for (int k = 0; k < g_namps; k++)
            for (uint32_t j = 0; j < n; j++) {
                uint32_t v = 0;
                if (r32(g_amps[k], reg + 4 * j, &v)) return 1;
                printf("0x%02x [%08x] = %08x\n", g_amps[k], reg + 4 * j, v);
            }
        return 0;
    }
    if (!strcmp(cmd, "w") && i + 1 < argc) {
        uint32_t reg = strtoul(argv[i], NULL, 0), val = strtoul(argv[i + 1], NULL, 0);
        for (int k = 0; k < g_namps; k++) if (w32(g_amps[k], reg, val)) return 1;
        return 0;
    }
    if (!strcmp(cmd, "ub") && i + 2 < argc) {
        uint32_t reg = strtoul(argv[i], NULL, 0), mask = strtoul(argv[i + 1], NULL, 0), val = strtoul(argv[i + 2], NULL, 0);
        for (int k = 0; k < g_namps; k++) if (ub(g_amps[k], reg, mask, val)) return 1;
        return 0;
    }
    if (!strcmp(cmd, "init")) {
        if (i + 1 < argc && !strcmp(argv[i], "--vol")) vol = atof(argv[i + 1]);
        for (int k = 0; k < g_namps; k++) if (amp_init(g_amps[k], vol, 0)) return 1;
        return 0;
    }
    if (!strcmp(cmd, "play")) { for (int k = 0; k < g_namps; k++) if (amp_play(g_amps[k], 1u << k)) return 1; return 0; }
    if (!strcmp(cmd, "pause")) return each(amp_pause) ? 1 : 0;
    if (!strcmp(cmd, "vol") && i < argc) {
        double db = atof(argv[i]);
        for (int k = 0; k < g_namps; k++) if (ub(g_amps[k], R_USER_VOLUME, 0xFFC0, vol_raw(db))) return 1;
        return 0;
    }
    if (!strcmp(cmd, "mute") && i < argc) {
        for (int k = 0; k < g_namps; k++) if (w32(g_amps[k], R_USER_MUTE, atoi(argv[i]) ? 1 : 0)) return 1;
        return 0;
    }
    if (!strcmp(cmd, "up") || !strcmp(cmd, "daemon")) {
        const char *fwdir = getenv("STRIXAMP_FW") ? getenv("STRIXAMP_FW") : "/usr/local/share/strixamp/fw";
        int spkid = -1, force = 0;
        const char *settingsPath = NULL;
        for (; i < argc; i++) {
            if (!strcmp(argv[i], "--vol") && i + 1 < argc) vol = atof(argv[++i]);
            else if (!strcmp(argv[i], "--fw") && i + 1 < argc) fwdir = argv[++i];
            else if (!strcmp(argv[i], "--spkid") && i + 1 < argc) spkid = atoi(argv[++i]) ? 1 : 0;
            else if (!strcmp(argv[i], "--force-fw")) force = 1;
            else if (!strcmp(argv[i], "--settings") && i + 1 < argc) settingsPath = argv[++i];
            else { usage(); return 2; }
        }
        if (!strcmp(cmd, "daemon")) return amp_daemon(fwdir, spkid, vol, settingsPath);
        if (spkid < 0) spkid = kext_spkid();
        if (spkid < 0) { fprintf(stderr, "speaker ID unknown: the kext could not read GPIO 104; pass --spkid 0|1\n"); return 1; }
        printf("speaker ID %d, firmware dir %s, volume %.1f dB\n", spkid, fwdir, vol);
        return amp_up(fwdir, spkid, vol, force);
    }
    if (!strcmp(cmd, "fwload")) {
        if (i + 1 < argc && !strcmp(argv[i], "--vol")) { vol = atof(argv[i + 1]); i += 2; }
        if (i + 1 >= argc) { usage(); return 2; }
        size_t wn, b0n, b1n;
        uint8_t *w = slurp(argv[i], &wn), *b0 = slurp(argv[i + 1], &b0n);
        uint8_t *b1 = (i + 2 < argc) ? slurp(argv[i + 2], &b1n) : NULL;
        if (!w || !b0 || (i + 2 < argc && !b1)) return 1;
        int rc = 0;
        for (int k = 0; k < g_namps; k++) {
            const uint8_t *bin = (g_amps[k] == 0x31 && b1) ? b1 : b0;
            size_t bn = (g_amps[k] == 0x31 && b1) ? b1n : b0n;
            if (amp_fwload(g_amps[k], w, wn, bin, bn, vol)) rc = 1;
        }
        return rc;
    }
    usage();
    return 2;
}
