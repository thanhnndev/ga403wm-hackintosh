#!/usr/bin/env python3
"""Disassemble functions of a kext that lives inside a macOS kernel collection.

otool/objdump cannot address a fileset entry, so the kext's __TEXT bytes are wrapped into a
throw-away Mach-O (same vmaddr, symbols of the requested range) and handed to otool -tV.
Rip-relative references into the kext's GOT are annotated with the chained-fixup target name.

Usage: kc_disasm.py --bundle com.apple.driver.AppleParavirtGPU --sym '^__ZN24AppleParavirtDisplayPipe17submit' [--kc ...]
"""
import argparse, os, re, struct, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ioaccel_layout as L

BKC = "/System/Library/KernelCollections/BootKernelExtensions.kc"


def build_macho(text_va, text_bytes, syms, path):
    """minimal x86_64 MH_OBJECT-ish executable: one segment, one __text section, LC_SYMTAB."""
    strtab = b"\0"
    nlist = b""
    for name, addr in syms:
        nlist += struct.pack("<IBBHQ", len(strtab), 0x0F, 1, 0, addr)   # N_SECT|N_EXT, sect 1
        strtab += name.encode() + b"\0"
    nsect = 1
    seg_size = 72 + 80 * nsect
    sym_size = 24
    hdr_size = 32
    ncmds, sizeofcmds = 2, seg_size + sym_size
    data_off = (hdr_size + sizeofcmds + 15) & ~15
    sym_off = data_off + len(text_bytes)
    sym_off = (sym_off + 7) & ~7
    str_off = sym_off + len(nlist)
    hdr = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x01000007, 3, 2, ncmds, sizeofcmds, 0, 0)
    seg = struct.pack("<II16sQQQQiiII", 0x19, seg_size, b"__TEXT", text_va, len(text_bytes),
                      data_off, len(text_bytes), 7, 5, nsect, 0)
    sect = struct.pack("<16s16sQQIIIIIIII", b"__text", b"__TEXT", text_va, len(text_bytes),
                       data_off, 4, 0, 0, 0x80000400, 0, 0, 0)
    st = struct.pack("<IIIIII", 0x2, sym_size, sym_off, len(syms), str_off, len(strtab))
    out = hdr + seg + sect + st
    out += b"\0" * (data_off - len(out)) + text_bytes
    out += b"\0" * (sym_off - len(out)) + nlist + strtab
    open(path, "wb").write(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", default="com.apple.driver.AppleParavirtGPU")
    ap.add_argument("--sym", action="append", required=True, help="regex on mangled symbol, repeatable")
    ap.add_argument("--kc", default=L.DEFAULT_KC)
    a = ap.parse_args()
    kc = L.KC(a.kc)
    by_name, by_addr = kc.symbols()
    bk = KCb = L.KC(BKC)
    n2, a2 = bk.symbols()
    for k, v in a2.items():
        by_addr.setdefault(k, v)
    segs = kc.kext_segments(a.bundle)
    tseg = [s for s in segs if s[0] in ("__TEXT_EXEC", "__TEXT")][0]
    lo, hi = tseg[1], tseg[1] + tseg[2]
    text = kc.read(lo, hi - lo)
    syms = sorted((n, v) for n, v in by_name.items() if lo <= v < hi and not n.endswith("cold.1"))
    wanted = [re.compile(r) for r in a.sym]
    todo = [(n, v) for n, v in syms if any(w.search(n) for w in wanted)]
    addrs = sorted(v for _, v in syms)
    bases = {1: 0, 0: bk.segs[0][1] - 0x100000}
    tmp = tempfile.mkdtemp(prefix="kcdis-")
    path = os.path.join(tmp, "k.macho")
    build_macho(lo, text, syms, path)
    dm = subprocess.run(["c++filt", "-_"], input="\n".join(n for n, _ in todo), capture_output=True, text=True).stdout.split("\n")
    for (n, v), dn in zip(todo, dm):
        import bisect
        i = bisect.bisect_right(addrs, v)
        end = addrs[i] if i < len(addrs) else hi
        r = subprocess.run(["otool", "-arch", "x86_64", "-tV", path], capture_output=True, text=True).stdout
        # otool prints the whole segment; cut the function by address
        print("\n=== %s  [%#x..%#x) %d bytes\n" % (dn, v, end, end - v))
        for line in r.splitlines():
            m = re.match(r"^([0-9a-f]{16})\s", line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            if not (v <= addr < end):
                continue
            ann = ""
            c = re.search(r"\b(?:callq|jmp|jmpq|je|jne|jb|jae|jbe|ja|jl|jg|jle|jge|js|jns)\s+(0x[0-9a-f]+)\s*$", line)
            if c:
                nm = by_addr.get(int(c.group(1), 16))
                if nm:
                    ann = "   ; " + nm
            g = re.search(r"## (0x[0-9a-f]+)", line)
            if g:
                ta = int(g.group(1), 16)
                nm = by_addr.get(ta)
                if nm:
                    ann = "   ; " + nm
                else:
                    raw = kc.u64(ta)
                    if raw and (raw >> 30) & 3 in bases:
                        p = bases[(raw >> 30) & 3] + (raw & 0x3FFFFFFF)
                        nm = by_addr.get(p)
                        if nm:
                            ann = "   ; GOT -> " + nm
                        else:
                            s = kc.read(ta, 40)
                            if s and re.match(rb"^[\x20-\x7e]{3,}\0", s):
                                ann = '   ; "%s"' % s.split(b"\0")[0].decode()
            print(line + ann)


if __name__ == "__main__":
    main()
