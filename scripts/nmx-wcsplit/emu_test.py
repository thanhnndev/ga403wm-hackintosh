#!/usr/bin/env python3
# Runs the patched NMXGPU's Step90 code (map_user / unmap_user / map_pages / unmap) under unicorn with fake IOKit
# calls, and checks the mappings it makes, the release order, IOFree sizes, leaks and stack alignment.
#   emu_test.py NMXGPU.patched        (needs the unicorn module)
import struct
import sys

from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_RAX, UC_X86_REG_RBX, UC_X86_REG_RCX, UC_X86_REG_RDI, UC_X86_REG_RDX,
                               UC_X86_REG_RIP, UC_X86_REG_RSI, UC_X86_REG_RSP, UC_X86_REG_R8, UC_X86_REG_R9,
                               UC_X86_REG_RBP, UC_X86_REG_R12, UC_X86_REG_R13, UC_X86_REG_R14, UC_X86_REG_R15)

MAP_USER, UNMAP_USER, MAP_PAGES, UNMAP = 0x6e24f0, 0x6e2710, 0x6e7d50, 0x6e7ea0
STUB = {0x6e2550: 'IOMalloc', 0x6e25d8: 'withAddressRanges', 0x6e25e6: 'IOFree', 0x6e2644: 'current_task',
        0x6e265f: 'createMappingInTask', 0x6e26ab: 'task_reference', 0x6e2727: 'get_task_map',
        0x6e2737: 'vm_deallocate', 0x6e2740: 'task_deallocate', 0x6e7c40: 'kva_to_phys'}
VT_RELEASE, VT_GETADDR = 0x40000000, 0x40000008
HEAP, OBJ, STACK, VTAB, KTASK_VAR = 0x50000000, 0x60000000, 0x70000000, 0x41000000, 0x42000000
UTASK, KTASK, UMAP, KMAP = 0x7a5c0000, 0x7c0000, 0xaa000, 0xbb000
RET_MAGIC = 0x3ffff000
TEXT_PHYS = 0x1234000
OVERWRITE, ANYWHERE, RO = 0x20000000, 1, 0x1000


