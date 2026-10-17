# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Shared logic of gen_io80211_header.py / check_io80211_header.py for the interface-side classes.

A class header is derived from one vtable dump (`<Class>.vtable.txt`, written by tools/kc_vtable.py) of one macOS build:
  * slot numbers count the two header words, as in the dump;
  * slots whose symbol is owned by the class itself are either overrides (slot <= last slot of the parent) or new virtuals;
  * a pure-virtual slot takes its name from the first derived class dump that overrides it;
  * the parent is the SDK class named in CLASSES (IOWorkLoop, OSObject, IOSkywalkInterface) or another generated header.
Return types are not part of an Itanium mangled name. Overrides take the return type from the SDK header of the class that
declares the method, new virtuals from RET (call-site evidence) or from NAME_RULES (a guess from the name, tagged "guess").
"""
import json
import os
import re
import subprocess

# class -> (parent, header the parent comes from, instance size from the MetaClass constructor, derived dumps naming pure slots)
CLASSES = {
    # IOSkywalkInterface has no dump of its own: its slots (<= cut) are read from its subclass IOSkywalkNetworkInterface's dump;
    # slots that subclass overrides cannot be attributed and are left to the inherited declaration. Size: the SDK's sizeof.
    'IOSkywalkInterface': dict(parent='IOService', include='<IOKit/IOService.h>', size=0xb0, source='IOSkywalkNetworkInterface',
                               cut=283, parent_last=267, size_src='SDK sizeof(IOSkywalkInterface); not seen in Apple\'s binary',
                               children=[]),
    'IO80211WorkQueue': dict(parent='IOWorkLoop', include='<IOKit/IOWorkLoop.h>', size=0x50, children=[]),
    'IO80211CommandGate': dict(parent='OSObject', include='<libkern/c++/OSObject.h>', size=0x18, children=[]),
    'IOSkywalkNetworkInterface': dict(parent='IOSkywalkInterface', include='"IOSkywalkInterface.h"', size=0xd0,
                                      children=['IOSkywalkEthernetInterface']),
    'IOSkywalkEthernetInterface': dict(parent='IOSkywalkNetworkInterface', include='"IOSkywalkNetworkInterface.h"', size=0x110,
                                       children=['IO80211SkywalkInterface']),
    'IO80211SkywalkInterface': dict(parent='IOSkywalkEthernetInterface', include='"IOSkywalkEthernetInterface.h"', size=0x118,
                                    children=['IO80211InfraInterface', 'AppleBCMWLANSkywalkInterface']),
    'IO80211InfraInterface': dict(parent='IO80211SkywalkInterface', include='"IO80211SkywalkInterface.h"', size=0x120,
                                  children=['IO80211InfraProtocol', 'AppleBCMWLANSkywalkInterface']),
    # the Family's protocol class: IO80211InfraInterface plus 190 pure virtuals (slots 467-656) that the Family's request
    # routing calls; names come from AppleBCMWLANInfraProtocol (round 5). Same instance size as its parent (no ivars).
    'IO80211InfraProtocol': dict(parent='IO80211InfraInterface', include='"IO80211InfraInterface.h"', size=0x120,
                                 children=['AppleBCMWLANInfraProtocol', 'AppleBCMWLANSkywalkInterface']),   # 2nd: names slot 417 (setMacAddress)
    # the Family's generic peer-to-peer / AWDL interface (role 6 creates the AWDL peer manager): what setVIRTUAL_IF_CREATE
    # instantiates on this driver (the Broadcom path instantiates its own IO80211AWDLProtocol subclass instead).
    # Size 0x130 from the MetaClass constructor (OSMetaClassC2(..., 0x130)); parent from the MetaClass at 0xffffff800248dfa0.
    'IO80211VirtualInterface': dict(parent='IO80211SkywalkInterface', include='"IO80211SkywalkInterface.h"', size=0x130,
                                    children=[]),
}
ORDER = ['IOSkywalkInterface', 'IO80211WorkQueue', 'IO80211CommandGate', 'IOSkywalkNetworkInterface', 'IOSkywalkEthernetInterface',
         'IO80211SkywalkInterface', 'IO80211InfraInterface', 'IO80211InfraProtocol', 'IO80211VirtualInterface']

# exported non-virtual members the stub calls (they do not change the layout): class -> [(mangled symbol, declaration, evidence)].
# The mangled symbol must be in <Class>.methods.txt of the dump or generation stops.
STATICS = {
    # non-virtual members the native interface calls (symbols from the method dumps; return types are guesses, the callers ignore
    # or only test them). A None symbol is a plain declaration needed so that the mangled parameter type resolves.
    'IOSkywalkEthernetInterface': [
        (None, 'struct RegistrationInfo;', 'distinct from IOSkywalkNetworkInterface::RegistrationInfo (mangled as IOSkywalkEthernetInterface::RegistrationInfo); 0x130 bytes, ABI-2 section 2'),
        ('__ZN26IOSkywalkEthernetInterface20initRegistrationInfoEPNS_16RegistrationInfoEjm',
         'IOReturn initRegistrationInfo(RegistrationInfo* info, uint32_t version, unsigned long size);',
         'AppleBCMWLANCore::createSkywalkInterface calls it with (info, 1, 0x130) on a zeroed block; result ignored'),
        ('__ZN26IOSkywalkEthernetInterface25registerEthernetInterfaceEPKNS_16RegistrationInfoEPP20IOSkywalkPacketQueuejP25IOSkywalkPacketBufferPoolS7_j',
         'IOReturn registerEthernetInterface(RegistrationInfo const* info, IOSkywalkPacketQueue** queues, uint32_t count, IOSkywalkPacketBufferPool* txPool, IOSkywalkPacketBufferPool* rxPool, uint32_t flags);',
         'registers the ifnet of a virtual interface (AppleBCMWLANProximityInterface::start / AppleBCMWLANIO80211APSTAInterface::start call it; the AWDL interface does too)'),
    ],
    'IO80211SkywalkInterface': [
        ('__ZN23IO80211SkywalkInterface16getInterfaceRoleEv', 'uint32_t getInterfaceRole();', 'AppleBCMWLANSkywalkInterface::start compares the result with 1'),
        ('__ZN23IO80211SkywalkInterface16setInterfaceRoleEj', 'void setInterfaceRole(uint32_t role);', 'called by AppleBCMWLANSkywalkInterface::initWithProviderAndParameters'),
        ('__ZN23IO80211SkywalkInterface14getInterfaceIdEv', 'uint32_t getInterfaceId();', 'queue factories take it as ifId'),
        ('__ZN23IO80211SkywalkInterface12getWorkQueueEv', 'IO80211WorkQueue* getWorkQueue();', 'AppleBCMWLANSkywalkInterface::start takes the interface\'s work queue from it; result used with the IOWorkLoop virtuals'),
        ('__ZN23IO80211SkywalkInterface14setInterfaceIdEj', 'void setInterfaceId(uint32_t id);', 'called by AppleBCMWLANSkywalkInterface::initWithProviderAndParameters'),
    ],
    'IO80211InfraInterface': [
        ('__ZN21IO80211InfraInterface30registerInfraEthernetInterfaceEPN26IOSkywalkEthernetInterface16RegistrationInfoEPP20IOSkywalkPacketQueuejP25IOSkywalkPacketBufferPoolS7_',
         'IOReturn registerInfraEthernetInterface(IOSkywalkEthernetInterface::RegistrationInfo* info, IOSkywalkPacketQueue** queues, uint32_t count, IOSkywalkPacketBufferPool* txPool, IOSkywalkPacketBufferPool* rxPool);',
         'AppleBCMWLANSkywalkInterface::start registers the queue array and the pool(s) with it'),
    ],
    'IO80211WorkQueue': [
        ('__ZN16IO80211WorkQueue9workQueueEv', 'static IO80211WorkQueue *workQueue();',
         'AppleBCMWLANCore::createWorkQueue calls it when boot-arg wlan.workQueue.create is set'),
    ],
}

# overrides whose declaring class is outside the SDK subset we check or not unique in it: name -> return type
RET_OVERRIDE = {
    'init': 'bool', 'free': 'void', 'start': 'bool', 'stop': 'void', 'joinPMtree': 'void', 'setAggressiveness': 'IOReturn',
    'setPowerState': 'IOReturn', 'maxCapabilityForDomainState': 'unsigned long', 'initialPowerStateForDomainState': 'unsigned long',
    'newUserClient': 'IOReturn', 'stringFromReturn': 'const char *', 'errnoFromReturn': 'int',
    'configureReport': 'IOReturn', 'updateReport': 'IOReturn', 'enable': 'IOReturn', 'disable': 'IOReturn',
    'getRunLoop': None,
}

# new virtuals: name -> (return type, evidence). Everything else falls to NAME_RULES (guess).
RET = {
    'getLogger': ('CCLogStream *', 'result used with CCLogStream::shouldLog in AppleBCMWLANSkywalkInterface'),
    'getNumTxQueues': ('uint8_t', 'AppleBCMWLANSkywalkInterface::getNumTxQueues returns the byte at state+0x2a'),
    'getTxHeadroom': ('uint16_t', 'AppleBCMWLANSkywalkInterface::getTxHeadroom returns the word at state+0x28'),
    'getTxQueueDepth': ('uint32_t', 'AppleBCMWLANSkywalkInterface::getTxQueueDepth returns a dword'),
    'getRxQueueCapacity': ('uint32_t', 'AppleBCMWLANSkywalkInterface::getRxQueueCapacity returns a dword'),
    'setMacAddress': ('IOReturn', 'AppleBCMWLANSkywalkInterface::setMacAddress returns the result of AppleBCMWLANCore::setCurEtheraddr in eax'),
    'setWCL_LINK_STATE_UPDATE': ('IOReturn', '25G241 base impl IO80211InfraInterface::setWCL_LINK_STATE_UPDATE (0x236889c) returns kIOReturnBadArgument/null and 0 in eax otherwise'),
}
# get/set handlers of IO80211InfraProtocol: tail calls into the core's own virtuals (AppleBCMWLANInfraProtocol::getCHANNEL is
# `jmp [core vtable + 0xe98]`), so the type is the core handler's. IOReturn is assumed; a sibling in the Family,
# IO80211InfraInterface::setWCL_ADVISORTY_INFO, returns a bool in al. Not verified per handler.
PROTOCOL_HANDLER = re.compile(r'^(get|set)[A-Z0-9][A-Z0-9_]*$')
PTR = {
    'createPeerManager': 'IO80211PeerManager *', 'createPeer': 'IO80211Peer *', 'getScanManager': 'IO80211ScanManager *',
    'getController': 'IO80211Controller *', 'getP2PSkywalkPeerMgr': 'IO80211PeerManager *', 'findPeer': 'IO80211Peer *',
    'getWorkerMatchingDict': 'OSDictionary *', 'getSelfMacAddr': 'ether_addr *', 'getPacketPool': 'IOSkywalkPacketBufferPool *',
    'getMultiCastQueue': 'IOSkywalkPacketQueue *', 'getRxCompQueue': 'IOSkywalkRxCompletionQueue *',
    'getTxCompQueue': 'IOSkywalkTxCompletionQueue *', 'getTxSubQueue': 'IOSkywalkTxSubmissionQueue *',
    'getTxPacketPool': 'IOSkywalkPacketBufferPool *', 'getRxPacketPool': 'IOSkywalkPacketBufferPool *',
    'getRingMD': 'IOMemoryDescriptor *', 'classNameOverride': 'const char *', 'getBSDName': 'const char *',
    'getBSDNamePrefix': 'const char *', 'getBSDInterface': '__ifnet *', 'getBSDNamePrefix_': 'const char *',
    'findOrCreateFlowQueue': 'IO80211FlowQueue *', 'findOrCreateFlowQueueWithCache': 'IO80211FlowQueue *',
    'findExistingFlowQueue': 'IO80211FlowQueue *', 'getLinkLayerAddress': 'ether_addr *',
}
UINT = {'getMaxTransferUnit', 'getMinPacketSize', 'getHardwareAssists', 'getInterfaceFamily', 'getInterfaceSubFamily',
        'getInitialMedia', 'getFeatureFlags', 'getTxDataOffset', 'getBSDUnitNumber', 'getAssocState', 'getEventPipeSize',
        'getDataQueueDepth', 'linkState', 'debugFlags'}
VOID_PREFIX = ('log', 'record', 'update', 'notify', 'flush', 'destroy', 'set', 'vlog')
ENUMS = {'IO80211CountryCodeOp', 'IO80211FeatureCode', 'apple80211_wme_ac', 'IO80211LinkState'}
BUILTIN = {'void', 'bool', 'int', 'char', 'const', 'unsigned', 'long', 'short', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t',
           'struct', 'size_t', '__builtin_va_list', 'block_pointer'}
# defined by the SDK headers the generated header includes (no forward declaration needed / allowed to differ in tag)
SDK_TYPES = {'IOReportChannelList', 'OSObject', 'OSDictionary', 'OSString', 'OSSymbol', 'IOService', 'IOReturn', 'IOUserClient', 'IOMemoryDescriptor',
             'IOWorkLoop', 'IORegistryEntry', 'IOSkywalkInterface', 'OSMetaClass'}


def dump_path(d, fname):
    """first existing <dir>/<fname> over the ':'-separated dump directories (round3 and later rounds hold different classes)"""
    for one in d.split(os.pathsep):
        p = os.path.join(one, fname)
        if os.path.exists(p):
            return p
    return os.path.join(d.split(os.pathsep)[0], fname)


def source_meta(d):
    """the source.json of the dump set (in the directory or its parent), or None"""
    for one in d.split(os.pathsep):
        for cand in (os.path.join(one, 'source.json'), os.path.join(one, os.pardir, 'source.json')):
            if os.path.exists(cand):
                try:
                    return json.load(open(cand))
                except ValueError:
                    return None
    return None


def build_desc(d):
    """('macOS 15.8.1 24H32, Darwin 24.6.0', '24H32') from the dump's source.json, or (None, None).
    `system` is either sw_vers output or a one-line note from a Linux collection."""
    js = source_meta(d)
    if not js:
        return None, None
    sys_txt, darwin = js.get('system', ''), js.get('darwin', '')
    m = re.search(r'ProductVersion:\s*(\S+).*?BuildVersion:\s*(\S+)', sys_txt, re.S)
    if m:
        desc, tag = 'macOS %s %s' % (m.group(1), m.group(2)), m.group(2)
    else:
        desc = ' '.join(sys_txt.split()) or None
        mt = re.search(r'\b\d{2}[A-Z]\d+\w*\b', sys_txt)
        tag = mt.group(0) if mt else None
    if desc and darwin and 'Darwin' not in desc:
        desc += ', Darwin ' + darwin.split()[0]
    return desc, tag


def meta_size(d, cls):
    """instance size in bytes from the MetaClass constructor (`mov ecx, 0x...` = OSMetaClass size argument), or None"""
    path = dump_path(d, cls + '-MetaClass.asm.txt')
    if not os.path.exists(path):
        return None
    m = re.search(r'mov\s+ecx,\s+0x([0-9a-f]+)', open(path).read())
    return int(m.group(1), 16) if m else None


def vt(d, cls):
    out = {}
    path = dump_path(d, cls + '.vtable.txt')
    for line in open(path):
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[0].isdigit():
            out[int(p[0])] = p[2]
    return out


def class_vt(d, cls):
    """slot -> symbol of the class's own vtable (a class without a dump is read from its subclass, cut at its last slot)"""
    conf = CLASSES.get(cls, {})
    mine = vt(d, conf.get('source', cls))
    if 'cut' in conf:
        mine = {s: v for s, v in mine.items() if s <= conf['cut']}
        mine[conf['cut'] + 1] = '-'
    return mine


