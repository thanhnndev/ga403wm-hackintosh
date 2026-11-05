#!/bin/zsh
# SimpleHDA (AppleHDA on Tahoe) check and undo. See docs/AUDIO-TAHOE.md.
#
#   zsh scripts/macos-simplehda.sh check    # after the reboot: what loaded, which audio devices exist
#   zsh scripts/macos-simplehda.sh idle     # HDEF interrupts at idle (asks for the admin password, 10 s)
#   zsh scripts/macos-simplehda.sh undo     # disable the Kernel>Add entry, remove the HAL plug-in (reboot after)
#
# The ESP must be mounted at /Volumes/ESP and user-writable.
set -u
ESP=/Volumes/ESP/EFI/OC
cmd=${1:-check}

case $cmd in
check)
    print "== kexts"
    kextstat 2>/dev/null | awk '{print $6, $7}' | grep -iE 'simplehda|applehda|applealc|lilu|strixamp|hdafamily'
    print "== HDA controller / codec"
    ioreg -r -c AppleHDAController -w0 -d1 2>/dev/null | head -2 || true
    ioreg -r -c AppleHDACodecGeneric -w0 -d1 2>/dev/null | head -2 || true
    ioreg -rc IOHDACodecDevice -w0 -l 2>/dev/null | grep -E '"(IOHDACodecVendorID|IOHDACodecRevisionID)"' | head -2
    ioreg -rc AppleHDAEngineOutput -w0 -l 2>/dev/null | grep -E '"IOAudioEngineState"' | head -2
    print "== CoreAudio devices"
    system_profiler SPAudioDataType 2>/dev/null | grep -E '^        [^ ].*:$|Transport|Default (In|Out)put'
    print "== rogaudiod status"
    plutil -p ~/Library/Application\ Support/RogAudio/status.plist 2>/dev/null | grep -E 'Active|updated'
    print "== HAL plug-in"
    ls -d /Library/Audio/Plug-Ins/SimpleHDA/AppleHDAHALPlugIn.bundle 2>/dev/null
    print "== boot-args"
    nvram boot-args | tr ' ' '\n' | grep -E 'shda|alc|keepsyms'
    print "== SimpleHDA log (this boot)"
    log show --last boot --predicate 'sender == "SimpleHDA" OR eventMessage CONTAINS[c] "SimpleHDA" OR eventMessage CONTAINS "AppleHDA"' \
        --style compact 2>/dev/null | tail -15
    ;;
idle)
    osascript -e 'do shell script "/usr/bin/powermetrics -n 1 -i 10000 --samplers interrupts 2>/dev/null | grep -iE \"HDEF|interrupts/sec|HDA\" | head -20" with administrator privileges with prompt "powermetrics: HDEF interrupts at idle"'
    ;;
undo)
    [[ -f $ESP/config.plist ]] || { print -u2 "ESP not mounted at /Volumes/ESP"; exit 1; }
    cp -p $ESP/config.plist $ESP/config.plist.pre-simplehda-undo-$(date +%Y%m%d-%H%M%S)
    python3 -I - $ESP/config.plist <<'EOF'
import plistlib, sys
p = sys.argv[1]; c = plistlib.load(open(p, 'rb'))
for k in c['Kernel']['Add']:
    if k['BundlePath'] == 'SimpleHDA.kext': k['Enabled'] = False; print('SimpleHDA entry disabled')
plistlib.dump(c, open(p, 'wb'))
EOF
    osascript -e 'do shell script "rm -rf /Library/Audio/Plug-Ins/SimpleHDA; pkgutil --forget cn.laobamac.SimpleHDA.HAL || true" with administrator privileges with prompt "Remove the SimpleHDA HAL plug-in"'
    print "Reboot to finish. Quick undo without editing the config: add -shdaoff to boot-args."
    ;;
*) print -u2 "usage: $0 check|idle|undo"; exit 2 ;;
esac
