#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step130 (macOS, run as root): brightness, display-sleep power hold and system-wake paging work move into the
# source-built NMXGPU; the NMXBacklight kext goes away.
#
# NMXBacklight 0.4.0 called NMXGPU functions by fixed file address (checked against byte signatures of the NullMoth
# cave build) and patched NMXAMDFB's vtable. On the first source build (Step129, B9229F5F) the addresses no longer
# matched, so it went inert: no "backlight" handler -> plain AppleDisplay, no slider; and no paging wake -> WindowServer
# would hang after the next system sleep (Step109d). Rule since then: no kext may call into NMXGPU by address or patch
# its vtable; anything NMXGPU-specific lives in the NMXGPU source (fork nmx-source-port).
#
# This script:
#   1. installs the given NMXGPU.kext (Step130 build: "backlight handler published", NMXPowerKeep child, paging wake);
#   2. moves /Library/Extensions/NMXBacklight.kext into the backup (NMXPowerKeep is now inside NMXGPU);
#   3. drops NMXBacklight from the installed auxguard.sh / nmx-relink.sh kext lists;
#   4. unloads and moves away two NullMoth NVIDIA-display stopgap daemons that do nothing for the 890M path:
#      com.nullmoth.displaytrace (continuous log streams) and com.nullmoth.wsreset (one WindowServer restart per boot);
#   5. relinks the AuxKC with new auxguard probes and checks it (kccheck, strings, no NMXBacklight).
#
#   sudo scripts/macos-install-step130.sh ~/develop/projects/nmx-build-xkpi/out-9/NMXGPU.kext
#   sudo scripts/macos-install-step130.sh --undo   # everything back from the last Step130 backup, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
PATH=/usr/bin:/bin:/usr/sbin:/sbin
TS=$(date -u +%Y%m%dT%H%M%SZ)
L=/Library/Extensions
G=$L/NMXGPU.kext; GB=$G/Contents/MacOS/NMXGPU; NB=$L/NMXBacklight.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
SGF=/Library/StrixGraphicsFix; PROBES=$SGF/nmx-relink.probes
LD=/Library/LaunchDaemons; DAEMONS="com.nullmoth.displaytrace com.nullmoth.wsreset"
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step130-$TS.log") 2>&1

STEP130_STRINGS=(
    'backlight handler published'            # NMXAMDFB "backlight" child + getAppleSense LCD
    'NMXPowerKeep: %s %s while the system'   # display-sleep power hold (was NMXBacklight's NMXPowerKeep)
    'paging wake (%s, #%u)'                  # system-wake paging work (was NMXBacklight 0.4.0)
    'neither owned nor foreign'              # Step128 owned-by-default fix
    'nmxgpu-stage'                           # Step128 NVRAM stage marks
    'NullMoth ips:'                          # source build
)
has_strings() { for s in "${STEP130_STRINGS[@]}"; do grep -qaF "$s" "$1" || { echo "'$s' is not in $1"; return 1; }; done; }

