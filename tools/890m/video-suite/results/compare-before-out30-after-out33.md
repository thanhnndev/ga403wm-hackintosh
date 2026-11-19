# Codec matrix: before-out30 -> after-out33

CPU % = VideoToolbox XPC service + the app's decoding process (Chrome GPU process, WebKit GPU process, QuickTime Player) over the measured window (Safari cells: a background window).

| codec | profile / depth | size | container | app | before | after | CPU % before | CPU % after | |
|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | Chrome | SW FFmpeg | VCN | 21 | 13 | fixed |
| H.264 | High 8-bit | 1080p30 | MP4 | Safari | SW | VCN | 157 | 139 | fixed |
| H.264 | High 8-bit | 1080p30 | MP4 | QuickTime | SW | VCN | 39 | 0 | fixed |
| H.264 | High 8-bit | 1080p60 | fMP4 | QuickTime | SW | VCN | 70 | 11 | fixed |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Chrome | SW FFmpeg | VCN | 10 | 22 | fixed |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | Safari | SW | VCN | 150 | 13 | fixed |
| H.264 | High 8-bit | 1080p60 | MP4 | Chrome | SW FFmpeg | VCN | 10 | 23 | fixed |
| H.264 | High 8-bit | 1080p60 | MP4 | Safari | SW | VCN | 84 | 7 | fixed |
| H.264 | High 8-bit | 1080p60 | MP4 | QuickTime | SW | VCN | 72 | 11 | fixed |
| H.264 | High 8-bit | 2160p30 | MP4 | Chrome | SW FFmpeg | VCN | 8 | 17 | fixed |
| H.264 | High 8-bit | 2160p30 | MP4 | Safari | SW | VCN | 164 | 18 | fixed |
| H.264 | High 8-bit | 2160p30 | MP4 | QuickTime | SW | VCN | 123 | 9 | fixed |
| HEVC | Main 8-bit | 1080p60 | fMP4 | QuickTime | SW | VCN | 42 | 11 | fixed |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Chrome | SW | VCN | 64 | 22 | fixed |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | Safari | SW | VCN | 129 | 26 | fixed |
| HEVC | Main 8-bit | 1080p60 | MP4 | Chrome | SW | VCN | 65 | 23 | fixed |
| HEVC | Main 8-bit | 1080p60 | MP4 | Safari | SW | VCN | 233 | 15 | fixed |
| HEVC | Main 8-bit | 1080p60 | MP4 | QuickTime | SW | VCN | 43 | 11 | fixed |
| HEVC | Main 8-bit | 2160p60 | MP4 | Chrome | SW | VCN | 183 | 27 | fixed |
| HEVC | Main 8-bit | 2160p60 | MP4 | Safari | SW | VCN | 224 | 35 | fixed |
| HEVC | Main 8-bit | 2160p60 | MP4 | QuickTime | SW | VCN | 127 | 13 | fixed |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Chrome | SW | VCN | 72 | 28 | fixed |
| HEVC | Main10 10-bit | 1080p60 | MP4 | Safari | SW | VCN | 224 | 44 | fixed |
| HEVC | Main10 10-bit | 1080p60 | MP4 | QuickTime | SW | VCN | 50 | 11 | fixed |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Chrome | VCN | VCN | 13 | 14 | was HW |
| VP9 | profile 0 8-bit | 1080p30 | WebM | Safari | SW | VCN | 193 | 52 | fixed |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Chrome | VCN | VCN | 13 | 12 | was HW |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | Safari | SW | VCN | 245 | 10 | fixed |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Chrome | VCN | VCN | 18 | 22 | was HW |
| VP9 | profile 0 8-bit | 1080p60 | WebM | Safari | SW | VCN | 140 | 9 | fixed |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Chrome | VCN | VCN | 18 | 22 | was HW |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | Safari | SW | VCN | 137 | 9 | fixed |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Chrome | VCN | VCN | 23 | 25 | was HW |
| VP9 | profile 0 8-bit | 2160p60 | WebM | Safari | SW | VCN | 252 | 15 | fixed |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Chrome | VCN | VCN | 22 | 26 | was HW |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | Safari | SW | VCN | 516 | 23 | fixed |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Chrome | SW Vpx | VCN | 16 | 38 | fixed |
| VP9 | profile 2 10-bit | 1080p60 | WebM | Safari | SW | VCN | 288 | 9 | fixed |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Chrome | SW Vpx | VCN | 16 | 24 | fixed |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | Safari | SW | VCN | 317 | 11 | fixed |
| AV1 | main 10-bit | ?p? | WebM | Chrome | no clip | no clip | - | - | no clip |
| AV1 | main 10-bit | 1080p30 | MP4 | Chrome | SW Dav1d | VCN | 7 | 16 | fixed |
| AV1 | main 10-bit | 1080p30 | MP4 | Safari | does not play | VCN | - | 6 | fixed |
| AV1 | main 10-bit | 1080p30 | MP4 | QuickTime | does not play | VCN | 2 | 9 | fixed |
| AV1 | main 8-bit | 1080p30 | MP4 | Chrome | VCN | VCN | 20 | 13 | was HW |
| AV1 | main 8-bit | 1080p30 | MP4 | Safari | VCN | VCN | 139 | 7 | was HW |
| AV1 | main 8-bit | 1080p30 | MP4 | QuickTime | SW | VCN | 7 | 8 | fixed |
| AV1 | main 8-bit | 1080p30 | WebM | Chrome | VCN | VCN | 15 | 14 | was HW |
| AV1 | main 8-bit | 1080p30 | WebM | Safari | VCN | VCN | 209 | 17 | was HW |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Chrome | VCN | VCN | 13 | 14 | was HW |
| AV1 | main 8-bit | 1080p30 | MSE WebM | Safari | VCN | VCN | 112 | 11 | was HW |
| AV1 | main 8-bit | 1080p60 | WebM | Chrome | VCN | VCN | 20 | 25 | was HW |
| AV1 | main 8-bit | 1080p60 | WebM | Safari | VCN | VCN | 142 | 48 | was HW |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Chrome | VCN | VCN | 20 | 25 | was HW |
| AV1 | main 8-bit | 1080p60 | MSE WebM | Safari | VCN | VCN | 0 | 16 | was HW |
| AV1 | main 8-bit | 2160p60 | WebM | Chrome | VCN | VCN | 38 | 35 | was HW |
| AV1 | main 8-bit | 2160p60 | WebM | Safari | VCN | VCN | 154 | 22 | was HW |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Chrome | VCN | VCN | 38 | 37 | was HW |
| AV1 | main 8-bit | 2160p60 | MSE WebM | Safari | VCN | VCN | 93 | 23 | was HW |

38 cells fixed, 20 already on the VCN before, 0 still failing.
