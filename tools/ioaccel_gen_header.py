#!/usr/bin/env python3
"""Generate kexts/StrixAccel/IOAccelFamily2_decl.h from the machine's own kernel collection.

The IOAcceleratorFamily2 headers are private.  A subclass has to reproduce the family's vtable
slot for slot, so this script emits, for every class we build on, a C++ declaration whose
virtual-function order is exactly the order of the family's vtable (read from the KC, see
ioaccel_layout.py) and whose mangled names are the family's real exported symbols:

  * a slot implemented by the family with an exported symbol   -> a normal virtual declaration
    (the leaf's vtable then binds to the family's own function at link time);
  * a pure slot                                               -> `= 0` (the leaf must override it);
  * a slot implemented by the family but NOT exported         -> `_vslot<N>()` declared pure; the
    leaf defines it as a naked tail-jump into the family's vtable slot (STRIXACCEL_FWD_<Class>);
  * data                                                      -> `char _pad[]` up to the family's
    instance size, so the leaf's own members start behind the family's.

Return types are not part of the Itanium mangled name, so they are only pinned for slots that the
leaf overrides or calls (RET table below, evidence: AppleParavirtGPU disassembly); every other
slot returns `uintptr_t` (a 64-bit rax value) in its declaration.

Usage: ioaccel_gen_header.py [--kc KC] [--layout JSON] [--out FILE]
"""
import argparse, json, os, re, struct, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ioaccel_layout as L

# class -> (parent, header-visible parent class name used in the C++ declaration)
CHAIN = [
    # (class, parent, own_vtable_override_names_to_skip)
    ("IOGraphicsAccelerator2", "IOAccelerator"),
    ("IOAccelDisplayMachine", "IOService"),
    ("IOAccelDisplayPipe", "IOService"),
    ("IOAccelEventMachine2", "OSObject"),
    ("IOAccelEventMachineFast2", "IOAccelEventMachine2"),
    ("IOAccelTask", "OSObject"),
    ("IOAccelMemory", "OSObject"),
    ("IOAccelSysMemory", "IOAccelMemory"),
    ("IOAccelVidMemory", "IOAccelMemory"),
    ("IOAccelResource2", "OSObject"),
    ("IOAccelMemoryMap", "OSObject"),
]
# parent real slot counts: IOService / OSObject come from the SDK headers (the leaf vtable is gated at run time)
PARENT_SLOTS = {"IOAccelerator": 266, "IOService": 266, "OSObject": 35}
SUPERS_IN_SDK = {"IOAccelerator", "IOService", "OSObject"}

