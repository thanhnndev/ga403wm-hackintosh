// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itl_wpa.cpp - see itl_wpa.h. Plain C++, no OS calls; also built by test/wpa_test.cpp on a normal host.
#include "itl_wpa.h"
#include <string.h>

// ------------------------------------------------------------------------------------------------
// SHA-1
// ------------------------------------------------------------------------------------------------
static inline uint32_t rol(uint32_t v, int s) { return (v << s) | (v >> (32 - s)); }

static void sha1_block(uint32_t h[5], const uint8_t *p)
{
    uint32_t w[80];
    for (int i = 0; i < 16; i++)
        w[i] = (uint32_t)p[4 * i] << 24 | (uint32_t)p[4 * i + 1] << 16 | (uint32_t)p[4 * i + 2] << 8 | p[4 * i + 3];
    for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20)      { f = (b & c) | (~b & d);           k = 0x5a827999; }
        else if (i < 40) { f = b ^ c ^ d;                    k = 0x6ed9eba1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d);  k = 0x8f1bbcdc; }
        else             { f = b ^ c ^ d;                    k = 0xca62c1d6; }
        uint32_t t = rol(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol(b, 30); b = a; a = t;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e;
}

void itl_sha1_init(itl_sha1 *c)
{
    c->h[0] = 0x67452301; c->h[1] = 0xefcdab89; c->h[2] = 0x98badcfe; c->h[3] = 0x10325476; c->h[4] = 0xc3d2e1f0;
    c->len = 0; c->n = 0;
}

void itl_sha1_update(itl_sha1 *c, const void *d, size_t n)
{
    const uint8_t *p = (const uint8_t *)d;
    c->len += n;
    while (n) {
        size_t k = 64 - c->n;
        if (k > n) k = n;
        memcpy(c->buf + c->n, p, k);
        c->n += (uint32_t)k; p += k; n -= k;
        if (c->n == 64) { sha1_block(c->h, c->buf); c->n = 0; }
    }
}

void itl_sha1_final(itl_sha1 *c, uint8_t out[20])
{
    uint64_t bits = c->len * 8;
    uint8_t pad = 0x80;
    itl_sha1_update(c, &pad, 1);
    pad = 0;
    while (c->n != 56) itl_sha1_update(c, &pad, 1);
    uint8_t lb[8];
    for (int i = 0; i < 8; i++) lb[i] = (uint8_t)(bits >> (56 - 8 * i));
    itl_sha1_update(c, lb, 8);
    for (int i = 0; i < 5; i++) {
        out[4 * i] = (uint8_t)(c->h[i] >> 24); out[4 * i + 1] = (uint8_t)(c->h[i] >> 16);
        out[4 * i + 2] = (uint8_t)(c->h[i] >> 8); out[4 * i + 3] = (uint8_t)c->h[i];
    }
}

// ------------------------------------------------------------------------------------------------
// HMAC-SHA1, PBKDF2, PRF
// ------------------------------------------------------------------------------------------------
void itl_hmac_sha1(const uint8_t *key, size_t klen, const uint8_t *d1, size_t n1, const uint8_t *d2, size_t n2,
                   uint8_t out[20])
{
    uint8_t k[64], ip[64], op[64], inner[20];
    memset(k, 0, sizeof(k));
    if (klen > 64) { itl_sha1 c; itl_sha1_init(&c); itl_sha1_update(&c, key, klen); itl_sha1_final(&c, k); }
    else memcpy(k, key, klen);
    for (int i = 0; i < 64; i++) { ip[i] = k[i] ^ 0x36; op[i] = k[i] ^ 0x5c; }
    itl_sha1 c;
    itl_sha1_init(&c); itl_sha1_update(&c, ip, 64);
    if (n1) itl_sha1_update(&c, d1, n1);
    if (n2) itl_sha1_update(&c, d2, n2);
    itl_sha1_final(&c, inner);
    itl_sha1_init(&c); itl_sha1_update(&c, op, 64); itl_sha1_update(&c, inner, 20); itl_sha1_final(&c, out);
}

void itl_pbkdf2_sha1(const char *pass, size_t plen, const uint8_t *salt, size_t slen, uint32_t iter, uint8_t *out,
                     size_t olen)
{
    for (uint32_t blk = 1; olen; blk++) {
        uint8_t ctr[4] = { (uint8_t)(blk >> 24), (uint8_t)(blk >> 16), (uint8_t)(blk >> 8), (uint8_t)blk };
        uint8_t u[20], t[20];
        itl_hmac_sha1((const uint8_t *)pass, plen, salt, slen, ctr, 4, u);
        memcpy(t, u, 20);
        for (uint32_t i = 1; i < iter; i++) {
            itl_hmac_sha1((const uint8_t *)pass, plen, u, 20, nullptr, 0, u);
            for (int j = 0; j < 20; j++) t[j] ^= u[j];
        }
        size_t k = olen < 20 ? olen : 20;
        memcpy(out, t, k);
        out += k; olen -= k;
    }
}

