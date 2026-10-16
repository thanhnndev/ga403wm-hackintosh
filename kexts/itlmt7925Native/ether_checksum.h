// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Finalize ordinary IP checksums in our private Ethernet-frame copy. Core raw
// 802.11 TX has no checksum/TSO engine. Fragmented/opaque transports are left
// to the stack (hardware assists are advertised as zero).
#pragma once
#include <stdint.h>
namespace itl_checksum {
inline uint16_t read16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
inline void write16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)(v >> 8); p[1] = (uint8_t)v; }
inline uint32_t add(uint32_t s, const uint8_t *p, uint32_t n)
{
    while (n >= 2) { s += read16(p); p += 2; n -= 2; }
    if (n) s += (uint32_t)p[0] << 8;
    return s;
}
inline uint16_t finish(uint32_t s)
{
    while (s >> 16) s = (s & 65535u) + (s >> 16);
    return (uint16_t)~s;
}
inline bool transport(uint8_t *p, uint32_t n, uint8_t protocol, uint32_t pseudo)
{
    uint32_t check;
    if (protocol == 6) {
        if (n < 20 || (p[12] >> 4) < 5 || (uint32_t)(p[12] >> 4) * 4 > n) return false;
        check = 16;
    } else if (protocol == 17) {
        if (n < 8 || read16(p + 4) != n) return false;
        check = 6;
    } else if (protocol == 1 || protocol == 58) {
        if (n < 4) return false;
        check = 2;
    } else return true;
    write16(p + check, 0);
    uint16_t value = finish(add(pseudo, p, n));
    if (protocol == 17 && !value) value = 65535;
    write16(p + check, value);
    return true;
}
inline bool ethernet(uint8_t *frame, uint32_t length)
{
    if (length < 14) return false;
    uint32_t offset = 14;
    uint16_t type = read16(frame + 12);
    for (uint32_t tag = 0; tag < 2 && (type == 0x8100 || type == 0x88a8); tag++) {
        if (length - offset < 4) return false;
        type = read16(frame + offset + 2); offset += 4;
    }
    uint8_t *p = frame + offset;
    uint32_t available = length - offset;
    if (type == 0x0800) {
        if (available < 20 || (p[0] >> 4) != 4) return false;
        uint32_t header = (p[0] & 15) * 4, total = read16(p + 2);
        if (header < 20 || header > total || total > available) return false;
        write16(p + 10, 0); write16(p + 10, finish(add(0, p, header)));
        if (read16(p + 6) & 0x3fff) return true;
        if (p[9] != 1 && p[9] != 6 && p[9] != 17) return true;
        uint32_t n = total - header;
        uint32_t pseudo = p[9] == 1 ? 0 : add(0, p + 12, 8) + p[9] + n;
        return transport(p + header, n, p[9], pseudo);
    }
    if (type == 0x86dd) {
        if (available < 40 || (p[0] >> 4) != 6) return false;
        uint32_t total = 40 + read16(p + 4), header = 40;
        if (total > available) return false;
        uint8_t next = p[6];
        for (uint32_t ext = 0; ext < 8; ext++) {
            if (next == 43 || next == 44 || next == 51 || next == 50) return true;
            if (next != 0 && next != 60) break;
            if (total - header < 8) return false;
            uint32_t size = ((uint32_t)p[header + 1] + 1) * 8;
            if (size > total - header) return false;
            next = p[header]; header += size;
        }
        if (next != 6 && next != 17 && next != 58) return true;
        uint32_t n = total - header;
        return transport(p + header, n, next, add(0, p + 8, 32) + next + n);
    }
    return true; // ARP and non-IP frames have no IP checksum to finalize
}
}
