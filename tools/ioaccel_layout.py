#!/usr/bin/env python3
"""Extract the IOAcceleratorFamily2 C++ ABI (vtable slots, superclass, instance size)
from a macOS x86_64 kernel collection.

The family ships without private headers.  A native accelerator that subclasses
IOGraphicsAccelerator2 / IOAccelDisplayPipe has to match the family vtable slot for
slot, so the layout is read from the machine's own KC instead of guessed:

  * vtable   : symbol __ZTV<class>, 8-byte pointers at +16 (Itanium: offset-to-top, rtti)
  * superclass / instance size : the static initialiser calls
        OSMetaClass::OSMetaClass(const char *name, const OSMetaClass *super, unsigned size)
    with rsi=name, rdx=super (lea rip), ecx=size (mov imm32); the call is a direct rel32.

Usage: ioaccel_layout.py [--kc PATH] [--family BUNDLE_ID] [--class NAME ...] [--out FILE]
"""
import argparse, json, struct, subprocess, sys, re, bisect

LC_SEGMENT_64, LC_SYMTAB, LC_FILESET_ENTRY = 0x19, 0x2, 0x80000035
DEFAULT_KC = "/System/Library/KernelCollections/SystemKernelExtensions.kc"
DEFAULT_FAMILY = "com.apple.iokit.IOAcceleratorFamily2"
DEFAULT_CLASSES = [
    "IOAccelerator", "IOGraphicsAccelerator2", "IOAccelDisplayMachine", "IOAccelDisplayPipe",
    "IOAccelEventMachine2", "IOAccelEventMachineFast2", "IOAccelTask", "IOAccelSysMemory",
    "IOAccelVidMemory", "IOAccelMemoryMap", "IOAccelResource2", "IOAccel2DContext2",
    "IOAccelSharedUserClient2", "IOAccelCommandQueue", "IOAccelMemory", "IOAccelShared2",
    "IOAccelSurface", "IOAccelContext2", "IOAccelSubmitter2",
    # Apple's own minimal accelerator (VM guest GPU) implements every pure slot: it names them
    "AppleParavirtAccelerator", "AppleParavirtDisplayMachine", "AppleParavirtDisplayPipe",
    "AppleParavirtEventMachine", "AppleParavirtTask", "AppleParavirtKernelTask",
    "AppleParavirtSysMemory", "AppleParavirtVidMemory", "AppleParavirtMemoryMap",
    "AppleParavirtResource", "AppleParavirt2DContext", "AppleParavirtSharedUserClient",
    "AppleParavirtCommandQueue", "AppleParavirtFramebuffer",
]


