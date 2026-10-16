# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Generate a slot-exact C++ header for IO80211Controller from the vtable dumps of one macOS build.

  python3 tools/gen_io80211_header.py abi/native-wifi/24H32/round3 > kexts/itlmt7925/io80211/IO80211Controller.h
  python3 tools/gen_io80211_header.py abi/native-wifi/24H32/round3 IO80211WorkQueue > kexts/itlmt7925/io80211/IO80211WorkQueue.h
  python3 tools/check_io80211_header.py abi/native-wifi/24H32/round3 [MacKernelSDK/Headers] [--class NAME | --all]
                                                                       # clang's own vtable layout must match the dump

Only names found in Apple's binary are used (symbol names of the vtable; pure-virtual slots take the name of the override in
AppleBCMWLANCore's vtable). Return types are NOT in a mangled name: they are filled from RET below (verified from a call site
or marked "guess") and only matter for methods a subclass overrides or calls.
"""
import re, subprocess, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import io80211_abi

D = sys.argv[1]
CLS = sys.argv[2] if len(sys.argv) > 2 else 'IO80211Controller'
if CLS != 'IO80211Controller':
    # interface-side classes: tools/io80211_abi.py (generic: parent from the SDK or from another generated header)
    # override return types come from the SDK header that declares the method (arg 3 or $MACKERNELSDK = .../Headers)
    sdk = sys.argv[3] if len(sys.argv) > 3 else os.environ.get('MACKERNELSDK')
    sys.stdout.write(io80211_abi.render(D, CLS, sdk)[0])
    sys.exit(0)
DESC, TAG = io80211_abi.build_desc(D)
FIRST, LAST = 396, 464          # new virtuals of IO80211Controller (slots counted with the two header words, as in the dump)

# return types: name -> (type, how known)
RET = {
    'createWorkQueue': ('bool', 'BCM override returns a success flag; base returns 0'),
    'getWorkQueue': ('IO80211WorkQueue *', 'result passed to IO80211CommandGate::allocWithParams'),
    'getIO80211CommandGate': ('IO80211CommandGate *', 'guess from name'),
    'getPrimarySkywalkInterface': ('IO80211SkywalkInterface *', 'guess from name'),
    'getLogger': ('CCLogStream *', 'result stored and used with CCLogStream::shouldLog'),
    'getFaultReporterFromDriver': ('IO80211FaultReporter *', 'BCM returns BusInterface::getIO80211FaultReporter() (state+0x28); '
                                   'start() retains it (slot 6) and panics if it is null (findAndAttachToFaultReporter)'),
    'attachInterface': ('bool', 'base returns setne al'),
    'CreatePostOffice': ('IO80211PostOffice *', 'result stored in ivars, null-checked'),
    'getPostOffice': ('IO80211PostOffice *', 'guess from name'),
}
ENUMS = {'IO80211CountryCodeOp', 'IO80211FeatureCode'}          # passed by value, 32 bit
KNOWN = {'OSObject', 'IOService', 'IOReturn', 'OSDictionary', 'IORegistryEntry'}


def vt(name):
    out = {}
    for line in open(os.path.join(D, name)):
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[0].isdigit():
            out[int(p[0])] = p[2]
    return out


def demangle(sym):
    r = subprocess.run(['c++filt', '-n', sym[1:]], capture_output=True, text=True).stdout.strip()
    return r


ctl, bcm = vt('IO80211Controller.vtable.txt'), vt('AppleBCMWLANCore.vtable.txt')
decls, used = [], set()
for slot in range(FIRST, LAST + 1):
    s = ctl[slot]
    pure = s == '___cxa_pure_virtual'
    dem = demangle(bcm[slot] if pure else s)
    m = re.match(r'(\w+)::(~?\w+)\((.*)\)( const)?$', dem)
    if not m:
        sys.exit('cannot parse slot %d: %s' % (slot, dem))
    cls, meth, args, const = m.groups()
    args = args.replace('unsigned long long', 'uint64_t').replace('unsigned long', 'unsigned long').replace('unsigned short', 'uint16_t')
    args = args.replace('unsigned char', 'uint8_t').replace('unsigned int', 'uint32_t').replace('__mbuf*', 'struct __mbuf*')
    plist, n = [], 0
    for a in ([x.strip() for x in args.split(',')] if args.strip() else []):
        n += 1
        plist.append('%s a%d' % (a, n))
        for t in re.findall(r'[A-Za-z_]\w*', a):
            used.add(t)
    ret, why = RET.get(meth, ('IOReturn', 'guess'))
    for t in re.findall(r'[A-Za-z_]\w*', ret):
        used.add(t)
    if meth.startswith('_RESERVED'):
        decls.append('    virtual void %s();' % meth)
        continue
    tail = ' = 0' if pure else ''
    decls.append('    /* %d */ virtual %s %s(%s)%s%s;%s' % (slot, ret, meth, ', '.join(plist), const or '', tail,
                                                           '   // ret: ' + why if why != 'guess' else '   // ret: guess'))

builtin = {'void', 'bool', 'int', 'char', 'const', 'unsigned', 'long', 'short', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t',
           'struct', '__mbuf', 'IOReturn', 'size_t', 'ether_addr'}
fwd = sorted(t for t in used if t not in builtin and t not in KNOWN and t not in ENUMS and t not in ('IO80211Controller',))
print('''// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// GENERATED by tools/gen_io80211_header.py from %s (%s). Do not edit by hand.
//
// IO80211Controller as Apple's IO80211Family exports it: slot-exact (checked by tools/check_io80211_header.sh against the
// vtable dump), instance size 0x128 (MetaClass constructor). Valid for this build only; other macOS builds need a new dump.
// Names come from Apple's symbols; no third-party sources were used. Return types are not in mangled names, see the notes.
#pragma once
#include <IOKit/network/IOEthernetController.h>
#include <stdint.h>

struct ether_addr;
struct __mbuf;
''' % (D, DESC or 'build unknown') + '\n'.join('class %s;' % t for t in fwd) + '''
enum IO80211CountryCodeOp : uint32_t {};
enum IO80211FeatureCode : uint32_t {};

class IO80211Controller : public IOEthernetController {
    OSDeclareAbstractStructors(IO80211Controller)

public:
    // Overrides IO80211Controller makes in the inherited range: declared so that super:: reaches Apple's code, not
    // IOEthernetController's. Same slots as the base declarations.
    bool init(OSDictionary *properties = nullptr) override;
    void free() override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    IOWorkLoop *getWorkLoop() const override;
    bool createWorkLoop() override;
    IOReturn getHardwareAddress(IOEthernetAddress *addr) override;
    IOReturn setPromiscuousMode(bool active) override;
    IOReturn setMulticastMode(bool active) override;

    // New virtuals, slots 396..464 (first number = slot incl. the two header words; byte offset in the vtable symbol = slot * 8,
    // from a vptr = slot * 8 - 0x10).
''' + '\n'.join(decls) + '''

protected:
    uint8_t io80211Opaque[0x10];   // 0x128 (MetaClass constructor) - 0x118 (sizeof IOEthernetController in the SDK); Apple's ivars pointer is at +0x120
};
static_assert(sizeof(IO80211Controller) == 0x128, "IO80211Controller must be 0x128 bytes%s");
''' % (' (build %s)' % TAG if TAG else ''))
