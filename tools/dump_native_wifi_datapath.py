# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Read-only 24H32 packet ownership/dequeue/completion dumps. KC=<kc> python <tool> <out-dir>."""
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
classes = ('IOSkywalkPacket', 'IOSkywalkTxSubmissionQueue', 'IOSkywalkTxCompletionQueue',
           'IOSkywalkRxCompletionQueue', 'IOSkywalkPacketBufferPool', 'IO80211SkywalkInterface',
           'IOSkywalkNetworkInterface', 'IONetworkController')
terms = ('getDataVirtualAddress', 'getDataLength', 'getBufferSize', 'getPacketBufferCount',
         'setDataLength', 'setDataOffset', 'getDataOffset', 'completeWithQueue', 'completeE',
         'allocatePacketE', 'deallocatePacketE', 'enqueuePackets', 'synchronize',
         'refillTxRingForNetworking', 'getPacketListForNetworking', 'enableEv', 'disableEv',
         'packetCompletion', 'checkForWork', 'packetSubmission', 'completePackets',
         'withPool', 'initWithPool', 'requestDequeue', 'legacyDequeue',
         'setInterfaceEnable', 'setRunningState', 'completePreparedPacket',
         'reportLinkStatus', 'reportEventType', 'setLinkStatus', '_broadcastEvent')
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
found = {}
for address, name in sorted(kc.syms.items()):
    if not any(c in name for c in classes) or not any(t in name for t in terms):
        continue
    if not any(vm <= address < vm + fs and protection & 4 for _, vm, _, _, fs, protection in kc.segs):
        continue
    lo, hi = kc.func_range(address)
    if hi - lo > 48000:
        found[name] = {'address': hex(address), 'skipped': hi-lo}
        continue
    filename = re.sub('[^A-Za-z0-9]+', '_', name.lstrip('_'))[:110] + '_' + hex(address)[-6:] + '.asm.txt'
    with (out / filename).open('w') as stream, contextlib.redirect_stdout(stream):
        print('#', hex(address), name)
        kc.disasm(lo, hi, comment_strings=True)
    found[name] = {'address': hex(address), 'file': filename}
(out / 'source.json').write_text(json.dumps({'sha256': EXPECTED, 'tool': __file__, 'functions': found}, indent=2)+'\n')
print('%d executable functions' % len(found))