# return types pinned by disassembly / the AppleParavirtGPU recipe.  Key "Class::method(args)".
RET = {
    "IOGraphicsAccelerator2::acceleratorDidLock(char const*, int)": "void",
    "IOGraphicsAccelerator2::acceleratorWillUnlock(char const*, int)": "void",
    "IOGraphicsAccelerator2::createDisplayPipe(IOFramebuffer*, unsigned int)": "IOAccelDisplayPipe*",
    "IOGraphicsAccelerator2::newDisplayPipe()": "IOAccelDisplayPipe*",
    "IOGraphicsAccelerator2::newSharedUserClient()": "uintptr_t",
    "IOGraphicsAccelerator2::newCommandQueue()": "uintptr_t",
    "IOGraphicsAccelerator2::newContext(unsigned int)": "uintptr_t",
    "IOGraphicsAccelerator2::newDevice()": "uintptr_t",
    "IOGraphicsAccelerator2::newShared()": "uintptr_t",
    "IOGraphicsAccelerator2::newDrawable()": "uintptr_t",
    "IOGraphicsAccelerator2::createEventMachine()": "uintptr_t",
    "IOGraphicsAccelerator2::start(IOService*)": "bool",
    "IOGraphicsAccelerator2::configureReport(IOReportChannelList*, unsigned int, void*, void*)": "IOReturn",
    "IOGraphicsAccelerator2::updateReport(IOReportChannelList*, unsigned int, void*, void*)": "IOReturn",
    "IOGraphicsAccelerator2::stop(IOService*)": "void",
    "IOGraphicsAccelerator2::free()": "void",
    "IOGraphicsAccelerator2::setProperties(OSObject*)": "IOReturn",
    "IOGraphicsAccelerator2::requestTerminate(IOService*, unsigned int)": "bool",
    "IOGraphicsAccelerator2::didTerminate(IOService*, unsigned int, bool*)": "bool",
    "IOGraphicsAccelerator2::terminate(unsigned int)": "bool",
    "IOGraphicsAccelerator2::finalize(unsigned int)": "bool",
    "IOGraphicsAccelerator2::requestProbe(unsigned int)": "IOReturn",
    "IOGraphicsAccelerator2::message(unsigned int, IOService*, void*)": "IOReturn",
    "IOGraphicsAccelerator2::newUserClient(task*, void*, unsigned int, IOUserClient**)": "IOReturn",
    "IOGraphicsAccelerator2::getWorkLoop() const": "IOWorkLoop*",
    "IOAccelDisplayMachine::free()": "void",
    "IOAccelDisplayMachine::init(IOGraphicsAccelerator2*)": "bool",
    "IOAccelDisplayMachine::start(IOPCIDevice*)": "uintptr_t",
    "IOAccelDisplayMachine::stop()": "void",
    "IOAccelDisplayPipe::free()": "void",
    "IOAccelDisplayPipe::init(IOGraphicsAccelerator2*, IOAccelDisplayMachine*, IOFramebuffer*, unsigned int)": "bool",
    "IOAccelDisplayPipe::initFramebufferResource(unsigned int, IOAccelResource2*)": "uintptr_t",
    "IOAccelDisplayPipe::validateTransaction(IOAccelDisplayPipeTransaction2*)": "uintptr_t",
    "IOAccelDisplayPipe::performTransaction(IOAccelDisplayPipeTransaction2*)": "uintptr_t",
    "IOAccelDisplayPipe::isTransactionComplete(IOAccelDisplayPipeTransaction2*)": "bool",
    "IOAccelDisplayPipe::submitTransaction(IOAccelDisplayPipeTransaction2*)": "IOReturn",
    "IOAccelDisplayPipe::displayModeWillChange()": "uintptr_t",
    "IOAccelDisplayPipe::displayModeDidChange()": "uintptr_t",
    "IOAccelDisplayPipe::beginTransaction(IOAccelEvent*)": "void",
    "IOAccelDisplayPipe::signalTransactionComplete(IOAccelEvent*)": "void",
    "IOAccelEventMachine2::free()": "void",
    "IOAccelEventMachine2::init(IOGraphicsAccelerator2*, unsigned int, int)": "bool",
    "IOAccelEventMachineFast2::init(IOGraphicsAccelerator2*, unsigned int, int)": "bool",
    "IOAccelEventMachineFast2::free()": "void",
    "IOAccelEventMachine2::setStampBaseAddress(unsigned int volatile*)": "void",
    "IOAccelEventMachine2::enableStampInterrupt(int)": "void",
    "IOAccelEventMachine2::disableStampInterrupt(int)": "void",
    "IOAccelTask::free()": "void",
    "IOAccelTask::release() const": "void",
    "IOAccelTask::init(IOGraphicsAccelerator2*, unsigned int, IORangeAllocator**)": "bool",
    "IOAccelMemory::free()": "void",
    "IOAccelMemory::init(IOGraphicsAccelerator2*)": "bool",
    "IOAccelMemory::release() const": "void",
    "IOAccelMemory::retain() const": "void",
    "IOAccelMemory::getRetainCount() const": "int",
    "IOAccelVidMemory::free()": "void",
    "IOAccelVidMemory::getPhysicalSegment(unsigned long long, unsigned long long*)": "uint64_t",
    "IOAccelSysMemory::getPhysicalSegment(unsigned long long, unsigned long long*)": "uint64_t",
    "IOAccelVidMemory::init(IOGraphicsAccelerator2*, IOAccelShared2*, IOAccelResource2*, unsigned long long, void*)": "bool",
    "IOAccelResource2::free()": "void",
    "IOAccelResource2::retain() const": "void",
    "IOAccelResource2::release() const": "void",
    "IOAccelResource2::getRetainCount() const": "int",
    "IOAccelResource2::init(IOGraphicsAccelerator2*, IOAccelShared2*, unsigned int)": "bool",
    "IOAccelMemoryMap::free()": "void",
    "IOAccelMemoryMap::release() const": "void",
    "IOAccelMemoryMap::init(IOGraphicsAccelerator2*, IOAccelTask*, IOAccelMemory*, unsigned int)": "bool",
    "IOAccelSysMemory::free()": "void",
    "IOAccelSysMemory::init(IOGraphicsAccelerator2*)": "bool",
}
# slots that are pure in the family: name, return type and arguments come from Apple's AppleParavirt* subclass
PURE_NAME_FROM = {
    "IOAccelMemory": "IOAccelSysMemory",
    "IOGraphicsAccelerator2": "AppleParavirtAccelerator",
    "IOAccelDisplayMachine": "AppleParavirtDisplayMachine",
    "IOAccelEventMachineFast2": "AppleParavirtEventMachine",
    "IOAccelEventMachine2": "AppleParavirtEventMachine",
    "IOAccelVidMemory": "AppleParavirtVidMemory",
    "IOAccelResource2": "AppleParavirtResource",
    "IOAccelMemoryMap": "AppleParavirtMemoryMap",
}
PURE_RET = {
    "getStampMemory(unsigned int*)": "IOMemoryDescriptor*",
    "newEventMachine()": "IOAccelEventMachine2*",
    "createUserGPUTask()": "IOAccelTask*",
    "createKernelGPUTask()": "IOAccelTask*",
    "populateAccelConfig(IOAccelConfig*)": "void",
    "configureDevice(IOPCIDevice*)": "bool",
    "teardownDevice(IOPCIDevice*)": "void",
    "newDisplayMachine()": "IOAccelDisplayMachine*",
    "newGLContext()": "uintptr_t",
    "newCLContext()": "uintptr_t",
    "newSurface()": "uintptr_t",
    "new2DContext()": "uintptr_t",
    "newVideoContext()": "uintptr_t",
    "newSysMemory()": "IOAccelSysMemory*",
    "newVidMemory()": "uintptr_t",
    "newResource()": "uintptr_t",
    "newMemoryMap()": "uintptr_t",
    "rebuildPagingBuffer()": "uintptr_t",
    "getLevelOffset(unsigned char, unsigned char, int*)": "uintptr_t",
    "getBackingLevelOffset(unsigned char, unsigned char, int*)": "uintptr_t",
    "calculateIOSurfaceDeviceCacheVRAMBytes(unsigned long long*, unsigned long long*)": "uintptr_t",
    "addToAperture()": "uintptr_t",
    "removeFromAperture()": "uintptr_t",
    "getApertureMemoryDescriptor(unsigned long long*)": "uintptr_t",
    "commitIntoGPUPageTable()": "uintptr_t",
    "releaseFromGPUPageTable()": "uintptr_t",
    "updateGPUPageTable()": "uintptr_t",
    "getPhysicalSegment(unsigned long long, unsigned long long*)": "uint64_t",
    "allocPhysical()": "uintptr_t",
    "deallocPhysical()": "uintptr_t",
    "displayModeWillChange()": "bool",
    "displayModeDidChange()": "bool",
    "writeStamp(int, vendevtCommandRec*, unsigned int)": "void",
    "prepareBarrier(vendevtBarrierRec*)": "void",
    "completeBarrier(vendevtBarrierRec*)": "bool",
    "writeBarrierElement(vendevtBarrierRec*, int, unsigned int)": "void",
}
# types that need no forward declaration
KNOWN = {"int", "unsigned int", "unsigned long", "unsigned long long", "bool", "char", "void", "long", "unsigned char",
         "unsigned short", "short", "long long", "float", "double", "task", "IOService", "IOUserClient", "OSObject",
         "IOPCIDevice", "IOFramebuffer", "IOMemoryDescriptor", "IORangeAllocator", "IOWorkLoop", "IOReportChannelList",
         "IOOptionBits", "IOReturn", "OSSerialize", "OSDictionary"}


