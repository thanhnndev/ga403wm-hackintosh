#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step125 (macOS, run as root): NMXGPU from one source build instead of the binary cave chain (nmxgpu-tech-debt).
# The live NMXGPU (5760efb6) is the Oct 22 source build 7efe25b8 plus ~25 byte patches (Step74..112c). The fork
# branch nmx-source-port (thanhnndev/nvidia-macos-driver) carries all of them as source: NMXAMDFB name + scan-out
# phys, rcu/idr/mutex guards, syncobj ETIME, zero flush, GTT snoop, TTM order 0, ibprobe, WC split, umap cache off,
# userptr pin + read-only retry, cs-trace, irqwatch + fence fallback, mm lifetime, flip/import API with DC on GPU VM,
# s2idle suspend + FADT re-read, plus what never made it into the caves: the lock-free nmx_thread_lock (e249183),
# the DISPLAY IPS trace ("NullMoth ips:", Step114b) and the NMXAMDFB boot hold ("nmxgpu-boot-hold").
# The kext is built outside this repo (PolyForm); pass its path. NVRM, NMXAccel and StrixS0ix are not touched.
#
# The cave checkers (scripts/nmx-*/--check-kc) do not apply to this build: it is checked by its own strings, and the
# auxguard probes (/Library/StrixGraphicsFix/nmx-relink.probes, kccheck) are rewritten to windows of the new binary.
#
#   sudo scripts/macos-install-step125.sh ~/develop/projects/nmx-build-xkpi/out-3/NMXGPU.kext
#   sudo scripts/macos-install-step125.sh --undo   # back to the NMXGPU + probes saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
GB=$G/Contents/MacOS/NMXGPU
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
SGF=/Library/StrixGraphicsFix
PROBES=$SGF/nmx-relink.probes
L=/Library/Extensions
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NMXBacklight.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step125-$TS.log") 2>&1

# strings only the source build has (one per ported area)
SRC_STRINGS=(
    'NullMoth ips:'                          # Step114b DISPLAY IPS trace
    'NMX irqwatch:'                          # Step97/100 irqwatch
    'NMX cs-trace:'                          # Step95 cs-trace
    'NMX flip: API up'                       # Step98/99 flip API
    'nmxgpu-boot-hold'                       # NMXAMDFB boot hold
    'FADT re-read before suspend'            # Step112c
    'unlock of unlocked mutex'               # Step78
    'NMXAMDFB'                               # Step74 class name
)

src_build() {  # $1 = binary or collection
    for s in "${SRC_STRINGS[@]}"; do
        grep -qaF "$s" "$1" || { echo "'$s' is not in $1"; return 1; }
    done
}

checks() {  # $1 = collection; $2 = src to require the source-built NMXGPU
    "$SGF/kccheck" "$1" --probes "$PROBES" "$GB" $KX
    grep -qa 'NVRMFB reports 0 connected displays on every nub' "$1" || { echo "headless NVRM is not in $1"; exit 1; }
    grep -qa '890M wait: NMXAMDFB registered' "$1" || { echo "NVRM nmx-wait (Step124) is not in $1"; exit 1; }
    grep -qa 'paging wake %s (setPowerState slot' "$1" || { echo "NMXBacklight 0.4.0 is not in $1"; exit 1; }
    grep -qa 'EC queries that ask for a full wake' "$1" || { echo "StrixS0ix 0.1.12 is not in $1"; exit 1; }
    if [[ ${2:-} == src ]]; then src_build "$1" || exit 1; fi
}

relink() {
    local new=$KC.step125
    rm -f "$new"
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$new" -z
    if [[ ${1:-} == src ]]; then
        new_probes "$GB" "$new" > "$PROBES.new"
        [[ $(wc -l < "$PROBES.new") -eq 3 ]] || { echo "could not make probes"; exit 1; }
        mv -f "$PROBES.new" "$PROBES"
        echo "auxguard probes: $(tr '\n' ' ' < "$PROBES")"
    fi
    checks "$new" "${1:-}"
    mv -f "$new" "$KC"; sync
    # kernelmanagerd once replaced a fresh collection with its own list (Step100b): check again after it had time to act
    /usr/bin/perl -e 'select(undef, undef, undef, 45)'
    checks "$KC" "${1:-}"
}

