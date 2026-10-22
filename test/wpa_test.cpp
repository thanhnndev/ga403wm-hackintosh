// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Host test for kexts/itlmt7925/itl_wpa.cpp. Build: c++ -std=c++17 -I../kexts/itlmt7925 wpa_test.cpp ../kexts/itlmt7925/itl_wpa.cpp -o wpa_test
#include "itl_wpa.h"
#include "wpa_vectors.h"
#include <stdio.h>
#include <string.h>

static int fails;
#define CHECK(c, what) do { if (!(c)) { printf("FAIL %s\n", what); fails++; } else printf("ok   %s\n", what); } while (0)

int main()
{
    uint8_t h[20];
    itl_sha1 c; itl_sha1_init(&c); itl_sha1_update(&c, v_sha_in, sizeof(v_sha_in)); itl_sha1_final(&c, h);
    CHECK(!memcmp(h, v_sha_out, 20), "sha1");
    itl_hmac_sha1(v_hmac_key, sizeof(v_hmac_key), v_hmac_d1, sizeof(v_hmac_d1), v_hmac_d2, sizeof(v_hmac_d2), h);
    CHECK(!memcmp(h, v_hmac_out, 20), "hmac-sha1 (long key, two parts)");
    uint8_t pmk[32];
    char pass[sizeof(v_pass) + 1];
    memcpy(pass, v_pass, sizeof(v_pass));
    pass[sizeof(v_pass)] = 0;           // itl_wpa_pmk takes a C string
    itl_wpa_pmk(pass, v_ssid, sizeof(v_ssid), pmk);
    CHECK(!memcmp(pmk, v_pmk, 32), "pbkdf2 pmk");
    itl_ptk ptk;
    itl_wpa_ptk(pmk, v_aa, v_spa, v_an, v_sn, &ptk, false);     // the vector is a CCMP (384-bit) PTK
    CHECK(!memcmp(&ptk, v_ptk, 48), "ptk prf");
    uint8_t out[64];
    CHECK(itl_aes128_unwrap(v_kek, v_wrapped, sizeof(v_wrapped), out) == 0 && !memcmp(out, v_unwrapped, sizeof(v_unwrapped)),
          "aes unwrap");
    uint8_t bad[sizeof(v_wrapped)]; memcpy(bad, v_wrapped, sizeof(bad)); bad[9] ^= 1;
    CHECK(itl_aes128_unwrap(v_kek, bad, sizeof(bad), out) != 0, "aes unwrap rejects corrupted input");
    CHECK(itl_eapol_mic_ok(v_ptk, v_eapol, sizeof(v_eapol)), "eapol mic verify");
    itl_eapol_key k;
    CHECK(itl_eapol_parse(v_eapol, sizeof(v_eapol), &k) == 0 && k.info == 0x010a && k.datalen == 8, "eapol parse");
    uint8_t f[200];
    size_t n = itl_eapol_build(f, k.info, k.keylen, k.replay, k.nonce, k.data, k.datalen);
    memcpy(f + 49, k.iv, 16); memcpy(f + 65, k.rsc, 8);
    itl_eapol_mic(v_ptk, f, n);
    CHECK(n == sizeof(v_eapol) && !memcmp(f, v_eapol, n), "eapol build + mic matches reference");
    return fails ? 1 : 0;
}
