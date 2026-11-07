# Windows-side tools for the macOS Data volume (Step128)

Used from Windows when macOS does not boot. They read the APFS container on `\.\Harddisk0Partition3` with
`dissect.apfs` (read-only), and write only file data inside existing extents (`auxkc_patch.py`, `apfs_restore.py`):
sizes, mtimes and metadata stay unchanged, because APFS checksums metadata objects and not file data. Run them from an
elevated PowerShell (`run_restore.ps1 -Mode dry|apply`). Always do a dry run first: raw block, block read through APFS,
and pulled copy must be equal.

- `apfs_pull.py`: read-only reader + `ls`/`copy` helpers; the other scripts `exec` its header.
- `fh.py`: tracev3 -> "uptime pid strings" per firehose entry.
- `macho.py`: minimal Mach-O reader.
- `auxkc_patch.py`: the Step128 two-byte patch of the AuxKC (je -> jmp).
- `probes_calc.py`: auxguard probes (three 64-byte `__text` windows, each once in the binary and once in the AuxKC).
- `apfs_restore.py`, `run_restore.ps1`: put the 14:29 good boot set back in place (see docs/890M-TRACE.md, Step128
  restore). The source files are expected in `apfs_out13/` next to the script (pulled from the step125/126 backups).
- `esp_restore.ps1`: ESP `config.plist` back to the good-boot copy, current one kept as `.bk-restore-*`.

Paths in the scripts are those of the 2026-11-07 session; adjust before reuse.