class World:
    def __init__(self, img):
        self.u = Uc(UC_ARCH_X86, UC_MODE_64)
        size = (len(img) + 0x200000) & ~0xfff
        self.u.mem_map(0, size)
        self.u.mem_write(0, img)
        for base in (HEAP, OBJ, STACK, VTAB, KTASK_VAR, RET_MAGIC & ~0xfff, 0x40000000):
            self.u.mem_map(base, 0x1000000 if base in (HEAP, OBJ, STACK) else 0x1000)
        vt = bytearray(0x200)
        struct.pack_into('<Q', vt, 0x28, VT_RELEASE)
        struct.pack_into('<Q', vt, 0x118, VT_GETADDR)
        self.u.mem_write(VTAB, bytes(vt))
        self.u.mem_write(KTASK_VAR, struct.pack('<Q', KTASK))
        self.u.mem_write(0x89a0e8, struct.pack('<Q', KTASK_VAR))      # the GOT slot of kernel_task
        self.heap = HEAP
        self.allocs = {}          # ptr -> size (live)
        self.objs = {}            # ptr -> dict
        self.next_obj = OBJ
        self.va = {UTASK: 0x100000000, KTASK: 0xffffff8000000000 & 0xffffffffffffffff}
        self.log = []
        self.fail_createmap_at = None
        self.ncreatemap = 0
        self.taskrefs = 0
        self.u.hook_add(UC_HOOK_CODE, self.hook)

    def r(self, reg):
        return self.u.reg_read(reg)

    def new_obj(self, kind, **kw):
        p = self.next_obj
        self.next_obj += 0x100
        self.u.mem_write(p, struct.pack('<Q', VTAB))
        self.objs[p] = dict(kind=kind, live=True, **kw)
        return p

    def ret(self, val):
        rsp = self.r(UC_X86_REG_RSP)
        ra = struct.unpack('<Q', self.u.mem_read(rsp, 8))[0]
        self.u.reg_write(UC_X86_REG_RSP, rsp + 8)
        self.u.reg_write(UC_X86_REG_RAX, val & 0xffffffffffffffff)
        self.u.reg_write(UC_X86_REG_RIP, ra)

    def hook(self, uc, addr, size, _):
        if addr == RET_MAGIC:
            uc.emu_stop()
            return
        name = STUB.get(addr)
        if name is None and addr not in (VT_RELEASE, VT_GETADDR):
            return
        rsp = self.r(UC_X86_REG_RSP)
        # at a stub's call instruction rsp must be 0 mod 16 (the callee then sees 8 mod 16); an internal function or a
        # virtual call is entered with rsp = 8 mod 16
        want = 0 if name in STUB.values() and addr != 0x6e7c40 else 8
        if rsp % 16 != want:
            raise AssertionError(f'stack misaligned at {name or hex(addr)}: rsp={rsp:#x}')
        a = [self.r(x) for x in (UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX, UC_X86_REG_RCX, UC_X86_REG_R8,
                                 UC_X86_REG_R9)]
        if name == 'IOMalloc':
            p = self.heap
            self.heap += (a[0] + 15) & ~15
            self.allocs[p] = a[0]
            self.u.mem_write(p, b'\xcc' * a[0])
            return self.ret(p)
        if name == 'IOFree':
            assert self.allocs.get(a[0]) == a[1], f'IOFree({a[0]:#x}, {a[1]:#x}) but allocated {self.allocs.get(a[0])}'
            del self.allocs[a[0]]
            return self.ret(0)
        if name == 'withAddressRanges':
            n = a[1] & 0xffffffff
            rr = [struct.unpack('<QQ', self.u.mem_read(a[0] + 16 * i, 16)) for i in range(n)]
            assert a[2] & 0xffffffff == 0x23 and a[3] == 0
            return self.ret(self.new_obj('md', ranges=rr, length=sum(l for _, l in rr)))
        if name == 'createMappingInTask':
            md, task, at, opts, off, ln = a[0], a[1], a[2], a[3] & 0xffffffff, a[4], a[5]
            o = self.objs[md]
            assert o['kind'] == 'md' and o['live'] and off == 0 and ln == 0
            self.ncreatemap += 1
            if self.fail_createmap_at == self.ncreatemap:
                return self.ret(0)
            if opts & OVERWRITE:
                va = at
            else:
                assert opts & ANYWHERE and at == 0
                va = self.va[task]
                self.va[task] += o['length'] + 0x10000
            o['refs'] = o.get('refs', 0) + 1
            m = self.new_obj('map', md=md, task=task, va=va, opts=opts, length=o['length'])
            self.log.append(('map', m, task, va, opts, o['ranges']))
            return self.ret(m)
        if addr == VT_RELEASE:
            o = self.objs[a[0]]
            assert o['live'], f'double release of {a[0]:#x}'
            if o['kind'] == 'md':
                if o.get('refs', 0) == 0:
                    o['live'] = False
            else:
                o['live'] = False
                self.log.append(('release', a[0], o['va'], o['length'], bool(o['opts'] & OVERWRITE)))
                md = self.objs[o['md']]
                md['refs'] -= 1
                if md['refs'] == 0:
                    md['live'] = False
            return self.ret(0)
        if addr == VT_GETADDR:
            return self.ret(self.objs[a[0]]['va'])
        if name == 'current_task':
            return self.ret(UTASK)
        if name == 'task_reference':
            assert a[0] == UTASK
            self.taskrefs += 1
            return self.ret(0)
        if name == 'task_deallocate':
            assert a[0] == UTASK
            self.taskrefs -= 1
            return self.ret(0)
        if name == 'get_task_map':
            return self.ret(UMAP if a[0] == UTASK else KMAP)
        if name == 'vm_deallocate':
            self.log.append(('vm_deallocate', a[0], a[1], a[2]))
            return self.ret(0)
        if name == 'kva_to_phys':
            assert 0x5aac00 <= a[0] < 0x5abe80
            return self.ret(TEXT_PHYS | (a[0] & 0xfff))

    def call(self, fn, *args, stack_args=()):
        rsp = STACK + 0x800000
        frame = [RET_MAGIC] + list(stack_args)
        rsp -= 8 * len(frame)
        if rsp % 16 != 8:                 # entry: rsp + 8 is 16-byte aligned
            rsp -= 8
        self.u.mem_write(rsp, b''.join(struct.pack('<Q', x) for x in frame))
        self.u.reg_write(UC_X86_REG_RSP, rsp)
        for reg, v in zip((UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX, UC_X86_REG_RCX, UC_X86_REG_R8,
                           UC_X86_REG_R9), args):
            self.u.reg_write(reg, v)
        callee = [UC_X86_REG_RBX, UC_X86_REG_RBP, UC_X86_REG_R12, UC_X86_REG_R13, UC_X86_REG_R14, UC_X86_REG_R15]
        sentinel = [0x1111 * (i + 1) for i in range(len(callee))]
        for reg, v in zip(callee, sentinel):
            self.u.reg_write(reg, v)
        self.u.emu_start(fn, RET_MAGIC, count=2_000_000)
        assert self.r(UC_X86_REG_RIP) == RET_MAGIC, 'did not return'
        assert self.r(UC_X86_REG_RSP) == rsp + 8, 'stack not balanced'
        for reg, v in zip(callee, sentinel):
            assert self.r(reg) == v, 'callee-saved register clobbered'
        return self.r(UC_X86_REG_RAX)

    def q(self, p):
        return struct.unpack('<Q', self.u.mem_read(p, 8))[0]

    def put_pages(self, pages):
        p = self.heap
        self.heap += 8 * len(pages) + 16
        self.u.mem_write(p, b''.join(struct.pack('<Q', x) for x in pages))
        return p


