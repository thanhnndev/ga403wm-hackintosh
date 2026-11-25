# Codec matrix: after-out33

Runs: apple-after-out33-20261118-0913, apple-after-out33-20261118-0921, apple-after-out33-20261118-0925, apple-after-out33-20261118-0926, matrix-after-out33-20261118-0905

Pass = plays, decoded by VCNDec on the 890M VCN (its unified-log StartSession/close lines during the cell), and the frame-index strip check has no wrong (more than 6 frames off) or unreadable picture. Check columns: exact / 1-6 off (late draw) / wrong / unreadable. Safari cells in a background window (Safari does not render a covered window, so the page is hidden) are judged on plays (clock advances) + VCNDec + no unreadable picture: a stale drawImage there makes the index unreliable; QuickTime frames are checked outside the app with vt_check.

| codec | profile / depth | size | container | app | plays | decoder | frame check | dropped / decoded | VTDec % | client % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 2.7 | 10.5 | PASS |  |
| H.264 | High 8-bit | 1080p30 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 0 / 1 / 1 / 0 | 132 / 385 | 0 | 139.2 | PASS | background window |
| H.264 | High 8-bit | 1080p30 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 0.3 | 0 | PASS |  |
| H.264 | High 8-bit | 1080p60 | fMP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 5.5 | 5.1 | PASS |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 5.8 | 15.7 | PASS |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Safari | yes | HW (VCNDec 8-bit) | 4 / 5 / 0 / 0 | 154 / 903 | 0 | 12.8 | PASS | background window |
| H.264 | High 8-bit | 1080p60 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 5.7 | 16.8 | PASS |  |
| H.264 | High 8-bit | 1080p60 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 7 / 0 / 0 / 0 | 153 / 885 | 0 | 7 | PASS | background window |
| H.264 | High 8-bit | 1080p60 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 5.8 | 5.1 | PASS |  |
| H.264 | High 8-bit | 2160p30 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 3.6 | 13.1 | PASS |  |
| H.264 | High 8-bit | 2160p30 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 5 / 1 / 1 / 0 | 104 / 438 | 0 | 17.7 | PASS | background window |
| H.264 | High 8-bit | 2160p30 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 4.5 | 4.3 | PASS |  |
| HEVC | Main 8-bit | 1080p60 | fMP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 5.6 | 5.2 | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 6.1 | 16.1 | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Safari | yes | HW (VCNDec 8-bit) | 8 / 1 / 0 / 0 | 196 / 907 | 14.3 | 12 | PASS | background window |
| HEVC | Main 8-bit | 1080p60 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 6.1 | 16.8 | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 8 / 0 / 0 / 0 | 149 / 885 | 5.6 | 8.9 | PASS | background window |
| HEVC | Main 8-bit | 1080p60 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 6 | 5.2 | PASS |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 109 / 0 / 0 / 0 | 0 / 720 | 7.2 | 19.8 | PASS |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 5 / 0 / 0 / 0 | 107 / 668 | 20.9 | 14.1 | PASS | background window |
| HEVC | Main 8-bit | 2160p60 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 7.5 | 5.3 | PASS |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Chrome | yes | HW (VCNDec 10-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 5.9 | 22.3 | PASS |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Safari | yes | HW (VCNDec 10-bit) | 1 / 0 / 1 / 0 | 59 / 368 | 8.8 | 35.5 | PASS | background window |
| HEVC | Main10 10-bit | 1080p60 | MP4 | QuickTime | yes | HW (VCNDec 10-bit) | n/a (vt_check) | - / - | 5.7 | 4.9 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 61 / 1 / 0 / 0 | 5 / 360 | 3.1 | 10.4 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Safari | yes | HW (VCNDec 8-bit) | 2 / 1 / 0 / 0 | 80 / 245 | 5.7 | 46 | PASS | background window |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 2.6 | 9.1 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 4 / 3 / 0 / 0 | 192 / 456 | 4 | 5.9 | PASS | background window |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 5.5 | 16.3 | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 9 / 0 / 0 / 0 | 0 / 551 | 0 | 9.1 | PASS | background window |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 5.7 | 16.2 | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 9 / 0 / 0 / 0 | 0 / 494 | 0 | 8.9 | PASS | background window |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 108 / 0 / 0 / 0 | 0 / 718 | 6.5 | 18.9 | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 3 / 4 / 0 / 0 | 194 / 469 | 0 | 15 | PASS | background window |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 94 / 0 / 0 / 0 | 0 / 720 | 6.8 | 18.7 | PASS | MSE appendBuffer: Failed to execute 'appendBuffer' on 'SourceBuffer': The SourceBuffer is full, and cannot fre |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 3 / 0 / 0 | 45 / 437 | 0 | 22.5 | PASS | background window |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Chrome | yes | HW (VCNDec 10-bit) | 128 / 0 / 0 / 0 | 0 / 720 | 24.3 | 14 | PASS |  |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Safari | yes | HW (VCNDec 10-bit) | 3 / 2 / 0 / 0 | 554 / 910 | 0 | 8.6 | PASS | background window |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Chrome | yes | HW (VCNDec 10-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 4.9 | 19.4 | PASS |  |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Safari | yes | HW (VCNDec 10-bit) | 1 / 4 / 0 / 0 | 277 / 582 | 0.1 | 11.3 | PASS | background window |
| AV1 | main 10-bit | ?p? | WebM | Chrome | no clip | - | - | - / - | - | - | no clip |  |
| AV1 | main 10-bit | 1080p30 | MP4 | Chrome | yes | HW (VCNDec 10-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 3 | 13.4 | PASS |  |
| AV1 | main 10-bit | 1080p30 | MP4 | Safari | yes | HW (VCNDec 10-bit) | 6 / 0 / 0 / 0 | 74 / 439 | 2.6 | 3.6 | PASS | background window |
| AV1 | main 10-bit | 1080p30 | MP4 | QuickTime | yes | HW (VCNDec 10-bit) | n/a (vt_check) | - / - | 4.8 | 3.7 | PASS |  |
| AV1 | main 8-bit | 1080p30 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 65 / 0 / 0 / 0 | 0 / 360 | 2.9 | 10.2 | PASS |  |
| AV1 | main 8-bit | 1080p30 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 4 / 1 / 1 / 0 | 86 / 467 | 3.3 | 4.1 | PASS | background window |
| AV1 | main 8-bit | 1080p30 | MP4 | QuickTime | yes | HW (VCNDec 8-bit) | n/a (vt_check) | - / - | 4.4 | 3.5 | PASS |  |
| AV1 | main 8-bit | 1080p30 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 3 | 11.1 | PASS |  |
| AV1 | main 8-bit | 1080p30 | WebM | Safari | yes | HW (VCNDec 8-bit) | 4 / 2 / 0 / 0 | 177 / 431 | 8.4 | 8.2 | PASS | background window |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 2.9 | 11 | PASS |  |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 4 / 2 / 0 / 0 | 57 / 183 | 4.8 | 6.5 | PASS | background window |
| AV1 | main 8-bit | 1080p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 127 / 0 / 0 / 0 | 0 / 719 | 6.1 | 19.3 | PASS |  |
| AV1 | main 8-bit | 1080p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 1 / 0 / 0 / 0 | 263 / 463 | 18.5 | 29.1 | PASS | background window |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 6.1 | 19.1 | PASS |  |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 2 / 4 / 0 / 0 | 433 / 886 | 7.2 | 8.8 | PASS | background window |
| AV1 | main 8-bit | 2160p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 113 / 0 / 0 / 0 | 4 / 719 | 14.8 | 20.4 | PASS |  |
| AV1 | main 8-bit | 2160p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 3 / 2 / 0 / 0 | 228 / 572 | 11.3 | 10.8 | PASS | background window |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 106 / 0 / 0 / 0 | 0 / 720 | 14.7 | 22.4 | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 1 / 0 / 0 | 313 / 898 | 9.4 | 13.9 | PASS | background window |

58 pass, 0 fail, 1 without a clip (no encoder on this machine for it, e.g. 10-bit AV1 WebM).
