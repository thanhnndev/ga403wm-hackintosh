# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Read-only 24H32 RX/identity/link lifecycle evidence. KC=<kc> python <tool> <out>."""
import contextlib
import hashlib
import json
from pathlib import Path
import re
import sys
import kc

EXPECTED = 'cd013c14a7f21dbb8181fb06c44e079de8646b6a674abe21f6e47f42e8979af3'
if hashlib.sha256(kc.d).hexdigest() != EXPECTED or kc.md is None:
    sys.exit('Requires recorded 24H32 KC and Capstone')
METHODS = {
 'IOSkywalkPacket': ('initWithPool', 'acquireWithPacketHandle', 'prepareWithQueue', 'prepare', 'completeWithQueue', 'complete', 'getPacketBufferCount', 'getDataVirtualAddress', 'setDataOffsetAndLength'),
 'IOSkywalkPacketBufferPool': ('newPacket', 'allocatePacket', 'deallocatePacket', 'completePreparedPacket'),
 'IOSkywalkPacketBuffer': ('prepare', 'complete'),
 'IOSkywalkNetworkPacket': ('withPool', 'setHeadroom', 'setLinkHeaderLength', 'setLinkHeaderOffset', 'setNetworkHeaderOffset', 'setDataContainsFCS', 'setIsLinkBroadcast', 'setIsLinkMulticast', 'setRxChecksumInfo'),
 'IOSkywalkRxCompletionQueue': ('enqueuePackets', 'enqueuePacketsForNetworking'),
 'IOSkywalkEthernetInterface': ('prepareBSDInterface', 'copyRegistrationInfo'),
 'IO80211SkywalkInterface': ('init', 'initIvars', 'start', 'getHardwareAddress', 'setHardwareAddress'),
 'IO80211InfraInterface': ('registerInfraEthernetInterface', 'updateMediumStatus', 'setLinkState', 'setLinkStateInternal', 'updateLinkSpeed', 'handleKeyDone'),
 'IO80211MacAddressAgent': ('initWithOptions', 'updateMacAddress', 'setMacAddress'),
 'AppleBCMWLANSkywalkInterface': ('initWithProviderAndParameters',),
 'AppleBCMWLANPCIeSkywalkPacketPool': ('allocatePacket',),
 'IOSkywalkNetworkBSDClient': ('enableInterface', 'gatedPrepareNexus'),
}
EXACT = {'_ifnet_set_offload', '_ifnet_set_lladdr', '_kern_packet_finalize', '_kern_netif_queue_rx_enqueue'}
patterns = [re.compile(r'^__ZNK?' + str(len(c)) + c + str(len(m)) + m + r'(?=E)')
            for c, methods in METHODS.items() for m in methods]
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
found = {}
for address, name in sorted(kc.syms.items()):
    if name not in EXACT and not any(p.match(name) for p in patterns): continue
    if not any(vm <= address < vm + fs and prot & 4 for _, vm, _, _, fs, prot in kc.segs): continue
    lo, hi = kc.func_range(address)
    if hi - lo > 48000: sys.exit('Function too large: ' + name)
    filename = re.sub('[^A-Za-z0-9]+', '_', name.lstrip('_'))[:110] + '_' + hex(address)[-6:] + '.asm.txt'
    with (out / filename).open('w') as stream, contextlib.redirect_stdout(stream):
        print('#', hex(address), name); kc.disasm(lo, hi, comment_strings=True)
    found[name] = {'address': hex(address), 'file': filename}
(out / 'source.json').write_text(json.dumps({'sha256': EXPECTED, 'tool': 'tools/dump_native_wifi_rx_root.py', 'functions': found}, indent=2) + '\n')
print('%d executable functions' % len(found))