def live_maps(w):
    return [p for p, o in w.objs.items() if o['live']]


def run(img):
    UC, WC, WB, WT = 0, 1, 2, 4
    ok = 0
    groups = [0x8000000, 0x8001000, 0x9005000, 0x7000000, 0x7001000, 0x7002000]   # ranges: 2, 1, 3 pages

    # 1. user WC, three ranges, anywhere -> reservation + 3 overwrite maps
    w = World(img)
    pages = w.put_pages(groups)
    out_addr, out_h = w.heap, w.heap + 8
    w.heap += 32
    rc = w.call(MAP_USER, pages, len(groups), WC, 1, 0, out_addr, stack_args=(out_h,))
    assert rc == 0, rc
    um = w.q(out_h)
    h, task, addr, size = (w.q(um + i) for i in (0, 8, 16, 24))
    assert h & 1 and task == 0 and size == len(groups) * 0x1000
    maps = [e for e in w.log if e[0] == 'map']
    res = maps[0]
    assert res[3] == addr and res[4] == ANYWHERE | RO and res[5] == [(TEXT_PHYS, 0x1000)] * len(groups), res
    subs = maps[1:]
    assert [(e[3] - addr, e[4], e[5]) for e in subs] == [
        (0, 0x400 | OVERWRITE, [(0x8000000, 0x2000)]),
        (0x2000, 0x400 | OVERWRITE, [(0x9005000, 0x1000)]),
        (0x3000, 0x400 | OVERWRITE, [(0x7000000, 0x3000)])], subs
    assert w.q(out_addr) == addr
    w.log.clear()
    w.call(UNMAP_USER, um)
    rel = [e for e in w.log if e[0] == 'release']
    assert rel[0][1] == res[1] and not rel[0][4] and all(e[4] for e in rel[1:]) and len(rel) == 4, rel
    assert not [e for e in w.log if e[0] == 'vm_deallocate']
    assert not w.allocs and not live_maps(w), (w.allocs, live_maps(w))
    ok += 1

    # 2. user WB (cached), three ranges -> one multi-range mapping, as before
    w = World(img)
    pages = w.put_pages(groups)
    out_addr, out_h = w.heap, w.heap + 8
    w.heap += 32
    assert w.call(MAP_USER, pages, len(groups), WB, 0, 0, out_addr, stack_args=(out_h,)) == 0
    um = w.q(out_h)
    maps = [e for e in w.log if e[0] == 'map']
    assert len(maps) == 1 and maps[0][4] == ANYWHERE | RO and len(maps[0][5]) == 3 and not w.q(um) & 1
    w.call(UNMAP_USER, um)
    assert not w.allocs and not live_maps(w)
    ok += 1

    # 3. user UC, one contiguous range -> single mapping
    w = World(img)
    pages = w.put_pages([0x5000000 + 0x1000 * i for i in range(4)])
    out_addr, out_h = w.heap, w.heap + 8
    w.heap += 32
    assert w.call(MAP_USER, pages, 4, UC, 1, 0, out_addr, stack_args=(out_h,)) == 0
    maps = [e for e in w.log if e[0] == 'map']
    assert len(maps) == 1 and maps[0][4] == ANYWHERE | 0x100 and maps[0][5] == [(0x5000000, 0x4000)]
    w.call(UNMAP_USER, w.q(out_h))
    assert not w.allocs and not live_maps(w)
    ok += 1

    # 4. user WC, fixed -> overwrite maps at fixed, task referenced, unmap deallocates the range first
    w = World(img)
    pages = w.put_pages(groups)
    out_addr, out_h = w.heap, w.heap + 8
    w.heap += 32
    fixed = 0x200000000
    assert w.call(MAP_USER, pages, len(groups), WC, 1, fixed, out_addr, stack_args=(out_h,)) == 0
    um = w.q(out_h)
    maps = [e for e in w.log if e[0] == 'map']
    assert len(maps) == 3 and [e[3] for e in maps] == [fixed, fixed + 0x2000, fixed + 0x3000]
    assert w.q(um + 8) == UTASK and w.taskrefs == 1
    w.log.clear()
    w.call(UNMAP_USER, um)
    assert w.log[0] == ('vm_deallocate', UMAP, fixed, len(groups) * 0x1000), w.log[0]
    assert w.taskrefs == 0 and not w.allocs and not live_maps(w)
    ok += 1

    # 5. kernel WC vmap, three ranges -> split in kernel_task; unmap releases all
    w = World(img)
    pages = w.put_pages(groups)
    hp = w.heap
    w.heap += 16
    kva = w.call(MAP_PAGES, pages, len(groups), WC, hp)
    h = w.q(hp)
    maps = [e for e in w.log if e[0] == 'map']
    assert h & 1 and kva == maps[0][3] and all(e[2] == KTASK for e in maps) and len(maps) == 4
    assert maps[0][4] == ANYWHERE | RO | 0x100 and maps[0][5] == [(groups[0], len(groups) * 0x1000)], maps[0]
    assert [(e[3] - kva, e[5]) for e in maps[1:]] == [(0, [(0x8000000, 0x2000)]), (0x2000, [(0x9005000, 0x1000)]),
                                                     (0x3000, [(0x7000000, 0x3000)])]
    assert [e[4] for e in maps[1:]] == [0x400 | OVERWRITE] * 3
    w.call(UNMAP, h)
    assert not w.allocs and not live_maps(w)
    ok += 1

    # 6. kernel WB vmap -> one mapping, handle untagged, unmap still works
    w = World(img)
    pages = w.put_pages(groups)
    hp = w.heap
    w.heap += 16
    kva = w.call(MAP_PAGES, pages, len(groups), WB, hp)
    assert kva and not w.q(hp) & 1 and len([e for e in w.log if e[0] == 'map']) == 1
    w.call(UNMAP, w.q(hp))
    assert not w.allocs and not live_maps(w)
    ok += 1

    # 7. failures: the n-th createMappingInTask fails -> error, nothing leaked
    for fixed in (0, 0x300000000):
        for nth in range(1, 4 if fixed else 5):     # 3 overwrite maps, plus the reservation when not fixed
            w = World(img)
            w.fail_createmap_at = nth
            pages = w.put_pages(groups)
            out_addr, out_h = w.heap, w.heap + 8
            w.heap += 32
            rc = w.call(MAP_USER, pages, len(groups), WC, 1, fixed, out_addr, stack_args=(out_h,))
            assert rc == (22 if fixed else 12), rc
            assert w.q(out_h) == 0 and w.q(out_addr) == 0
            assert not w.allocs and not live_maps(w), (nth, fixed, w.allocs, live_maps(w))
            if fixed:
                assert ('vm_deallocate', UMAP, fixed, len(groups) * 0x1000) in w.log
            ok += 1
    for nth in (1, 2, 3, 4):
        w = World(img)
        w.fail_createmap_at = nth
        pages = w.put_pages(groups)
        hp = w.heap
        w.heap += 16
        assert w.call(MAP_PAGES, pages, len(groups), WC, hp) == 0 and w.q(hp) == 0
        assert not w.allocs and not live_maps(w)
        ok += 1

    # 8. argument checks
    w = World(img)
    out_addr, out_h = w.heap, w.heap + 8
    w.heap += 32
    assert w.call(MAP_USER, w.heap, 0, WC, 1, 0, out_addr, stack_args=(out_h,)) == 22
    assert w.call(MAP_USER, w.heap, 1, WC, 1, 0x1234, out_addr, stack_args=(out_h,)) == 22
    w.call(UNMAP, 0)
    w.call(UNMAP_USER, 0)
    ok += 1
    print(f'emu_test: {ok} cases passed')


if __name__ == '__main__':
    run(open(sys.argv[1], 'rb').read())
