#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# NMXAccel arms the 890M display pipe only when IOKitBuildVersion equals the reviewed 25G241 kernel string
# (nvrm-accel.cpp: "native framebuffer watch ... not on reviewed kernel profile"). On another build, such as 25G332,
# WindowServer gets no Metal device and composites on the CPU. The gate protects private IOAcceleratorFamily2 offsets,
# so only retarget it after checking that the family version is the same (487.4.4 on both).
# This swaps the string for the target kernel's (same length) and gives the binary a new LC_UUID, so auxguard's
# kccheck sees the change and relinks the AuxKC at the next boot.
#   nmxaccel-kernel-gate.py <NMXAccel binary> <target kernel file>      (backup next to it: NMXAccel.gate-orig)
#   nmxaccel-kernel-gate.py --undo <NMXAccel binary>
import re, shutil, struct, sys

def kver(path):
    m = re.search(rb'Darwin Kernel Version [^\0]*?RELEASE_X86_64', open(path, 'rb').read())
    if not m: sys.exit('no kernel version string in ' + path)
    return m.group(0)

if sys.argv[1] == '--undo':
    b = sys.argv[2]; shutil.copy2(b + '.gate-orig', b); print('restored', b); sys.exit(0)
b, kern = sys.argv[1], sys.argv[2]
d = bytearray(open(b, 'rb').read())
new = kver(kern)
old = re.search(rb'Darwin Kernel Version 25\.[^\0]*?RELEASE_X86_64', bytes(d))
if not old: sys.exit('gate string not found in ' + b)
old = old.group(0)
if old == new: sys.exit('already gated on ' + new.decode())
if len(old) != len(new): sys.exit('length differs: %d vs %d' % (len(old), len(new)))
if bytes(d).count(old) != 1: sys.exit('gate string is not unique')
shutil.copy2(b, b + '.gate-orig')
i = bytes(d).index(old); d[i:i + len(old)] = new
magic, cpu, sub, ft, ncmds, size, flags, res = struct.unpack_from('<IiiIIIII', d, 0)
if magic != 0xfeedfacf: sys.exit('not a 64-bit Mach-O')
off = 32
for _ in range(ncmds):
    cmd, cs = struct.unpack_from('<II', d, off)
    if cmd == 0x1b: d[off + 8 + 15] ^= 0x01; break      # LC_UUID: new identity for the changed binary
    off += cs
else: sys.exit('no LC_UUID')
open(b, 'wb').write(d)
print('gate', old.decode(), '->', new.decode())
