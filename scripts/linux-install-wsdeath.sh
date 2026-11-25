#!/bin/bash
# Step81: after login WindowServer died again (boot 44707127, ~20 s into the session) and the log on disk stops 6 s before
# the death, so the reason was lost. Also nullmoth-wsreset (the NVIDIA flicker stopgap) kills the first WindowServer on
# every boot (wsreset.log: 03:28:06), which on the 890M only tears down live GPU contexts for nothing.
#
#   pkexec scripts/linux-install-wsdeath.sh
#
#  - /Library/NullMoth/no-wsreset: nullmoth-wsreset exits without restarting WindowServer.
#  - com.nullmoth.wsdeath: on WindowServer death, writes the last 3 min of WindowServer/kernel/loginwindow log to
#    /Library/NullMoth/wsdeath/<time>-ws<pid>.log and syncs, so it survives a power-off right after the console shows.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

N="$MNT/Library/NullMoth"
date -u >"$N/no-wsreset"
install -o 0 -g 0 -m 755 "$HERE/wsdeath/nullmoth-wsdeath.sh" "$N/nullmoth-wsdeath.sh"
install -o 0 -g 0 -m 644 "$HERE/wsdeath/com.nullmoth.wsdeath.plist" "$MNT/Library/LaunchDaemons/com.nullmoth.wsdeath.plist"
python3 -I - "$MNT/private/var/db/com.apple.xpc.launchd/disabled.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
if d.pop('com.nullmoth.wsdeath', None) is not None:
    plistlib.dump(d, open(p, 'wb')); print('wsdeath: enabled again in launchd')
PY
ls -l "$N/no-wsreset" "$N/nullmoth-wsdeath.sh" "$MNT/Library/LaunchDaemons/com.nullmoth.wsdeath.plist"
sync
umount "$MNT"
echo "installed: wsreset off, wsdeath recorder on (next boot)"