# auxguard probes: three 64-byte windows of NMXGPU's __TEXT,__text (near 10/50/90 %), each found exactly once in the
# binary and in the linked collection (windows with calls the linker fixes up do not match in the collection)
new_probes() {  # $1 = binary, $2 = collection
    /usr/bin/perl -e '
        local $/; open(my $f, "<:raw", $ARGV[0]) or die; my $d = <$f>; open(my $k, "<:raw", $ARGV[1]) or die; my $kc = <$k>;
        # thin x86_64 Mach-O: the __TEXT,__text section header
        my $ncmds = unpack("V", substr($d, 16, 4)); my $o = 32; my ($off, $sz);
        for (1 .. $ncmds) {
            my ($cmd, $len) = unpack("VV", substr($d, $o, 8));
            if ($cmd == 0x19) {
                my $nsect = unpack("V", substr($d, $o + 64, 4));
                for my $i (0 .. $nsect - 1) {
                    my $s = $o + 72 + 80 * $i;
                    my ($sn, $gn) = (unpack("Z16", substr($d, $s, 16)), unpack("Z16", substr($d, $s + 16, 16)));
                    if ($sn eq "__text" && $gn eq "__TEXT") { $sz = unpack("Q<", substr($d, $s + 40, 8)); $off = unpack("V", substr($d, $s + 48, 4)); }
                }
            }
            $o += $len;
        }
        die "no __text\n" unless $off;
        for my $frac (0.1, 0.5, 0.9) {
            my $p = ($off + int($sz * $frac)) & ~0xff;
            for (;; $p += 0x100) {
                die "no unique window\n" if $p + 0x40 > $off + $sz;
                my $w = substr($d, $p, 0x40); next if $w =~ /^(\x00|\xcc|\x90)+$/;
                my $n = () = $d =~ /\Q$w\E/g; next unless $n == 1;
                my $m = () = $kc =~ /\Q$w\E/g;
                if ($m == 1) { printf("0x%x 0x40\n", $p); last; }
            }
        }' "$1" "$2"
}

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step125-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
    cp -p "$BK/nmx-relink.probes" "$PROBES"
    echo "restored NMXGPU $(shasum -a 256 "$GB" | cut -c1-16) and the probes from $BK"
    relink
    echo "Step125 undone (cave build back); reboot to apply"
    exit 0
fi

B=${1:?path to the source-built NMXGPU.kext}
src_build "$B/Contents/MacOS/NMXGPU" || { echo "$B is not the Step125 source build"; exit 1; }
# Step128: 928335c2 panicked at 7 s on its weak proc_starttime import (kmutil binds a missing weak symbol to
# &gOSKextUnresolved), and 326858e hung the boot at ~12 s with nothing on disk. Only a build without that import and
# with the NVRAM stage marks (nmxgpu-stage / nmxgpu-alive) may go in, so a hang can be located from Windows.
if grep -qa '_proc_starttime' "$B/Contents/MacOS/NMXGPU"; then echo "$B imports proc_starttime (Step128 panic), refusing"; exit 1; fi
grep -qaF 'nmxgpu-stage' "$B/Contents/MacOS/NMXGPU" || { echo "$B has no NVRAM stage marks (Step128), refusing"; exit 1; }
BK=/Library/NullMoth/step125-bk-$TS
mkdir -p "$BK"
ditto "$G" "$BK/NMXGPU.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
cp -p "$PROBES" "$BK/nmx-relink.probes"
echo "backup $BK (NMXGPU $(shasum -a 256 "$GB" | cut -c1-16))"
# any failure from here on puts the cave build, its probes and the old collection back
DONE=0
rollback() {
    [[ $DONE == 1 ]] && return
    echo "FAILED: restoring NMXGPU, probes and AuxKC from $BK"
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
    cp -p "$BK/nmx-relink.probes" "$PROBES"
    rm -f "$KC.step125" "$PROBES.new"
    cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"; sync
    echo "restored; nothing changed"
}
trap rollback EXIT
rm -rf "$G"; ditto "$B" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
echo "NMXGPU $(shasum -a 256 "$GB" | cut -c1-16) installed"
relink src
DONE=1
echo "Step125 installed: source-built NMXGPU (AuxKC checked: kccheck + probes, NVRM Step124, StrixS0ix 0.1.12, NMXBacklight); reboot to load it"