# three 64-byte windows of NMXGPU's __TEXT,__text, each unique in the binary and in the collection (as Step125)
new_probes() {
    /usr/bin/perl -e '
        local $/; open(my $f, "<:raw", $ARGV[0]) or die; my $d = <$f>; open(my $k, "<:raw", $ARGV[1]) or die; my $kc = <$k>;
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

checks() {  # $1 = collection, $2 = "new" to require the Step130 NMXGPU
    "$SGF/kccheck" "$1" --probes "$PROBES" "$GB" $KX
    grep -qa '890M wait: NMXAMDFB registered' "$1" || { echo "NVRM nmx-wait (Step124) is not in $1"; return 1; }
    grep -qa 'EC queries that ask for a full wake' "$1" || { echo "StrixS0ix >= 0.1.12 is not in $1"; return 1; }
    if [[ ${2:-} == new ]]; then
        has_strings "$1" || return 1
        if grep -qa 'com.ga403wm.nmxbacklight' "$1"; then echo "NMXBacklight is still in $1"; return 1; fi
    fi
}

relink() {  # $1 = "new" for the Step130 checks
    local new=$KC.step130
    rm -f "$new"
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$new" -z
    new_probes "$GB" "$new" > "$PROBES.new"
    [[ $(wc -l < "$PROBES.new") -eq 3 ]] || { echo "could not make probes"; return 1; }
    mv -f "$PROBES.new" "$PROBES"
    echo "auxguard probes: $(tr '\n' ' ' < "$PROBES")"
    checks "$new" "${1:-}"
    mv -f "$new" "$KC"; sync
    # kernelmanagerd once replaced a fresh collection with its own list (Step100b): check again after it had time to act
    perl -e 'select(undef, undef, undef, 45)'
    checks "$KC" "${1:-}"
    echo "AuxKC relinked and checked"
}

restore_from() {  # $1 = backup dir
    local BK=$1
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
    if [[ -d $BK/NMXBacklight.kext ]]; then rm -rf "$NB"; ditto "$BK/NMXBacklight.kext" "$NB"; chown -R 0:0 "$NB"; chmod -R go-w "$NB"; fi
    cp -p "$BK/nmx-relink.probes" "$PROBES"
    cp -p "$BK/auxguard.sh" "$SGF/auxguard.sh"; cp -p "$BK/nmx-relink.sh" "$SGF/nmx-relink.sh"
    for d in $DAEMONS; do
        if [[ -f $BK/$d.plist ]]; then cp -p "$BK/$d.plist" "$LD/$d.plist"; launchctl bootstrap system "$LD/$d.plist" 2>/dev/null || true; fi
    done
}

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step130-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no backup"; exit 1; }
    restore_from "$BK"
    cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"; sync
    echo "Step130 undone from $BK (NMXGPU, NMXBacklight, probes, auxguard/nmx-relink, daemons, AuxKC); reboot to apply"
    exit 0
fi

B=${1:?path to the Step130 NMXGPU.kext}
has_strings "$B/Contents/MacOS/NMXGPU" || { echo "$B is not the Step130 build"; exit 1; }
if grep -qa '_proc_starttime' "$B/Contents/MacOS/NMXGPU"; then echo "$B imports proc_starttime (Step128 panic), refusing"; exit 1; fi
[[ $(/usr/libexec/PlistBuddy -c 'Print :IOKitPersonalities:NMXGPUAMD:NMXOwnsDisplay' "$B/Contents/Info.plist" 2>/dev/null) == true ]] \
    || { echo "$B Info.plist has no NMXOwnsDisplay=true (Step128 black panel), refusing"; exit 1; }

BK=/Library/NullMoth/step130-bk-$TS
mkdir -p "$BK"
ditto "$G" "$BK/NMXGPU.kext"
[[ -d $NB ]] && ditto "$NB" "$BK/NMXBacklight.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
cp -p "$PROBES" "$BK/nmx-relink.probes"
cp -p "$SGF/auxguard.sh" "$BK/auxguard.sh"; cp -p "$SGF/nmx-relink.sh" "$BK/nmx-relink.sh"
for d in $DAEMONS; do [[ -f $LD/$d.plist ]] && cp -p "$LD/$d.plist" "$BK/$d.plist"; done
echo "backup $BK (NMXGPU $(shasum -a 256 "$GB" | cut -c1-16))"

DONE=0
rollback() {
    [[ $DONE == 1 ]] && return
    echo "FAILED: restoring everything from $BK"
    rm -f "$KC.step130" "$PROBES.new"
    restore_from "$BK"
    cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC"; sync
    echo "restored; nothing changed"
}
trap rollback EXIT

rm -rf "$G"; ditto "$B" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
echo "NMXGPU $(shasum -a 256 "$GB" | cut -c1-16) installed"
rm -rf "$NB"; echo "NMXBacklight.kext removed (kept in $BK)"
# the installed copies: drop NMXBacklight from the kext lists (kccheck fails on a listed kext that is gone)
sed -i '' 's# \$L/NMXBacklight\.kext##' "$SGF/auxguard.sh"
sed -i '' "s#, 'NMXBacklight')#)#; /if name == 'NMXBacklight' and not Path(b).exists():/,+1d" "$SGF/nmx-relink.sh"
if grep -q NMXBacklight "$SGF/auxguard.sh" || grep -q "'NMXBacklight'" "$SGF/nmx-relink.sh"; then echo "auxguard/nmx-relink still list NMXBacklight"; exit 1; fi
bash -n "$SGF/auxguard.sh"; bash -n "$SGF/nmx-relink.sh"
for d in $DAEMONS; do
    launchctl bootout "system/$d" 2>/dev/null || true
    rm -f "$LD/$d.plist"
    echo "$d unloaded (plist kept in $BK)"
done
relink new
DONE=1
echo "Step130 installed: NMXGPU with brightness + NMXPowerKeep + paging wake, NMXBacklight gone, displaytrace/wsreset gone; reboot to load it"