def exported_syms(kc, bundle):
    vm, fo = kc.entries[bundle]
    _, _, _, _, ncmds, _ = struct.unpack_from("<IiiIII", kc.m, fo)
    off = fo + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", kc.m, off)
        if cmd == L.LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", kc.m, off + 8)
            break
        off += size
    ext = set()
    for i in range(nsyms):
        strx, ntype, nsect, ndesc, nvalue = struct.unpack_from("<IBBHQ", kc.m, symoff + 16 * i)
        if ntype & 0xE0 or (ntype & 0xE) != 0xE:
            continue
        if (ntype & 1) and not (ntype & 0x10):
            end = kc.m.find(b"\0", stroff + strx)
            ext.add(kc.m[stroff + strx:end].decode("latin1"))
    return ext


def split_sig(dm):
    """'Class::name(a, b) const' -> (cls, name, args[list], const)"""
    m = re.match(r"^(\w+)::(\w+)\((.*)\)( const)?$", dm)
    if not m:
        return None
    cls, name, args, const = m.groups()
    args = [a.strip() for a in args.split(",")] if args.strip() else []
    # `unsigned int volatile*` -> `volatile unsigned int*`
    out = []
    for a in args:
        mm = re.match(r"^(.*?) volatile\*$", a)
        out.append("volatile %s*" % mm.group(1) if mm else a)
    return cls, name, out, bool(const)


