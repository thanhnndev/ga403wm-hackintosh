#!/usr/bin/env python3
"""ws-spin-buckets.py <mode.spin.txt> <presents> [thread-filter]: WS-CPU.md section 4 reader.
Counts ON-CPU samples only (1 ms each): a user frame's self samples (not marked runnable/blocked) and kernel self
samples marked (running). Attributes each to a layer by its stack:
  plugin  = an NVMTLDriver frame is on the stack and no RADV/libdrm frame below it
  radv    = a libvulkan_radeon / libdrm frame is on the stack (user part)
  k-drv   = kernel samples under a plugin/RADV/libdrm frame (ioctls: CS, BO, syncobj)
  k-other = other kernel samples (mach_msg, IOSurface, VM faults ...)
  rest    = by the leaf binary (QuartzCore, SkyLight, CoreDisplay, libobjc, malloc, Metal ...)
Prints ms per present per thread group, then the top self functions in plugin and RADV and the plugin's top inclusive
entry points (the first NVMTLDriver frame of each stack)."""
import re, sys, collections
path, presents = sys.argv[1], int(sys.argv[2]); filt = sys.argv[3] if len(sys.argv) > 3 else None
line_re = re.compile(r'^(\s*)(\*?)(\d+)\s+(.*)$')
def binary(fr):
    m = re.search(r'\(([^()+]+?) \+ \d+\)', fr)
    return m.group(1).strip() if m else ('kernel' if fr.startswith('???') else '?')
def fname(fr):
    return re.sub(r' \+ \d+ \(.*$', '', fr).strip()
PLUG = ('NVMTLDriver',); RADV = ('libvulkan_radeon.dylib', 'libdrm_amdgpu.1.dylib', 'libdrm.2.dylib', 'libvulkan.1.dylib', 'libvulkan.1.4.362.dylib')
threads = []; cur = None
for raw in open(path, errors='replace'):
    if raw.startswith('  Thread 0x'):
        if cur: threads.append(cur)
        if raw.startswith('  Thread 0x') and ('Process:' in raw): pass
        cur = {'hdr': raw.strip(), 'nodes': []}; continue
    if raw.startswith('Process:') and cur: threads.append(cur); cur = None; 
    if raw.startswith('Process:') and threads: break_proc = True
    if cur is None: continue
    m = line_re.match(raw.rstrip('\n'))
    if not m: continue
    ind = len(m.group(1)); cur['nodes'].append((ind, int(m.group(3)), m.group(4), bool(m.group(2))))
if cur: threads.append(cur)
def analyse(t):
    nodes = t['nodes']; res = collections.Counter(); selfp = collections.Counter(); selfr = collections.Counter(); entry = collections.Counter(); rest = collections.Counter(); ksys = collections.Counter()
    stack = []
    for i, (ind, cnt, fr, kern) in enumerate(nodes):
        while stack and stack[-1][0] >= ind: stack.pop()
        stack.append((ind, fr, kern))
        child = 0; j = i + 1; cind = None
        while j < len(nodes) and nodes[j][0] > ind:
            if cind is None: cind = nodes[j][0]
            if nodes[j][0] == cind: child += nodes[j][1]
            j += 1
        s = cnt - child
        if s <= 0: continue
        if kern: oncpu = '(running)' in fr
        else: oncpu = '(runnable)' not in fr and 'blocked' not in fr
        if not oncpu: continue
        users = [f for (_, f, k) in stack if not k]
        bins = [binary(f) for f in users]
        inplug = any(b in PLUG for b in bins); inradv = any(b in RADV for b in bins)
        leaf = users[-1] if users else fr
        # a kernel sample is kernel time only below a syscall stub; below any other user frame it is the stackshot's
        # own interrupt of a thread that was running that user frame
        if kern and binary(leaf) == 'libsystem_kernel.dylib':
            res['k-drv' if (inplug or inradv) else 'k-other'] += s
            callers = [fname(f) for f in users if binary(f) != 'libsystem_kernel.dylib' and binary(f) not in ('libsystem_platform.dylib','libdispatch.dylib')]
            ksys[('drv ' if (inplug or inradv) else 'oth ') + fname(leaf) + ' <- ' + ' <- '.join(reversed(callers[-2:]))] += s
        else:
            fr2 = leaf if kern else fr
            if binary(fr2) in RADV or inradv: res['radv'] += s; selfr[fname(fr2) + ' [' + binary(fr2) + ']'] += s
            elif binary(fr2) in PLUG or inplug: res['plugin'] += s; selfp[fname(fr2) + ' [' + binary(fr2) + ']'] += s
            else: res['rest'] += s; rest[binary(fr2)] += s
        if inplug:
            for (_, f, k) in stack:
                if not k and binary(f) in PLUG: entry[fname(f)] += s; break
    return res, selfp, selfr, entry, rest, ksys
groups = collections.OrderedDict()
for t in threads:
    h = t['hdr']; name = re.search(r'Thread name "([^"]+)"', h); q = re.search(r'DispatchQueue "([^"]+)"', h)
    key = name.group(1) if name else (q.group(1) if q else h[:40])
    if filt and filt not in key: continue
    if 'cpu time' not in h or re.search(r'cpu time <0\.001s', h): continue   # never ran in the window
    g = groups.setdefault(key, [collections.Counter() for _ in range(6)])
    for a, b in zip(g, analyse(t)): a.update(b)
tot = collections.Counter()
print(f"{path}: {presents} presents; on-CPU ms per present (1 ms samples)")
for k, (res, selfp, selfr, entry, rest, ksys) in groups.items():
    n = sum(res.values())
    if n < presents * 0.05: continue
    tot.update(res)
    print(f"\n== {k}: {n/presents:.2f} ms/present  " + "  ".join(f"{b} {res[b]/presents:.2f}" for b in ('plugin','radv','k-drv','k-other','rest')))
    print("   rest by binary: " + ", ".join(f"{b} {c/presents:.2f}" for b, c in rest.most_common(8)))
    print("   plugin entry points (inclusive): " + "; ".join(f"{f} {c/presents:.2f}" for f, c in entry.most_common(8)))
    print("   plugin self: " + "; ".join(f"{f} {c/presents:.2f}" for f, c in selfp.most_common(10)))
    print("   kernel by syscall <- caller: " + "; ".join(f"{f} {c/presents:.2f}" for f, c in ksys.most_common(8)))
    print("   radv self: " + "; ".join(f"{f} {c/presents:.2f}" for f, c in selfr.most_common(8)))
print("\nALL listed threads: " + "  ".join(f"{b} {tot[b]/presents:.2f}" for b in ('plugin','radv','k-drv','k-other','rest')) + f"  total {sum(tot.values())/presents:.2f} ms/present")