class KC:
    def __init__(self, path):
        self.f = open(path, "rb")
        import mmap
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        magic, cpu, _, _, ncmds, sizeofcmds = struct.unpack_from("<IiiIII", self.m, 0)
        if magic != 0xFEEDFACF:
            raise SystemExit("not a thin x86_64/arm64 Mach-O: %#x" % magic)
        self.cpu = cpu
        self.segs, self.entries, self.symtab = [], {}, None
        off = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", self.m, off)
            if cmd == LC_SEGMENT_64:
                name = self.m[off + 8:off + 24].split(b"\0")[0].decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", self.m, off + 24)
                nsects = struct.unpack_from("<I", self.m, off + 64)[0]
                self.segs.append((name, vmaddr, vmsize, fileoff, filesize))
            elif cmd == LC_SYMTAB:
                self.symtab = struct.unpack_from("<IIII", self.m, off + 8)
            elif cmd == LC_FILESET_ENTRY:
                vmaddr, fileoff, strx = struct.unpack_from("<QQI", self.m, off + 8)
                eid = self.m[off + strx:off + size].split(b"\0")[0].decode()
                self.entries[eid] = (vmaddr, fileoff)
            off += size

    def v2f(self, va):
        for _, vm, sz, fo, fs in self.segs:
            if fs and vm <= va < vm + min(sz, fs):
                return fo + (va - vm)
        return None

    def read(self, va, n):
        fo = self.v2f(va)
        return None if fo is None else self.m[fo:fo + n]

    def u64(self, va):
        b = self.read(va, 8)
        return None if b is None else struct.unpack("<Q", b)[0]

    def kext_segments(self, bundle):
        """segments (name, vmaddr, vmsize, fileoff, filesize) of a fileset entry's own header."""
        vmaddr, fileoff = self.entries[bundle]
        magic, _, _, _, ncmds, _ = struct.unpack_from("<IiiIII", self.m, fileoff)
        out, off = [], fileoff + 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", self.m, off)
            if cmd == LC_SEGMENT_64:
                name = self.m[off + 8:off + 24].split(b"\0")[0].decode()
                out.append((name,) + struct.unpack_from("<QQQQ", self.m, off + 24))
            off += size
        return out

    def entry_symtabs(self):
        """LC_SYMTAB of every fileset entry (a KC carries none at the top level)."""
        seen = set()
        for vmaddr, fileoff in self.entries.values():
            _, _, _, _, ncmds, _ = struct.unpack_from("<IiiIII", self.m, fileoff)
            off = fileoff + 32
            for _ in range(ncmds):
                cmd, size = struct.unpack_from("<II", self.m, off)
                if cmd == LC_SYMTAB:
                    st = struct.unpack_from("<IIII", self.m, off + 8)
                    if st not in seen:
                        seen.add(st)
                        yield st
                off += size

    def symbols(self):
        by_name, by_addr = {}, {}
        tabs = list(self.entry_symtabs()) or ([self.symtab] if self.symtab else [])
        for symoff, nsyms, stroff, strsize in tabs:
            for i in range(nsyms):
                strx, ntype, nsect, ndesc, nvalue = struct.unpack_from("<IBBHQ", self.m, symoff + 16 * i)
                if ntype & 0xE0 or (ntype & 0xE) != 0xE:   # stab or not defined-in-section
                    continue
                end = self.m.find(b"\0", stroff + strx)
                nm = self.m[stroff + strx:end].decode("latin1")
                by_name.setdefault(nm, nvalue)
                by_addr.setdefault(nvalue, nm)
        return by_name, by_addr


def decode_ptr(v, bases):
    if not v:
        return None
    target, level = v & 0x3FFFFFFF, (v >> 30) & 3
    return bases.get(level, 0) + target


def demangle(names):
    if not names:
        return {}
    p = subprocess.run(["c++filt", "-_"], input="\n".join(names), capture_output=True, text=True)
    return dict(zip(names, p.stdout.split("\n")))


