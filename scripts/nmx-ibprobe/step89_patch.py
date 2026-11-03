#!/usr/bin/env python3
# Helpers for scripts/macos-patch-nmx-step89.sh.
#   step89_patch.py NMXGPU <dir with cave.bin, cave-step86.bin>    patch NMXGPU in place (TTM order 0 + ibprobe v2)
#   step89_patch.py --check-accel NMXAccel                          refuse an NMXAccel without the sleeping beam wait
#   step89_patch.py --check-kc KC NMXGPU NMXAccel                   the collection holds the bytes now on disk
import hashlib
import re
import subprocess
import sys

TTM_AT = 0x5fd9b1
TTM_OLD = bytes.fromhex('83f80a41bc0a000000')   # cmpl $0xa,%eax ; movl $0xa,%r12d
TTM_NEW = bytes.fromhex('83f80041bc00000000')   # cmpl $0x0,%eax ; movl $0x0,%r12d
CAVE_AT = 0x5aa5a0
IBPROBE_V2 = b'NullMoth ibprobe: va=%llx cmd_bufsz=%x left=%x pasid=%x vm=%p'


def patch(path, cavedir):
    d = bytearray(open(path, 'rb').read())
    old_cave = open(cavedir + '/cave-step86.bin', 'rb').read()
    new_cave = open(cavedir + '/cave.bin', 'rb').read()
    # the Step86 cave is shorter; the bytes after it belong to the same dead SI function and are overwritten too
    old_span = old_cave + bytes(d[CAVE_AT + len(old_cave):CAVE_AT + len(new_cave)])
    patches = [(TTM_AT, TTM_OLD, TTM_NEW), (CAVE_AT, old_span, new_cave)]
    if all(bytes(d[o:o + len(n)]) == n for o, _, n in patches):
        print('NMXGPU already patched')
        return
    for o, want, new in patches:
        got = bytes(d[o:o + len(new)])
        if got != want and got != new:
            sys.exit(f'bytes at {o:#x} are not the expected build -- not touching it')
    for o, _, new in patches:
        d[o:o + len(new)] = new
    open(path, 'wb').write(d)
    print('NMXGPU patched: ttm order 0, ibprobe v2; sha256', hashlib.sha256(d).hexdigest())


def check_accel(path):
    d = open(path, 'rb').read()
    if d[:4] != b'\xcf\xfa\xed\xfe':
        sys.exit('not a 64-bit Mach-O')
    if d.count(b'\0NMXAMDFB\0') != 1 or b'iop: beam: OTG%u' not in d:
        sys.exit('not the NMXAMDFB beam-paced NMXAccel')
    if b'ns/line' not in d:
        sys.exit('CI NMXAccel predates the sleeping beam wait')
    print('CI NMXAccel ok')


def uuid(path):
    out = subprocess.run(['/usr/bin/otool', '-l', path], capture_output=True, text=True).stdout
    return re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out).group(1)


def check_kc(kc_path, gpu, accel):
    kc = open(kc_path, 'rb').read()
    b = open(gpu, 'rb').read()
    probes = {'NMXGPU ttm order code': b[TTM_AT - 9:TTM_AT + 17],
              'NMXGPU uuid': bytes.fromhex(uuid(gpu).replace('-', '')),
              'NMXAccel uuid': bytes.fromhex(uuid(accel).replace('-', ''))}
    if IBPROBE_V2 in b:
        probes['ibprobe v2'] = IBPROBE_V2
    ok = True
    for k, v in probes.items():
        hit = v in kc
        print(f'{k}: {"present" if hit else "MISSING"} in the new collection')
        ok = ok and hit
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-accel':
        check_accel(sys.argv[2])
    elif sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        patch(sys.argv[1], sys.argv[2])