void itl_prf_sha1(const uint8_t *key, size_t klen, const char *label, const uint8_t *data, size_t dlen, uint8_t *out,
                  size_t olen)
{
    uint8_t buf[192];
    size_t ll = strlen(label);
    if (ll + 1 + dlen + 1 > sizeof(buf)) return;
    memcpy(buf, label, ll);
    buf[ll] = 0;
    memcpy(buf + ll + 1, data, dlen);
    size_t m = ll + 1 + dlen;
    for (uint8_t i = 0; olen; i++) {
        uint8_t h[20];
        buf[m] = i;
        itl_hmac_sha1(key, klen, buf, m + 1, nullptr, 0, h);
        size_t k = olen < 20 ? olen : 20;
        memcpy(out, h, k);
        out += k; olen -= k;
    }
}

void itl_wpa_pmk(const char *pass, const uint8_t *ssid, size_t ssidlen, uint8_t pmk[32])
{
    itl_pbkdf2_sha1(pass, strlen(pass), ssid, ssidlen, 4096, pmk, 32);
}

void itl_wpa_ptk(const uint8_t pmk[32], const uint8_t aa[6], const uint8_t spa[6], const uint8_t anonce[32],
                 const uint8_t snonce[32], itl_ptk *ptk, bool tkip)
{
    uint8_t d[76], out[64];
    const uint8_t *lo = memcmp(aa, spa, 6) < 0 ? aa : spa, *hi = lo == aa ? spa : aa;
    memcpy(d, lo, 6); memcpy(d + 6, hi, 6);
    const uint8_t *nlo = memcmp(anonce, snonce, 32) < 0 ? anonce : snonce, *nhi = nlo == anonce ? snonce : anonce;
    memcpy(d + 12, nlo, 32); memcpy(d + 44, nhi, 32);
    itl_prf_sha1(pmk, 32, "Pairwise key expansion", d, sizeof(d), out, tkip ? 64 : 48);
    memcpy(ptk->kck, out, 16); memcpy(ptk->kek, out + 16, 16); memcpy(ptk->tk, out + 32, 16);
    bzero(ptk->mic, sizeof(ptk->mic));
    if (tkip) memcpy(ptk->mic, out + 48, 16);                // TX MIC key then RX MIC key, the order the PRF produces
}

// ------------------------------------------------------------------------------------------------
// AES-128 (decrypt) and RFC 3394 unwrap. The S-box is computed, not typed in.
// ------------------------------------------------------------------------------------------------
static uint8_t g_sbox[256], g_isbox[256];
static bool g_aes_ready;

static uint8_t xt(uint8_t x) { return (uint8_t)((x << 1) ^ ((x & 0x80) ? 0x1b : 0)); }
static uint8_t gmul(uint8_t a, uint8_t b)
{
    uint8_t r = 0;
    while (b) { if (b & 1) r ^= a; a = xt(a); b >>= 1; }
    return r;
}

static void aes_init()
{
    if (g_aes_ready) return;
    // multiplicative inverse by walking the generator 3: p *= 3, q /= 3 stay inverse of each other
    uint8_t p = 1, q = 1;
    do {
        p = (uint8_t)(p ^ xt(p));                       // p *= 3
        q ^= (uint8_t)(q << 1); q ^= (uint8_t)(q << 2); q ^= (uint8_t)(q << 4);
        if (q & 0x80) q ^= 0x09;                        // q /= 3
        uint8_t x = (uint8_t)(q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4));
        g_sbox[p] = x ^ 0x63;
    } while (p != 1);
    g_sbox[0] = 0x63;
    for (int i = 0; i < 256; i++) g_isbox[g_sbox[i]] = (uint8_t)i;
    g_aes_ready = true;
}

struct aes128 { uint8_t rk[176]; };

static void aes_expand(aes128 *k, const uint8_t key[16])
{
    aes_init();
    memcpy(k->rk, key, 16);
    uint8_t rcon = 1;
    for (int i = 16; i < 176; i += 4) {
        uint8_t t[4]; memcpy(t, k->rk + i - 4, 4);
        if (i % 16 == 0) {
            uint8_t a = t[0];
            t[0] = g_sbox[t[1]] ^ rcon; t[1] = g_sbox[t[2]]; t[2] = g_sbox[t[3]]; t[3] = g_sbox[a];
            rcon = xt(rcon);
        }
        for (int j = 0; j < 4; j++) k->rk[i + j] = k->rk[i - 16 + j] ^ t[j];
    }
}

