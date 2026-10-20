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
assert text.count(marker) == 1 and '# GA403 hybrid restore' not in text
restore = '''# GA403 hybrid restore: the old AuxKC must match these wrapper-owned kexts too.
HYBRID_BACKUP=BACKUP_VALUE
for p in Library/Extensions/NMXAccel.kext Library/Extensions/NVRMEdpBL.kext Library/NullMoth/gpu-userland; do
  rm -rf "/$p" || exit 1
  if [ -e "$HYBRID_BACKUP/$p" ]; then ditto "$HYBRID_BACKUP/$p" "/$p" || exit 1; fi
done
'''.replace('BACKUP_VALUE', shlex.quote(str(backup)))
job.write_text(text.replace(marker, restore + marker))