def fix_type(t):
    t = t.replace("char const*", "const char*").replace("IOAccelEvent const*", "const IOAccelEvent*")
    t = re.sub(r"(\w+) const\*", r"const \1*", t)
    return t


def base_ident(t):
    t = re.sub(r"\b(const|volatile|unsigned|long|int|char|short|bool|void|signed)\b", " ", t)
    t = t.replace("*", " ").replace("&", " ")
    return [w for w in t.split() if w]


FAMILIES = [   # inheritance chains (root first); a slot that is non-exported anywhere in a chain is `_vslotN` everywhere in it
    ["IOGraphicsAccelerator2"],
    ["IOAccelDisplayMachine"],
    ["IOAccelDisplayPipe"],
    ["IOAccelEventMachine2", "IOAccelEventMachineFast2"],
    ["IOAccelTask"],
    ["IOAccelMemory", "IOAccelSysMemory", "IOAccelVidMemory"],
    ["IOAccelResource2"],
    ["IOAccelMemoryMap"],
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kc", default=L.DEFAULT_KC)
    ap.add_argument("--layout", default="out/890m-trace/ioaccel-layout/layout-24H32.json")
    ap.add_argument("--out", default="kexts/StrixAccel/IOAccelFamily2_decl.h")
    a = ap.parse_args()
    d = json.load(open(a.layout))["classes"]
    kc = L.KC(a.kc)
    ext = exported_syms(kc, L.DEFAULT_FAMILY)
    parent_of = dict(CHAIN)

    def nslots(c):
        return PARENT_SLOTS[c] if c in PARENT_SLOTS else d[c]["nslots"] - 1

    # pass 1: slot indices that must be forwarded, per chain
    vslots = {}
    for chain in FAMILIES:
        z = set()
        for c in chain:
            P = nslots(parent_of[chain[0]])
            for i in range(P, nslots(c)):
                sym = d[c]["slots"][i]
                if sym and sym != "___cxa_pure_virtual" and sym.startswith("_") and sym not in ext and not sym.startswith("__ZN9IOService") \
                        and not sym.startswith("__ZN8OSObject") and not sym.startswith("__ZNK8OSObject"):
                    z.add(i)
        for c in chain:
            vslots[c] = z

    forward = set()
    out = []
    out.append("// GENERATED by tools/ioaccel_gen_header.py from %s -- do not edit.\n" % os.path.basename(a.kc))
    out.append("// Source of truth: the machine's own IOAcceleratorFamily2 vtables (macOS 24H32).  Each class declares its\n"
               "// virtual functions in the family's slot order, with the family's real exported mangled names, and pads its\n"
               "// data to the family's instance size.  A leaf class must override every pure slot and define every\n"
               "// `_vslotN` through STRIXACCEL_FWD_<Class>(Leaf).\n")
    out.append("#pragma once\n#include <IOKit/IOService.h>\n#include <IOKit/IOMemoryDescriptor.h>\n#include <IOKit/IORangeAllocator.h>\n"
               "#include <IOKit/IOWorkLoop.h>\n#include <IOKit/IOUserClient.h>\n#include <IOKit/graphics/IOAccelerator.h>\n"
               "#include <IOKit/graphics/IOFramebuffer.h>\n#include <IOKit/pci/IOPCIDevice.h>\n\n")
    classes_out = []
    summary = []
    for cls, parent in CHAIN:
        v = d[cls]
        n = nslots(cls)
        P = nslots(parent)
        pnames = d[PURE_NAME_FROM[cls]]["demangled"] if cls in PURE_NAME_FROM else None
        decls, fwd_idx, ovfwd = [], [], []
        for i in range(n):
            sym, dm = v["slots"][i], v["demangled"][i]
            forwarded = i in vslots[cls] and i >= nslots(parent_of[CHAIN_ROOT[cls]])
            if i < P:
                if not dm or not dm.startswith(cls + "::") or "~" in dm or "getMetaClass" in dm:
                    continue
                if i in vslots[cls] and i >= nslots(parent_of[CHAIN_ROOT[cls]]):
                    continue                    # declared as _vslotN in the chain root
                s = split_sig(dm)
                if s is None:
                    decls.append("    // slot %d: %s not declared (unparsed)" % (i, dm))
                    continue
                r = RET.get(dm, "uintptr_t")
                args = ", ".join(fix_type(x) for x in s[2])
                if sym not in ext:
                    # the family's implementation is not exported: the leaf must define the slot itself (forwarder)
                    decls.append("    virtual %s %s(%s)%s override = 0;   // %d: family symbol not exported" % (r, s[1], args, " const" if s[3] else "", i))
                    ovfwd.append((i, r, s[1], args, s[3]))
                    continue
                for x in s[2]:
                    for w in base_ident(x):
                        if w not in KNOWN and re.match(r"^[A-Za-z_]\w*$", w):
                            forward.add(w)
                decls.append("    virtual %s %s(%s)%s override;   // %d" % (r, s[1], args, " const" if s[3] else "", i))
                continue
            pure = sym == "___cxa_pure_virtual" or not sym
            if forwarded:
                if cls == CHAIN_ROOT[cls]:
                    decls.append("    virtual uintptr_t _vslot%d() = 0;   // %d: %s" % (i, i, dm))
                fwd_idx.append(i)
                continue
            name_dm = pnames[i] if (pure and pnames) else dm
            s = split_sig(name_dm) if name_dm and name_dm != "___cxa_pure_virtual" else None
            if s is None:
                decls.append("    virtual uintptr_t _vslot%d() = 0;   // %d: unknown (%s)" % (i, i, name_dm))
                fwd_idx.append(i)
                continue
            _, nm, args_l, const = s
            for x in args_l:
                for w in base_ident(x):
                    if w not in KNOWN and re.match(r"^[A-Za-z_]\w*$", w):
                        forward.add(w)
            args = ", ".join(fix_type(x) for x in args_l)
            sig = "%s(%s)" % (nm, ", ".join(args_l))
            if pure:
                r = PURE_RET.get(sig, "uintptr_t")
                decls.append("    virtual %s %s(%s)%s = 0;   // %d" % (r, nm, args, " const" if const else "", i))
            else:
                r = RET.get(name_dm, "uintptr_t")
                decls.append("    virtual %s %s(%s)%s;   // %d" % (r, nm, args, " const" if const else "", i))
        classes_out.append((cls, parent, decls, v.get("size"), n, sorted(vslots[cls]), ovfwd))
        summary.append((cls, parent, n, v.get("size"), len(decls), sorted(vslots[cls])))
    for w in sorted(forward):
        if w in parent_of:
            out.append("class %s;\n" % w)
        else:
            out.append("struct %s;\n" % w)
    for w in sorted(parent_of):   # return types in RET/PURE_RET are not scanned for forward declarations
        out.append("class %s;\n" % w)
    out.append("\n")
    for cls, parent, decls, size, n, vs, ovfwd in classes_out:
        out.append("// ---- %s : %s   %d slots, size %s\n" % (cls, parent, n, size))
        out.append("#define STRIXACCEL_%s_SIZE %su\n#define STRIXACCEL_%s_SLOTS %du\n" % (cls, size, cls, n))
        out.append("class %s : public %s {\n    OSDeclareAbstractStructors(%s)\n" % (cls, parent, cls))
        out.append("protected:\n    char _famdata[STRIXACCEL_%s_SIZE - sizeof(%s)];\npublic:\n" % (cls, parent))
        out.extend(x + "\n" for x in decls)
        out.append("};\n")
        # forwarders into THIS class's vtable for every _vslot visible at this level
        if ovfwd or vs:
            out.append("#define STRIXACCEL_LEAFDECL_%s \\\n" % cls)
            for (i, r, nm, args, const) in ovfwd:
                out.append("    virtual %s %s(%s)%s override; \\\n" % (r, nm, args, " const" if const else ""))
            for i in vs:
                out.append("    virtual uintptr_t _vslot%d() override; \\\n" % i)
            out.append("\n")
        if vs or ovfwd:
            out.append("#define STRIXACCEL_FWD_%s(LEAF) \\\n" % cls)
            for (i, r, nm, args, const) in ovfwd:
                out.append("    __attribute__((naked)) %s LEAF::%s(%s)%s { __asm__(\"movq __ZTV%d%s@GOTPCREL(%%rip), %%rax\\n\\tmovq %d(%%rax), %%rax\\n\\tjmpq *%%rax\"); } \\\n" % (r, nm, args, " const" if const else "", len(cls), cls, 16 + 8 * i))
            for i in vs:
                out.append("    __attribute__((naked)) uintptr_t LEAF::_vslot%d() { __asm__(\"movq __ZTV%d%s@GOTPCREL(%%rip), %%rax\\n\\tmovq %d(%%rax), %%rax\\n\\tjmpq *%%rax\"); } \\\n" % (i, len(cls), cls, 16 + 8 * i))
            out.append("\n")
        out.append("\n")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out, "w").write("".join(out))
    for row in summary:
        print("%-26s parent=%-22s slots=%-4d size=%-5s decls=%-3d vslots=%s" % row)


CHAIN_ROOT = {"IOGraphicsAccelerator2": "IOGraphicsAccelerator2", "IOAccelDisplayMachine": "IOAccelDisplayMachine",
              "IOAccelDisplayPipe": "IOAccelDisplayPipe", "IOAccelEventMachine2": "IOAccelEventMachine2",
              "IOAccelEventMachineFast2": "IOAccelEventMachine2", "IOAccelTask": "IOAccelTask",
              "IOAccelMemory": "IOAccelMemory", "IOAccelSysMemory": "IOAccelMemory",
              "IOAccelVidMemory": "IOAccelMemory", "IOAccelResource2": "IOAccelResource2", "IOAccelMemoryMap": "IOAccelMemoryMap"}


if __name__ == "__main__":
    main()