def metaclass_calls(kc, text_lo, text_hi, by_addr, bases, wanted):
    """class name -> {size, super_sym}.

    Every OSMetaClass subclass registers itself with
        lea rsi,[rip+"Name"] ; mov rdx,[rip+GOT(super gMetaClass)] | lea rdx,[rip+super] ;
        mov ecx,SIZE ; call OSMetaClass::OSMetaClass(char const*, OSMetaClass const*, unsigned)
    The call target is a kernel stub, so the sequence is matched by the name string instead."""
    fo0 = kc.v2f(text_lo)
    blob = kc.m[fo0:fo0 + (text_hi - text_lo)]
    res = {}
    for name in wanted:
        needle = name.encode() + b"\0"
        k = 0
        sva = None
        while True:
            k = blob.find(needle, k)
            if k < 0:
                break
            if k == 0 or blob[k - 1] == 0:       # whole C string, not a suffix of a longer one
                sva = text_lo + k
                break
            k += 1
        if sva is None:
            continue
        for m in re.finditer(rb"\x48\x8d\x35", blob):
            i = m.start()
            d = struct.unpack_from("<i", blob, i + 3)[0]
            if text_lo + i + 7 + d != sva:
                continue
            win = blob[i + 7:i + 7 + 48]
            super_sym, size = None, None
            j = 0
            while j + 7 <= len(win):
                if win[j:j + 3] == b"\x48\x8b\x15":      # mov rdx,[rip+disp]  (super via GOT)
                    d2 = struct.unpack_from("<i", win, j + 3)[0]
                    slot = text_lo + i + 7 + j + 7 + d2
                    raw = kc.u64(slot)
                    p = decode_ptr(raw, bases) if raw else None
                    super_sym = by_addr.get(p, "%#x" % p) if p else None
                    j += 7
                    continue
                if win[j:j + 3] == b"\x48\x8d\x15":      # lea rdx,[rip+disp]  (super in this kext)
                    d2 = struct.unpack_from("<i", win, j + 3)[0]
                    t = text_lo + i + 7 + j + 7 + d2
                    super_sym = by_addr.get(t, "%#x" % t)
                    j += 7
                    continue
                if win[j] == 0xB9:
                    size = struct.unpack_from("<I", win, j + 1)[0]
                    break
                j += 1
            if size is not None:
                res[name] = dict(size=size, super_sym=super_sym)
                break
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kc", default=DEFAULT_KC)
    ap.add_argument("--family", default=DEFAULT_FAMILY)
    ap.add_argument("--symbols-from", action="append",
                    default=["/System/Library/KernelCollections/BootKernelExtensions.kc"])
    ap.add_argument("--class", dest="classes", action="append")
    ap.add_argument("--out", default="-")
    a = ap.parse_args()
    classes = a.classes or DEFAULT_CLASSES

    kc = KC(a.kc)
    by_name, by_addr = kc.symbols()
    # OSMetaClass / IOService live in the boot KC (com.apple.kernel); the SKC calls into it by fixed address
    for extra in a.symbols_from:
        n2, a2 = KC(extra).symbols()
        for k, v in n2.items(): by_name.setdefault(k, v)
        for k, v in a2.items(): by_addr.setdefault(k, v)
    segs = kc.kext_segments(a.family)
    text = ([s for s in segs if s[0] == "__TEXT_EXEC"] or [s for s in segs if s[0] == "__TEXT"])[0]   # __TEXT_EXEC when the kext is split, else __TEXT
    text_lo, text_hi = text[1], text[1] + text[2]
    bases = {1: 0}
    for extra in a.symbols_from:
        bases[0] = KC(extra).segs[0][1] - 0x100000   # empirical: level-0 targets are 0x100000 below the BKC header (checked against IOService::gMetaClass)
    mc = metaclass_calls(kc, text_lo, text_hi, by_addr, bases, classes)
    meta_by_name = {k: (None, v) for k, v in mc.items()}

    sorted_addrs = sorted(by_addr)
    # chained-fixup pointers: target in bits 0-29, cache level in bits 30-31 (0 = boot KC / kernel, 1 = this KC)
    result = {"kc": a.kc, "family": a.family, "classes": {}}
    for c in classes:
        vt = by_name.get("__ZTV%d%s" % (len(c), c))
        if vt is None:
            result["classes"][c] = {"error": "no vtable symbol"}
            continue
        nxt = sorted_addrs[bisect.bisect_right(sorted_addrs, vt)]
        nslots = (nxt - vt - 16) // 8
        slots = []
        for i in range(nslots):
            raw = kc.u64(vt + 16 + 8 * i)
            p = decode_ptr(raw, bases)
            slots.append(None if p is None else by_addr.get(p, "%#x" % p))
        info = meta_by_name.get(c, (None, {}))[1]
        result["classes"][c] = dict(
            vtable=vt, nslots=nslots, slots=slots,
            size=info.get("size"), super_sym=info.get("super_sym"), meta=info.get("name"))
    allnames = {s for v in result["classes"].values() for s in v.get("slots", []) if s and s.startswith("_")}
    dm = demangle(sorted(allnames))
    for v in result["classes"].values():
        v["demangled"] = [dm.get(s, s) if s else None for s in v.get("slots", [])]
    out = json.dumps(result, indent=1)
    if a.out == "-":
        print(out)
    else:
        open(a.out, "w").write(out)
        for c, v in result["classes"].items():
            print("%-28s slots=%-4s size=%-6s super=%s" % (c, v.get("nslots"), v.get("size"), v.get("super_sym")))


if __name__ == "__main__":
    main()