def demangle_all(syms):
    syms = list(syms)
    res = subprocess.run(['c++filt', '-n'], input='\n'.join(s[1:] if s.startswith('_') else s for s in syms),
                         capture_output=True, text=True, check=True).stdout.split('\n')
    return dict(zip(syms, res))


def split_params(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '(<[':
            depth += 1
        elif ch in ')>]':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def norm(t):
    t = t.replace('unsigned long long', 'uint64_t').replace('unsigned short', 'uint16_t')
    t = t.replace('unsigned char', 'uint8_t').replace('unsigned int', 'uint32_t')
    t = t.replace('__va_list_tag*', '__builtin_va_list').replace('__va_list_tag *', '__builtin_va_list')
    return t


def declarator(t, n):
    t = norm(t)
    if '(*)' in t:
        return t.replace('(*)', '(*a%d)' % n, 1)
    if t.endswith(' block_pointer'):
        m = re.match(r'(.*?) (\(.*\))$', t[:-len(' block_pointer')])
        return '%s (^a%d)%s' % (m.group(1), n, m.group(2))
    return '%s a%d' % (t, n)


def parse_method(dem):
    m = re.match(r'(.+?)::(~?[\w]+)\((.*)\)( const)?$', dem)
    if not m:
        return None
    owner, name, args, const = m.groups()
    return owner, name, split_params(args), bool(const)


def ret_for(name, params, const, cls=None):
    # Verified in round14: overloads have distinct return conventions.
    if name == 'init' and len(params) == 2 and 'ether_addr' in params[1]:
        return 'bool', '24H32 IO80211SkywalkInterface::init(provider,address) returns bool in eax'
    if name in ('setLinkState', 'setLinkStateInternal') and len(params) == 4:
        return 'bool', '24H32 InfraInterface::setLinkStateInternal returns success flag in eax'
    if name == 'setHardwareAddress':
        return 'IOReturn', '24H32 Skywalk setter returns MacAddressAgent status; Ethernet base returns Unsupported'
    if name in RET:
        return RET[name][0], RET[name][1]
    if cls == 'IO80211InfraProtocol' and PROTOCOL_HANDLER.match(name):
        return 'IOReturn', 'guess: tail call into the core handler (see PROTOCOL_HANDLER)'
    if name in PTR:
        return PTR[name], 'guess from name'
    if name in UINT:
        return 'uint32_t', 'guess from name'
    if re.match(r'(is|should|was|has)[A-Z]', name) or name.endswith('Enabled') or name.endswith('Enable') and not params:
        return 'bool', 'guess from name'
    if name.startswith(VOID_PREFIX) and name not in ('setLinkState', 'setScanningState'):
        return 'void', 'guess from name'
    return 'IOReturn', 'guess'


def analyse(d, cls):
    """-> dict with overrides, new virtuals (slot, ret, name, params, const, pure, why), parent_last, nested, types"""
    conf = CLASSES[cls]
    mine = class_vt(d, cls)
    last = max(s for s, v in mine.items() if v != '-')
    kids = [vt(d, c) for c in conf['children'] if os.path.exists(dump_path(d, c + '.vtable.txt'))]

    def sym_at(slot):
        s = mine[slot]
        if s != '___cxa_pure_virtual':
            return s, False
        for k in kids:
            if slot in k and k[slot] not in ('___cxa_pure_virtual', '-'):
                return k[slot], True
        return None, True

    dem = demangle_all({v for v in mine.values() if v.startswith('__Z')} |
                       {k[s] for k in kids for s in k if k[s].startswith('__Z')})
    owner_of = {}
    for s in range(2, last + 1):
        v = mine[s]
        if v.startswith('__Z'):
            pm = parse_method(dem[v])
            owner_of[s] = pm[0] if pm else None
        else:
            owner_of[s] = None
    # first slot of the trailing run that belongs to this class (or is pure): everything before it is inherited/overridden
    parent_last = conf.get('parent_last') or max(s for s in range(2, last + 1) if owner_of[s] not in (None, cls))
    new, over, pure_unnamed = [], [], []
    for s in range(2, last + 1):
        sym, pure = sym_at(s)
        if mine[s] == '___cxa_pure_virtual' and s <= parent_last:
            continue                          # inherited pure virtual: not declared here
        if sym is None:
            pure_unnamed.append(s)
            if s > parent_last:
                # unnamed pure virtual (no override in any derived dump): a non-pure placeholder keeps the layout slot-exact
                # and the class concrete (nothing calls this slot; pure in Apple's binary)
                new.append(dict(slot=s, name='_unnamedPure%d' % s, params=[], const=False, pure=False,
                                ret='void', why="___cxa_pure_virtual in Apple's binary, no symbol to name it"))
            continue
        pm = parse_method(dem[sym])
        if pm is None:
            continue
        owner, name, params, const = pm
        if not pure and owner != cls and not ('source' in conf and s > parent_last):
            continue
        if s in (2, 3, 9):
            continue                          # destructor pair, getMetaClass: OSDeclare*Structors
        rec = dict(slot=s, name=name, params=params, const=const, pure=pure)
        if s > parent_last:
            rec['ret'], rec['why'] = ret_for(name, params, const, cls)
            new.append(rec)
        else:
            over.append(rec)
    return dict(conf=conf, new=new, over=over, parent_last=parent_last, last=last, pure_unnamed=pure_unnamed)


def sdk_virtual_rets(sdk):
    """name -> set of return types over the SDK headers the generated headers build on (OSObject, IORegistryEntry, IOService,
    IOWorkLoop, IOSkywalk*)."""
    files = ['libkern/c++/OSObject.h', 'libkern/c++/OSMetaClass.h', 'IOKit/IORegistryEntry.h', 'IOKit/IOService.h',
             'IOKit/IOWorkLoop.h', 'IOKit/IOEventSource.h', 'IOKit/skywalk/IOSkywalkInterface.h']
    rx = re.compile(r'virtual\s+([\w:\s\*&<>]+?)\s+\*?\s*(\w+)\s*\(', re.S)
    out = {}
    for f in files:
        p = os.path.join(sdk, f)
        if not os.path.exists(p):
            continue
        text = re.sub(r'/\*.*?\*/', '', open(p, errors='replace').read(), flags=re.S)
        text = re.sub(r'//[^\n]*', '', text)
        for m in rx.finditer(text):
            ret = ' '.join(m.group(1).split())
            ptr = '*' if text[m.end(1):m.end()].count('*') else ''
            out.setdefault(m.group(2), set()).add((ret + ' ' + ptr).strip())
    return out


def generate(d, cls, sdk=None, known_rets=None):
    a = analyse(d, cls)
    conf = a['conf']
    sdkret = sdk_virtual_rets(sdk) if sdk else {}
    lines_over, lines_new, used = [], [], set()
    skipped = []
    for r in a['over']:
        plist = [declarator(t, i + 1) for i, t in enumerate(r['params'])]
        for t in r['params']:
            used.update(re.findall(r'[A-Za-z_]\w*', norm(t)))
        cands = sdkret.get(r['name'])
        ret = None
        if r['name'] in RET_OVERRIDE and RET_OVERRIDE[r['name']]:
            ret = RET_OVERRIDE[r['name']]
        elif cands and len(cands) == 1:
            ret = next(iter(cands))
        elif known_rets and known_rets.get(r['name']):
            ret = known_rets[r['name']]
        if ret is None:
            skipped.append(r)
            continue
        lines_over.append('    /* %d */ virtual %s %s(%s)%s override;' % (r['slot'], ret, r['name'], ', '.join(plist),
                                                                         ' const' if r['const'] else ''))
    for r in a['new']:
        plist = [declarator(t, i + 1) for i, t in enumerate(r['params'])]
        for t in r['params']:
            used.update(re.findall(r'[A-Za-z_]\w*', norm(t)))
        if r['name'].startswith('_RESERVED'):
            lines_new.append('    /* %d */ virtual void %s();' % (r['slot'], r['name']))
            continue
        for t in re.findall(r'[A-Za-z_]\w*', r['ret']):
            used.add(t)
        lines_new.append('    /* %d */ virtual %s %s(%s)%s%s;   // ret: %s' % (
            r['slot'], r['ret'], r['name'], ', '.join(plist), ' const' if r['const'] else '', ' = 0' if r['pure'] else '',
            r['why']))
    # nested types and plain forward declarations
    nested = sorted({m for t in used for m in []})
    return dict(analysis=a, over=lines_over, new=lines_new, skipped=skipped, used=used)


def ancestors(cls):
    out = set()
    while cls in CLASSES:
        cls = CLASSES[cls]['parent']
        out.add(cls)
    return out


def types_of(params_lists):
    return {w for p in params_lists for t in p for w in re.findall(r'[A-Za-z_][\w:]*', norm(t))}


def parent_rets(d, cls, sdk):
    """name -> return type as declared by the generated ancestors (so an override matches its base declaration)"""
    rets = {}
    p = CLASSES[cls]['parent']
    if p in CLASSES:
        rets.update(parent_rets(d, p, sdk))
        text = render(d, p, sdk)[0]
        for m in re.finditer(r'virtual ([\w:\s\*&]+?) \*?(\w+)\(', text):
            rets[m.group(2)] = m.group(1).strip()
    return rets


def render(d, cls, sdk=None, known_rets=None):
    if known_rets is None:
        known_rets = parent_rets(d, cls, sdk)
    g = generate(d, cls, sdk, known_rets)
    a = g['analysis']
    conf = a['conf']
    allp = [r['params'] for r in a['new'] + a['over']]
    toks = types_of(allp)
    for r in a['new']:
        toks.update(re.findall(r'[A-Za-z_][\w:]*', r['ret']))
    for sym, decl, why in STATICS.get(cls, ()):       # types named by the non-virtual declarations need forward declarations too
        toks.update(t for t in re.findall(r'[A-Za-z_][\w:]*', decl) if re.match(r'(IO|OS|CC)[A-Z0-9]\w*', t) and t != 'IOReturn')
    nested = {}
    plain = set()
    for t in toks:
        if t in BUILTIN or t in SDK_TYPES or t in ENUMS or t == cls or t in ancestors(cls):
            continue
        if '::' in t:
            o, n = t.split('::', 1)
            nested.setdefault(o, set()).add(n)
        else:
            plain.add(t)
    for sym, decl, why in STATICS.get(cls, ()):       # a generated class named only by a non-virtual declaration: forward-declare it
        for t in re.findall(r'[A-Za-z_]\w*', decl):
            if t in CLASSES and t != cls and t not in ancestors(cls) and re.match(r'(IO|OS|CC)[A-Z0-9]', t):
                plain.add(t)
    mine_nested = sorted(nested.get(cls, ()))
    macro = 'OSDeclareAbstractStructors' if any(r['pure'] for r in a['new']) else 'OSDeclareDefaultStructors'
    size = meta_size(d, cls) or conf['size']
    size_src = 'MetaClass constructor' if meta_size(d, cls) else conf.get('size_src', 'MetaClass constructor')
    desc, tag = build_desc(d)
    hdr = []
    hdr.append('''// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// GENERATED by tools/gen_io80211_header.py from %s (%s). Do not edit by hand.
//
// %s : %s as Apple's frameworks export it on this build: slot numbers count the two vtable header words
// (byte offset in the vtable symbol = slot * 8, from a vptr = slot * 8 - 0x10). Instance size 0x%x (%s).
// Checked with tools/check_io80211_header.py (clang's own vtable layout against the dump). Return types are not in mangled
// names: "ret: guess" means a guess from the method name. Valid for this build only.
#pragma once
#include %s
#include <IOKit/IOReturn.h>
#include <stdint.h>
''' % (d, desc or 'build unknown', cls, conf['parent'], size, size_src, conf['include']))
    fwd = sorted(t for t in plain if t not in SDK_TYPES)
    hdr.append('struct ether_addr;\nstruct __mbuf;')
    for t in fwd:
        if t in ('ether_addr', '__mbuf'):
            continue
        kw = 'class' if re.match(r'(IO|OS|CC)', t) else 'struct'
        hdr.append('%s %s;' % (kw, t))
    for o in sorted(nested):
        if o != cls and o not in CLASSES:
            hdr.append('// nested type of %s: %s' % (o, ', '.join(sorted(nested[o]))))
    for e in sorted(ENUMS & toks):
        if e in ('IO80211CountryCodeOp', 'IO80211FeatureCode') and cls != 'IO80211Controller':
            continue
        hdr.append('#ifndef IO80211_ENUM_%s\n#define IO80211_ENUM_%s\nenum %s : uint32_t {};\n#endif' % (e, e, e))
    hdr.append('')
    hdr.append('class %s : public %s {' % (cls, conf['parent']))
    hdr.append('    %s(%s)' % (macro, cls))
    hdr.append('')
    hdr.append('public:')
    for n in mine_nested:
        hdr.append('    struct %s;   // layout: see docs/IO80211-ABI-2.md (opaque here)' % n)
    if g['over']:
        hdr.append('    // overrides of inherited virtuals (declared so that super:: reaches Apple\'s code)')
        hdr.extend(g['over'])
    if g['skipped']:
        hdr.append('    // overridden here too, not redeclared (return type of the declaring class not verified):')
        for r in g['skipped']:
            hdr.append('    //   /* %d */ %s(%s)%s' % (r['slot'], r['name'], ', '.join(norm(t) for t in r['params']),
                                                          ' const' if r['const'] else ''))
    hdr.append('')
    hdr.append('    // new virtuals, slots %d..%d' % (a['parent_last'] + 1, a['last']))
    hdr.extend(g['new'])
    hdr.append('')
    for sym, decl, why in STATICS.get(cls, ()):
        if sym is None:
            hdr.append('    %s   // %s' % (decl, why))
            continue
        if sym not in open(dump_path(d, cls + '.methods.txt')).read():
            raise SystemExit('%s: %s is not in the method dump' % (cls, sym))
        hdr.append('    %s   // exported: %s; %s' % (decl, sym, why))
    if STATICS.get(cls):
        hdr.append('')
    parent_size = None
    if conf['parent'] in CLASSES:
        parent_size = meta_size(d, conf['parent']) or CLASSES[conf['parent']]['size']
    if parent_size != size:
        hdr.append('protected:')
        hdr.append('    uint8_t %sOpaque[0x%x - sizeof(%s)];   // ivars of Apple\'s class: layout not determined' % (
            cls[0].lower() + cls[1:], size, conf['parent']))
    hdr.append('};')
    hdr.append('static_assert(sizeof(%s) == 0x%x, "%s must be 0x%x bytes%s");' % (
        cls, size, cls, size, ' (build %s)' % tag if tag else ''))
    return '\n'.join(hdr) + '\n', g
