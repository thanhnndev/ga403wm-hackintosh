| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 10.5 | 10 | 19.8 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 16.3 | 15.8 | 35 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 127 / 0 / 0 / 0 | 16.2 | 15.7 | 20.2 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 719 | 0 | 127 / 0 / 0 / 0 | 19.3 | 16.4 | 40.1 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 127 / 0 / 0 / 0 | 19.1 | 15.8 | 34.4 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 718 | 92 | 108 / 0 / 0 / 0 | 18.9 | 34.7 | 38.1 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 90 | 94 / 0 / 0 / 0 | 18.7 | 29 | 36.5 | - | PASS | MSE appendBuffer: Failed to execute 'appendBuffer' on 'SourceBuffer': The SourceBuffer is full, and cannot free space to |
| H.264 | High 8-bit | 1080p60 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 720 | 1 | 126 / 0 / 0 / 0 | 16.8 | 16.3 | 24.9 | - | PASS |  |
| H.264 | High 8-bit | 2160p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 360 | 1 | 64 / 0 / 0 / 0 | 13.1 | 20.8 | 10.3 | - | PASS |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 15.7 | 15.2 | 18.6 | - | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 16.8 | 16.9 | 28.3 | - | PASS |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | yes | HW (VCNDec 10-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 22.3 | 16.5 | 32.6 | - | PASS |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 720 | 91 | 109 / 0 / 0 / 0 | 19.8 | 33.4 | 11.8 | - | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 16.1 | 15.9 | 17.7 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 5 / 360 | 3 | 61 / 1 / 0 / 0 | 10.4 | 10.8 | 42.9 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 9.1 | 8.3 | 10.8 | - | PASS |  |
| VP9 | profile 2 10-bit | 1080p60 | WebM | yes | HW (VCNDec 10-bit) | 0 / 720 | 0 | 128 / 0 / 0 / 0 | 14 | 91.8 | 21 | - | PASS |  |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 10-bit) | 0 / 720 | 0 | 127 / 0 / 0 / 0 | 19.4 | 13.5 | 37.8 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 11.1 | 9 | 12.5 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 11 | 8.3 | 12.3 | - | PASS |  |
| AV1 | main 10-bit | ?p? | WebM | no clip | - | - / - | - | - | - | - | - | - | FAIL |  |
| AV1 | main 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 4 / 719 | 69 | 113 / 0 / 0 / 0 | 20.4 | 29.8 | 65.8 | - | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 95 | 106 / 0 / 0 / 0 | 22.4 | 33.5 | 16.1 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 65 / 0 / 0 / 0 | 10.2 | 9.8 | 11.8 | - | PASS |  |
| AV1 | main 10-bit | 1080p30 | MP4 | yes | HW (VCNDec 10-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 13.4 | 9.9 | 28.8 | - | PASS |  |
