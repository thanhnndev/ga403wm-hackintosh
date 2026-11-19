# Codec matrix: regress-out37

Runs: matrix-regress-out37-20261119-0527, matrix-regress-out37-20261119-0528, matrix-regress-out37-20261119-0529

Pass = plays, decoded by VCNDec on the 890M VCN (its unified-log StartSession/close lines during the cell), and the frame-index strip check has no wrong (more than 6 frames off) or unreadable picture. Check columns: exact / 1-6 off (late draw) / wrong / unreadable. Safari cells in a background window (Safari does not render a covered window, so the page is hidden) are judged on plays (clock advances) + VCNDec + no unreadable picture: a stale drawImage there makes the index unreliable; QuickTime frames are checked outside the app with vt_check.

| codec | profile / depth | size | container | app | plays | decoder | frame check | dropped / decoded | VTDec % | client % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p60 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 11.2 | 17.2 | PASS |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 105 / 0 / 0 / 0 | 0 / 719 | 12.9 | 21.3 | PASS |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Chrome | yes | HW (VCNDec 10-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 10.8 | 21.9 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 63 / 0 / 0 / 0 | 0 / 360 | 8.4 | 10.7 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 63 / 0 / 0 / 0 | 0 / 360 | 8.8 | 12.2 | PASS |  |
| AV1 | main 8-bit | 2160p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 92 / 0 / 0 / 0 | 0 / 720 | 12.3 | 21.5 | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 108 / 0 / 0 / 0 | 0 / 721 | 11.8 | 23.1 | PASS |  |

7 pass, 0 fail, 0 without a clip (no encoder on this machine for it, e.g. 10-bit AV1 WebM).
