# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Round-12 raw dump: media ioctls, interface enable and the skywalk interface base classes (read-only, no reboot needed).

Usage: KC=<BootKernelExtensions.kc> python3 tools/dump_native_wifi_round12.py <out-dir>
Questions answered by these dumps: why SIOCGIFXMEDIA on the published interface returns EIO (IOSkywalkNetworkInterface /
IOSkywalkEthernetInterface processBSDCommand + ioctl_gifmedia, getSupportedMediaArray, getInitialMedia), what ifconfig up
(enable / setInterfaceEnable / enableDatapath callers) needs from the driver, and which controller properties and messages the
userland Wi-Fi stack sees (link state, postMessage, MAC address agent, association snapshot, command gate sleep/wakeup).
Writes: the exact functions below plus every IOSkywalkNetworkInterface / IOSkywalkEthernetInterface function (size capped).
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
    '__ZN23IO80211SkywalkInterface6enableEj',
    '__ZN23IO80211SkywalkInterface7disableEj',
    '__ZN23IO80211SkywalkInterface17createIOReportersEv',
    '__ZN23IO80211SkywalkInterface14enableDatapathEv',
    '__ZN23IO80211SkywalkInterface15disableDatapathEv',
    '__ZN28AppleBCMWLANSkywalkInterface6enableEj',
    '__ZN28AppleBCMWLANSkywalkInterface7disableEj',
    '__ZN28AppleBCMWLANSkywalkInterface14enableDatapathEv',
    '__ZN28AppleBCMWLANSkywalkInterface15disableDatapathEv',
    '__ZN22IO80211MacAddressAgent18setInterfaceEnableEb',
    '__ZN18IO80211CommandGate12commandSleepEPvy',
    '__ZN18IO80211CommandGate13commandWakeupEPv',
    '__Z29apple80211getHARDWARE_VERSIONP23IO80211SkywalkInterfaceP23apple80211_version_data',
    '__Z25apple80211getCOUNTRY_CODEP23IO80211SkywalkInterfaceP28apple80211_country_code_data',
]
# whole classes (size capped): the skywalk base interfaces, plus anything that creates the association snapshot / mac address agent
CLASS_RE = re.compile(r'^__ZN(?:25IOSkywalkNetworkInterface|26IOSkywalkEthernetInterface|27IO80211AssociationJoinSnapshot|22IO80211MacAddressAgent)\d')
# link state / message plumbing the userland Wi-Fi stack observes
WORKLOOP_RE = re.compile(r'^__ZN\d+IO80211\w*?(?:setLinkState|postMessage|reportLinkStatus|updateLinkStatus|setLinkQuality)\w*')
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
(out / 'source.json').write_text(json.dumps({'sha256': EXPECTED, 'tool': 'tools/dump_native_wifi_round12.py', 'functions': found}, indent=2) + '\n')
print('%d functions, %d missing' % (len(found), len(missing)))
print('\n'.join(missing))
