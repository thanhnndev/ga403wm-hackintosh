# Codec matrix: before-out30

Runs: apple-before-out30-20261118-0445, apple-before-out30-20261118-0511, apple-before-out30-20261118-0517, apple-before-out30-20261118-0534, matrix-before-out30-20261118-0457, matrix-before-out30-20261118-0505, matrix-before-out30-20261118-0507, matrix-before-out30-20261118-0510

Pass = plays, decoded by VCNDec on the 890M VCN (its unified-log StartSession/close lines during the cell), and the frame-index strip check has no wrong (more than 6 frames off) or unreadable picture. Check columns: exact / 1-6 off (late draw) / wrong / unreadable. Safari cells in a background window (Safari does not render a covered window, so the page is hidden) are judged on plays (clock advances) + VCNDec + no unreadable picture: a stale drawImage there makes the index unreliable; QuickTime frames are checked outside the app with vt_check.

| codec | profile / depth | size | container | app | plays | decoder | frame check | dropped / decoded | VTDec % | client % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | Chrome | yes | **SW** (Chrome FFmpeg) | 61 / 0 / 0 / 0 | 4 / 360 | 14 | 6.8 | **FAIL** |  |
| H.264 | High 8-bit | 1080p30 | MP4 | Safari | yes | **SW** (WebKit) | 0 / 1 / 1 / 0 | 120 / 358 | 1.7 | 154.9 | **FAIL** | background window |
| H.264 | High 8-bit | 1080p30 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 35 | 4 | **FAIL** |  |
| H.264 | High 8-bit | 1080p60 | fMP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 65.1 | 5.3 | **FAIL** |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Chrome | yes | **SW** (Chrome FFmpeg) | 123 / 0 / 0 / 0 | 0 / 721 | 0 | 9.9 | **FAIL** |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Safari | yes | **SW** (WebKit) | 1 / 1 / 0 / 0 | 0 / 853 | 4.1 | 145.8 | **FAIL** | background window |
| H.264 | High 8-bit | 1080p60 | MP4 | Chrome | yes | **SW** (Chrome FFmpeg) | 123 / 0 / 0 / 0 | 0 / 720 | 0 | 9.7 | **FAIL** |  |
| H.264 | High 8-bit | 1080p60 | MP4 | Safari | yes | **SW** (WebKit) | 1 / 0 / 1 / 0 | 63 / 395 | 4.2 | 79.6 | **FAIL** | background window |
| H.264 | High 8-bit | 1080p60 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 65.6 | 6.1 | **FAIL** |  |
| H.264 | High 8-bit | 2160p30 | MP4 | Chrome | yes | **SW** (Chrome FFmpeg) | 62 / 0 / 0 / 0 | 0 / 360 | 0 | 7.9 | **FAIL** |  |
| H.264 | High 8-bit | 2160p30 | MP4 | Safari | yes | **SW** (WebKit) | 0 / 1 / 0 / 0 | 65 / 233 | 4.8 | 159.6 | **FAIL** | background window |
| H.264 | High 8-bit | 2160p30 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 118.7 | 4.5 | **FAIL** |  |
| HEVC | Main 8-bit | 1080p60 | fMP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 37.4 | 4.4 | **FAIL** |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Chrome | yes | **SW** (VideoToolbox, Apple software) | 127 / 0 / 0 / 0 | 0 / 720 | 47.4 | 16.9 | **FAIL** |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Safari | yes | **SW** (VideoToolbox, Apple software) | 2 / 0 / 0 / 0 | 249 / 876 | 27.3 | 101.9 | **FAIL** | background window |
| HEVC | Main 8-bit | 1080p60 | MP4 | Chrome | yes | **SW** (VideoToolbox, Apple software) | 120 / 0 / 0 / 0 | 0 / 720 | 47.4 | 17.2 | **FAIL** |  |
| HEVC | Main 8-bit | 1080p60 | MP4 | Safari | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 1 / 0 | 215 / 728 | 29.3 | 203.2 | **FAIL** | background window |
| HEVC | Main 8-bit | 1080p60 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 38 | 4.5 | **FAIL** |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | Chrome | yes | **SW** (VideoToolbox, Apple software) | 105 / 0 / 0 / 0 | 6 / 720 | 160.6 | 22.5 | **FAIL** |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | Safari | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 0 / 0 | 69 / 518 | 126.4 | 97.2 | **FAIL** | background window |
| HEVC | Main 8-bit | 2160p60 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 121.2 | 5.6 | **FAIL** |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Chrome | yes | **SW** (VideoToolbox, Apple software) | 125 / 0 / 0 / 0 | 9 / 720 | 49.4 | 22.1 | **FAIL** |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Safari | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 1 / 0 | 227 / 842 | 57.2 | 166.9 | **FAIL** | background window |
| HEVC | Main10 10-bit | 1080p60 | MP4 | QuickTime | yes | **SW** (VideoToolbox, Apple software) | n/a (vt_check) | - / - | 45.4 | 4.9 | **FAIL** |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 3.1 | 9.9 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Safari | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 1 / 1 / 0 / 0 | 121 / 444 | 12 | 180.8 | **FAIL** | background window |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 63 / 0 / 0 / 0 | 0 / 360 | 2.8 | 10 | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Safari | yes | **SW** (WebKit; VCNDec failed) | 2 / 0 / 0 / 0 | 0 / 427 | 1.9 | 243.5 | **FAIL** | background window |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 125 / 0 / 0 / 0 | 0 / 720 | 4.3 | 13.9 | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Safari | yes | **SW** (WebKit; VCNDec failed) | 1 / 6 / 0 / 0 | 0 / 403 | 0.9 | 139.4 | **FAIL** | background window |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 4.5 | 13.6 | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Safari | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 6 / 1 / 0 / 0 | 6 / 561 | 14.4 | 122.2 | **FAIL** | background window |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 120 / 0 / 0 / 0 | 0 / 720 | 6 | 17.1 | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Safari | yes | **SW** (WebKit; VCNDec failed) | 0 / 0 / 0 / 0 | 0 / 0 | 0 | 251.8 | **FAIL** | decoding in software: WebKit GPU 251.8 % + VTDecoderXPCService 0 % CPU (page hidden) |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 119 / 0 / 0 / 0 | 0 / 719 | 5.6 | 16.8 | PASS | MSE appendBuffer: Failed to execute 'appendBuffer' on 'SourceBuffer': The SourceBuffer is full, and cannot fre |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Safari | yes | **SW** (WebKit; VCNDec failed) | 0 / 0 / 0 / 0 | 0 / 0 | 0 | 515.8 | **FAIL** | decoding in software: WebKit GPU 515.8 % + VTDecoderXPCService 0 % CPU (page hidden) |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Chrome | yes | **SW** (Chrome Vpx; VCNDec refused) | 125 / 0 / 0 / 0 | 0 / 720 | 0 | 16.1 | **FAIL** | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Safari | yes | **SW** (WebKit; VCNDec refused) | 2 / 0 / 0 / 0 | 255 / 815 | 0.8 | 286.7 | **FAIL** | background window |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Chrome | yes | **SW** (Chrome Vpx; VCNDec refused) | 126 / 0 / 0 / 0 | 0 / 720 | 0 | 16.2 | **FAIL** | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Safari | yes | **SW** (VideoToolbox, Apple software; VCNDec refused) | 0 / 2 / 0 / 0 | 0 / 925 | 9.9 | 306.6 | **FAIL** | background window |
| AV1 | main 10-bit | ?p? | WebM | Chrome | no clip | - | - | - / - | - | - | no clip |  |
| AV1 | main 10-bit | 1080p30 | MP4 | Chrome | yes | **SW** (Chrome Dav1d; VCNDec refused) | 38 / 0 / 0 / 0 | 3 / 308 | 0 | 7.3 | **FAIL** | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
| AV1 | main 10-bit | 1080p30 | MP4 | Safari | no | - | 0 / 0 / 0 / 0 | 0 / 0 | - | - | **FAIL** | background window; Media failed to decode |
| AV1 | main 10-bit | 1080p30 | MP4 | QuickTime | no | - | n/a (vt_check) | - / - | 0.1 | 2.1 | **FAIL** |  |
| AV1 | main 8-bit | 1080p30 | MP4 | Chrome | yes | HW (VCNDec 8-bit) | 63 / 0 / 0 / 0 | 0 / 360 | 4.5 | 15 | PASS |  |
| AV1 | main 8-bit | 1080p30 | MP4 | Safari | yes | HW (VCNDec 8-bit) | 0 / 0 / 2 / 0 | 67 / 411 | 36.6 | 102.3 | PASS | background window |
| AV1 | main 8-bit | 1080p30 | MP4 | QuickTime | yes | **SW** (QuickTime; VCNDec failed) | n/a (vt_check) | - / - | 3.7 | 3.1 | **FAIL** |  |
| AV1 | main 8-bit | 1080p30 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 3.1 | 11.8 | PASS |  |
| AV1 | main 8-bit | 1080p30 | WebM | Safari | yes | HW (VCNDec 8-bit) | 2 / 0 / 0 / 0 | 246 / 425 | 10.5 | 198.7 | PASS | background window |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 64 / 0 / 0 / 0 | 0 / 360 | 2.6 | 10.1 | PASS |  |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 1 / 1 / 0 / 0 | 215 / 420 | 11.2 | 101.1 | PASS | background window |
| AV1 | main 8-bit | 1080p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 127 / 0 / 0 / 0 | 0 / 720 | 4.5 | 15 | PASS |  |
| AV1 | main 8-bit | 1080p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 0 / 0 / 0 | 0 / 0 | 10.8 | 131 | PASS | decoding in software: WebKit GPU 131 % + VTDecoderXPCService 10.8 % CPU (page hidden) |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 126 / 0 / 0 / 0 | 0 / 720 | 4.5 | 15.5 | PASS |  |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 0 / 0 / 2 | 271 / 491 | 0 | 0 | **FAIL** | background window; Media failed to decode |
| AV1 | main 8-bit | 2160p60 | WebM | Chrome | yes | HW (VCNDec 8-bit) | 106 / 0 / 0 / 0 | 0 / 720 | 9.4 | 28.6 | PASS |  |
| AV1 | main 8-bit | 2160p60 | WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 2 / 0 / 0 | 254 / 838 | 13.1 | 140.7 | PASS | background window |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Chrome | yes | HW (VCNDec 8-bit) | 105 / 0 / 0 / 0 | 0 / 720 | 9.6 | 28.4 | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Safari | yes | HW (VCNDec 8-bit) | 0 / 1 / 0 / 0 | 186 / 762 | 15.4 | 78 | PASS | background window |

19 pass, 39 fail, 1 without a clip (no encoder on this machine for it, e.g. 10-bit AV1 WebM).