static void aes_dec_block(const aes128 *k, const uint8_t in[16], uint8_t out[16])
{
    uint8_t s[16];
    for (int i = 0; i < 16; i++) s[i] = in[i] ^ k->rk[160 + i];
    for (int r = 9; r >= 0; r--) {
        // inverse ShiftRows
        uint8_t t[16];
        for (int c = 0; c < 4; c++) for (int row = 0; row < 4; row++) t[((c + row) & 3) * 4 + row] = s[c * 4 + row];
        // inverse SubBytes + AddRoundKey
        for (int i = 0; i < 16; i++) s[i] = g_isbox[t[i]] ^ k->rk[r * 16 + i];
        if (r) {   // inverse MixColumns
            for (int c = 0; c < 4; c++) {
                uint8_t a0 = s[c * 4], a1 = s[c * 4 + 1], a2 = s[c * 4 + 2], a3 = s[c * 4 + 3];
                s[c * 4]     = gmul(a0, 14) ^ gmul(a1, 11) ^ gmul(a2, 13) ^ gmul(a3, 9);
                s[c * 4 + 1] = gmul(a0, 9)  ^ gmul(a1, 14) ^ gmul(a2, 11) ^ gmul(a3, 13);
                s[c * 4 + 2] = gmul(a0, 13) ^ gmul(a1, 9)  ^ gmul(a2, 14) ^ gmul(a3, 11);
                s[c * 4 + 3] = gmul(a0, 11) ^ gmul(a1, 13) ^ gmul(a2, 9)  ^ gmul(a3, 14);
            }
        }
    }
    memcpy(out, s, 16);
}

int itl_aes128_unwrap(const uint8_t kek[16], const uint8_t *in, size_t inlen, uint8_t *out)
{
    if (inlen < 24 || inlen % 8 || inlen > 8 + 8 * 64) return -1;
    size_t n = inlen / 8 - 1;
    aes128 k; aes_expand(&k, kek);
    uint8_t a[8]; memcpy(a, in, 8);
    memcpy(out, in + 8, 8 * n);
    for (int j = 5; j >= 0; j--) {
        for (size_t i = n; i >= 1; i--) {
            uint32_t t = (uint32_t)(n * (size_t)j + i);
            uint8_t b[16];
            memcpy(b, a, 8);
            b[7] ^= (uint8_t)t; b[6] ^= (uint8_t)(t >> 8); b[5] ^= (uint8_t)(t >> 16); b[4] ^= (uint8_t)(t >> 24);
            memcpy(b + 8, out + 8 * (i - 1), 8);
            aes_dec_block(&k, b, b);
            memcpy(a, b, 8);
            memcpy(out + 8 * (i - 1), b + 8, 8);
        }
    }
    for (int i = 0; i < 8; i++) if (a[i] != 0xa6) return -2;
    return 0;
}

// ------------------------------------------------------------------------------------------------
// EAPOL-Key
// ------------------------------------------------------------------------------------------------
static uint16_t be16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }

int itl_eapol_parse(const uint8_t *p, size_t len, itl_eapol_key *k)
{
    if (len < 99 || p[1] != 3) return -1;
    size_t blen = be16(p + 2);
    if (blen + 4 > len || blen < 95) return -2;
    if (p[4] != 2 && p[4] != 254) return -3;
    k->info = be16(p + 5);
    k->keylen = be16(p + 7);
    memcpy(k->replay, p + 9, 8);
    memcpy(k->nonce, p + 17, 32);
    memcpy(k->iv, p + 49, 16);
    memcpy(k->rsc, p + 65, 8);
    memcpy(k->mic, p + 81, 16);
    k->datalen = be16(p + 97);
    if ((size_t)99 + k->datalen > blen + 4) return -4;
    k->data = p + 99;
    return 0;
}

size_t itl_eapol_build(uint8_t *out, uint16_t info, uint16_t keylen, const uint8_t replay[8], const uint8_t nonce[32],
                       const uint8_t *data, uint16_t datalen)
{
    memset(out, 0, 99);
    out[0] = 2; out[1] = 3;
    uint16_t body = (uint16_t)(95 + datalen);
    out[2] = (uint8_t)(body >> 8); out[3] = (uint8_t)body;
    out[4] = 2;
    out[5] = (uint8_t)(info >> 8); out[6] = (uint8_t)info;
    out[7] = (uint8_t)(keylen >> 8); out[8] = (uint8_t)keylen;
    memcpy(out + 9, replay, 8);
    memcpy(out + 17, nonce, 32);
    out[97] = (uint8_t)(datalen >> 8); out[98] = (uint8_t)datalen;
    if (datalen) memcpy(out + 99, data, datalen);
    return (size_t)99 + datalen;
}

void itl_eapol_mic(const uint8_t kck[16], uint8_t *frame, size_t len)
{
    uint8_t h[20];
    memset(frame + 81, 0, 16);
    itl_hmac_sha1(kck, 16, frame, len, nullptr, 0, h);
    memcpy(frame + 81, h, 16);
}

bool itl_eapol_mic_ok(const uint8_t kck[16], const uint8_t *frame, size_t len)
{
    uint8_t tmp[512], h[20];
    if (len > sizeof(tmp) || len < 99) return false;
    memcpy(tmp, frame, len);
    memset(tmp + 81, 0, 16);
    itl_hmac_sha1(kck, 16, tmp, len, nullptr, 0, h);
    uint8_t d = 0;
    for (int i = 0; i < 16; i++) d |= h[i] ^ frame[81 + i];
    return d == 0;
}
