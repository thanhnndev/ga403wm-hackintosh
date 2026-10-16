# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Round-11 raw dump: what happens after the BSD attach gate check passes (read-only, no reboot needed).

Usage: KC=<BootKernelExtensions.kc> python3 tools/dump_native_wifi_round11.py <out-dir>
Questions answered by these dumps: how setInterfaceEnable / finalizeBSDInterface / updateCountryCodeProperty behave, how an ioctl from
sendIOUCToWcl reaches the controller (isCommandProhibited, apple80211Request, the 802.11 getters), and what the IO80211Controller
bring-up (IOUserClient / WCL glue init) expects from a driver.
Writes: the exact functions below plus every IO80211WCLGlue / IO80211InfraInterface function (size capped).
"""
import contextlib
import hashlib
import json
from pathlib import Path
import re
import sys
import kc

EXPECTED = 'cd013c14a7f21dbb8181fb06c44e079de8646b6a674abe21f6e47f42e8979af3'
if hashlib.sha256(kc.d).hexdigest() != EXPECTED:
    sys.exit('Unsupported KC: verified only for the recorded 24H32 hash')
if kc.md is None:
    sys.exit('Capstone required')

EXACT = [
    '__ZN21IO80211InfraInterface18setInterfaceEnableEb',
    '__ZN23IO80211SkywalkInterface18setInterfaceEnableEb',
    '__ZN21IO80211InfraInterface20finalizeBSDInterfaceEP7__ifnetj',
    '__ZN21IO80211InfraInterface25updateCountryCodePropertyEb',
    '__ZN17IO80211Controller17apple80211RequestEjiP23IO80211SkywalkInterfaceP19apple80211_requestPv',
    '__ZN17IO80211Controller16isCommandProhibitedEi',
    '__ZN11IO80211Glue10sendIOUCToWclEjjPvmRb',
    '__ZN11IO80211Glue13sendIOUCToWclEjjPvmRb',
]
CLASS_RE = re.compile(r'^__ZN(?:\d+IO80211WCLGlue|\d+IO80211InfraInterface)\d')
WORKLOOP_RE = re.compile(r'^__ZN\d+IO80211\w*(?:apple80211Request|handleIoctl|ioctl)\w*')
by_name = {n: a for a, n in kc.syms.items()}
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
found = {}
missing = []


def dump(name, addr, cap=6000):
    stem = re.sub(r'[^A-Za-z0-9]+', '_', name.lstrip('_'))[:110] + '_' + hex(addr)[-6:]
    lo, hi = kc.func_range(addr)
    if hi - lo > cap * 8:
        found[name] = {'file': None, 'address': hex(addr), 'skipped': 'size %d' % (hi - lo)}
        return
    with (out / (stem + '.asm.txt')).open('w') as stream, contextlib.redirect_stdout(stream):
        print('#', hex(addr), name)
        kc.disasm(lo, hi, comment_strings=True)
    found[name] = {'file': stem + '.asm.txt', 'address': hex(addr)}


for n in EXACT:
    if n in by_name:
        dump(n, by_name[n])
    else:
        missing.append(n)
for a, n in sorted(kc.syms.items()):
    if n not in found and (CLASS_RE.match(n) or WORKLOOP_RE.match(n)) and 'MetaClass' not in n:
        dump(n, a)

(out / 'missing.txt').write_text('\n'.join(missing) + '\n')
(out / 'source.json').write_text(json.dumps({'sha256': EXPECTED, 'tool': 'tools/dump_native_wifi_round11.py', 'functions': found}, indent=2) + '\n')
print('%d functions, %d missing' % (len(found), len(missing)))
print('\n'.join(missing))
