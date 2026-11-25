#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Assembles acpi/SSDT-S0IDLE.dsl by hand (no iasl on this Mac) into efi/OC/ACPI/SSDT-S0IDLE.aml."""
import os, struct, sys

def pkg(body):                          # PkgLength + body, 1- or 2-byte encoding
    n = len(body) + 1
    if n <= 0x3f:
        return bytes([n]) + body
    n += 1
    assert n <= 0xfff
    return bytes([0x40 | (n & 0xf), n >> 4]) + body

osi = b'\x5c_OSI' + b'\x0d' + b'Darwin\x00'        # \_OSI ("Darwin")
if_ = b'\xa0' + pkg(osi + b'\xa4\x01')               # If (...) { Return (One) }
meth = b'\x14' + pkg(b'LPS0' + b'\x00' + if_ + b'\xa4\x00')   # Method (LPS0, 0) { ...; Return (Zero) }
scope = b'\x10' + pkg(b'\x5c_SB_' + meth)             # Scope (\_SB)
hdr = bytearray(b'SSDT' + struct.pack('<I', 36 + len(scope)) + b'\x02\x00' + b'GA403 ' + b'S0IDLE  '
                + struct.pack('<I', 0) + b'INTL' + struct.pack('<I', 0x20200925))
t = hdr + scope
t[9] = (-sum(t)) & 0xff
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'efi/OC/ACPI/SSDT-S0IDLE.aml')
open(out, 'wb').write(bytes(t))
print(out, len(t), 'bytes, checksum ok' if sum(t) & 0xff == 0 else 'BAD CHECKSUM')
