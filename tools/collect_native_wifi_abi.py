# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Read-only native Wi-Fi ABI collection. Set KC, then run with an output directory.

Raw Apple disassembly is collected in build/ before review. Capstone is required.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if not os.environ.get('KC'):
        parser.error('set KC to the target BootKernelExtensions.kc')
    import kc
    import kc_vtable as vt
    if kc.md is None:
        parser.error('Capstone is required; install it in a local venv')
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {}

    def save(name, action):
        with (args.output / name).open('w') as stream, contextlib.redirect_stdout(stream):
            action()

    classes = ['IO80211Controller', 'IO80211SkywalkInterface', 'IO80211InfraInterface',
               'IO80211WorkQueue', 'IO80211CommandGate', 'IO80211Peer',
               'IO80211VirtualInterface', 'IO80211ControllerMonitor',
               'AppleBCMWLANCore', 'AppleBCMWLANSkywalkInterface',
               'IOSkywalkEthernetInterface', 'IOSkywalkNetworkInterface',
               'IOSkywalkPacketQueue', 'IOSkywalkPacketBufferPool',
               'IOSkywalkTxSubmissionQueue', 'IOSkywalkRxCompletionQueue',
               'IOSkywalkTxCompletionQueue', 'IOSkywalkRxSubmissionQueue',
               'IOSkywalkPacket', 'CCPipe', 'CCStream', 'CCLogStream', 'CCLogPipe',
               'CCFaultReporter', 'AppleBCMWLANPCIeSkywalk',
               'AppleBCMWLANPCIeSkywalkPacketPool', 'IO80211Glue']
    for cls in classes:
        try:
            summary[cls] = len(vt.vtable(cls))
            save(cls + '.vtable.txt', lambda: vt.cmd_vtable(cls))
        except SystemExit as error:
            summary[cls] = str(error)
        save(cls + '.methods.txt', lambda: vt.cmd_methods(cls))
        constructors = [(a, n) for a, n in sorted(kc.syms.items())
                        if n.startswith('__ZN%d%s9MetaClassC' % (len(cls), cls))]
        def dump_constructors():
            if not constructors:
                print('# No MetaClass constructor symbol in this collection')
            for address, name in constructors:
                print('#', hex(address), name)
                kc.disasm(*kc.func_range(address), comment_strings=False)
        save(cls + '-MetaClass.asm.txt', dump_constructors)
    if isinstance(summary['AppleBCMWLANSkywalkInterface'], int):
        save('skywalk-if.diff', lambda: vt.cmd_compare('IO80211SkywalkInterface', 'AppleBCMWLANSkywalkInterface'))
    targets = {
        'AppleBCMWLANCore': ['start', 'createWorkQueue', 'SCAN', 'ASSOCIATE', 'getCARD_CAPABILITIES', 'handleCardSpecific', 'getLogger', 'getWorkQueue'],
        'IO80211Controller': ['start', 'createWorkQueue', 'attachInterface'],
        'IO80211SkywalkInterface': ['init', 'start', 'register', 'processBSDCommand', 'performGatedCommandIOCTL', 'routeIoctlToWcl'],
        'IO80211InfraInterface': ['init', 'start', 'registerInfraEthernetInterface'],
        'AppleBCMWLANSkywalkInterface': ['initWithProviderAndParameters', 'start', 'withProvider'],
    }
    targets.update({
        'IO80211Glue': ['sendIOUCToWcl'],
        'CCPipe': ['withOwnerNameCapacity', 'initWithOwnerNameCapacity'],
        'CCStream': ['withPipeAndName', 'initWithPipeAndName'],
        'CCLogStream': ['withPipeAndName', 'initWithPipeAndName'],
        'CCLogPipe': ['withOwnerNameCapacity'],
        'AppleBCMWLANPCIeSkywalk': ['withProviderAndCapacity', 'initWithProviderAndCapacity'],
        'AppleBCMWLANPCIeSkywalkPacketPool': ['withName'],
        'IOSkywalkEthernetInterface': ['registerEthernetInterface'],
        'IOSkywalkPacketBufferPool': ['withName', 'initWithName'],
    })
    for cls, terms in targets.items():
        pattern = re.compile(r'^__ZNK?%d%s(\d+)([A-Za-z_][A-Za-z_0-9]*)' % (len(cls), cls))
        for term in terms:
            selected = []
            for address, name in sorted(kc.syms.items()):
                match = pattern.match(name)
                if match:
                    method = match[2][:int(match[1])]
                    if method == term or (term.isupper() and term in method):
                        selected.append((address, name))
            def dump():
                if not selected:
                    print('# No matching method in this collection')
                for address, name in selected:
                    print('#', hex(address), name)
                    kc.disasm(*kc.func_range(address), comment_strings=False)
            save(cls + '-' + term + '.asm.txt', dump)
    for function in ('apple80211RouteExternal', 'apple80211RouteInternal'):
        prefix = '__Z%d%s' % (len(function), function)
        def dump_function():
            for address, name in sorted(kc.syms.items()):
                if name.startswith(prefix):
                    print('#', hex(address), name)
                    kc.disasm(*kc.func_range(address), comment_strings=False)
        save(function + '.asm.txt', dump_function)
    metadata = {'kc': kc.KC, 'sha256': hashlib.sha256(kc.d).hexdigest(),
                'system': (subprocess.check_output(['sw_vers'], text=True) if __import__('shutil').which('sw_vers') else os.environ.get('SYSTEM_NOTE', 'unknown (collected on Linux from a mounted volume)')),
                'darwin': subprocess.check_output(['uname', '-r'], text=True).strip(),
                'vtables_symbol_spans': summary,
                'collection_entries': [name for name, _, _ in kc.entries
                                       if any(part in name for part in ('80211', 'Skywalk', 'BCMWLAN', 'corecapture'))]}
    (args.output / 'source.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(args.output)


if __name__ == '__main__':
    main()
