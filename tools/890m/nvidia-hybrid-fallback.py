#!/usr/bin/env python3
"""Extend the upstream one-shot fallback to restore the hybrid wrapper's state."""
import shlex
import sys
from pathlib import Path

backup = Path(sys.argv[1])
job = Path('/Library/NullMoth/lastgood.sh')
assert backup.parent == Path('/Library/NullMoth') and backup.name.startswith('hybrid-2.4.2-')
assert (backup / 'Library/Extensions/NMXAccel.kext/Contents/Info.plist').is_file()
text = job.read_text()
marker = 'nvram -d $V:nullmoth-nv-starts 2>/dev/null\n'
assert text.count(marker) == 1
paths = 'Library/Extensions/NMXGPU.kext Library/Extensions/NMXAccel.kext Library/Extensions/NVRMEdpBL.kext Library/NullMoth/gpu-userland'
assert (backup / 'Library/Extensions/NMXGPU.kext/Contents/Info.plist').is_file()
restore = '''# GA403 hybrid restore: the old AuxKC must match these wrapper-owned kexts too.
HYBRID_BACKUP=BACKUP_VALUE
for p in PATHS_VALUE; do
  rm -rf "/$p" || exit 1
  if [ -e "$HYBRID_BACKUP/$p" ]; then ditto "$HYBRID_BACKUP/$p" "/$p" || exit 1; fi
done
'''.replace('BACKUP_VALUE', shlex.quote(str(backup))).replace('PATHS_VALUE', paths)
if '# GA403 hybrid restore' in text:
    # Upgrade the Step51 job after adding its unchanged GPU image to that backup.
    old = 'for p in Library/Extensions/NMXAccel.kext Library/Extensions/NVRMEdpBL.kext Library/NullMoth/gpu-userland; do'
    new = 'for p in ' + paths + '; do'
    if new not in text:
        assert text.count(old) == 1
        job.write_text(text.replace(old, new))
else:
    job.write_text(text.replace(marker, restore + marker))
