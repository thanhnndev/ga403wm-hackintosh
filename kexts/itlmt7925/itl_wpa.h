// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itl_wpa.h - WPA2-PSK primitives with no OS dependencies (compiles in the kext and in the host test, test/wpa_test.cpp).
//   SHA-1, HMAC-SHA1, PBKDF2-HMAC-SHA1, IEEE 802.11i PRF, AES-128 (decrypt only), RFC 3394 key unwrap,
//   PTK derivation and EAPOL-Key (RSN, descriptor version 2) parsing / building.
#ifndef ITL_WPA_H
#define ITL_WPA_H

#include <stdint.h>
#include <stddef.h>

struct itl_sha1 { uint32_t h[5]; uint64_t len; uint8_t buf[64]; uint32_t n; };
void itl_sha1_init(itl_sha1 *c);
void itl_sha1_update(itl_sha1 *c, const void *d, size_t n);
void itl_sha1_final(itl_sha1 *c, uint8_t out[20]);

void itl_hmac_sha1(const uint8_t *key, size_t klen, const uint8_t *d1, size_t n1, const uint8_t *d2, size_t n2,
                   uint8_t out[20]);
void itl_pbkdf2_sha1(const char *pass, size_t plen, const uint8_t *salt, size_t slen, uint32_t iter, uint8_t *out,
                     size_t olen);
// IEEE 802.11-2016 12.7.1.2: PRF-n(K, label, A || 0x00 || B)
void itl_prf_sha1(const uint8_t *key, size_t klen, const char *label, const uint8_t *data, size_t dlen, uint8_t *out,
                  size_t olen);

// AES-128 key unwrap (RFC 3394). in/out: 8 bytes of integrity block less than `inlen`; returns 0 on success.
int itl_aes128_unwrap(const uint8_t kek[16], const uint8_t *in, size_t inlen, uint8_t *out);

// PMK from passphrase / SSID
void itl_wpa_pmk(const char *pass, const uint8_t *ssid, size_t ssidlen, uint8_t pmk[32]);

// PTK = PRF-384(PMK, "Pairwise key expansion", min(AA,SPA) || max(AA,SPA) || min(ANonce,SNonce) || max(ANonce,SNonce))
// CCMP needs 384 bits; TKIP 512 (the extra 128 are the two MIC keys, TX first, as the AP computes them).
struct itl_ptk { uint8_t kck[16]; uint8_t kek[16]; uint8_t tk[16]; uint8_t mic[16]; };
void itl_wpa_ptk(const uint8_t pmk[32], const uint8_t aa[6], const uint8_t spa[6], const uint8_t anonce[32],
                 const uint8_t snonce[32], itl_ptk *ptk, bool tkip);

// EAPOL-Key (802.1X, type 3), RSN descriptor 2
#define ITL_KI_VER_MASK   0x0007
#define ITL_KI_PAIRWISE   0x0008
#define ITL_KI_INSTALL    0x0040
#define ITL_KI_ACK        0x0080
#define ITL_KI_MIC        0x0100
#define ITL_KI_SECURE     0x0200
#define ITL_KI_ERROR      0x0400
#define ITL_KI_REQUEST    0x0800
#define ITL_KI_ENCRYPTED  0x1000

struct itl_eapol_key {
    uint16_t info;
    uint16_t keylen;
    uint8_t replay[8];
    uint8_t nonce[32];
    uint8_t iv[16];
    uint8_t rsc[8];
    uint8_t mic[16];
    const uint8_t *data;        // points into the frame
    uint16_t datalen;
};

// `p` is the EAPOL packet (version byte first). Returns 0 and fills `k` on success.
int itl_eapol_parse(const uint8_t *p, size_t len, itl_eapol_key *k);
// Builds an EAPOL-Key frame of the given shape into out (>= 99 + datalen) and returns its length. The MIC field is zero;
// call itl_eapol_mic afterwards.
size_t itl_eapol_build(uint8_t *out, uint16_t info, uint16_t keylen, const uint8_t replay[8], const uint8_t nonce[32],
                       const uint8_t *data, uint16_t datalen);
// MIC = first 16 bytes of HMAC-SHA1(KCK, frame with zero MIC); written into the frame at the MIC offset (81).
void itl_eapol_mic(const uint8_t kck[16], uint8_t *frame, size_t len);
// Verify the MIC of a received frame (does not modify it).
bool itl_eapol_mic_ok(const uint8_t kck[16], const uint8_t *frame, size_t len);

#endif
