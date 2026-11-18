| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AV1 | main 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 63 / 360 | 63 | 52 / 0 / 0 / 0 | 10.3 | 7.9 | 2.2 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 10.1 | 7.7 | 2.3 | - | PASS |  |
| AV1 | main 10-bit | ?p? | WebM | no clip | - | - / - | - | - | - | - | - | - | FAIL |  |
| AV1 | main 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 100 | 106 / 0 / 0 / 0 | 28.6 | 33.1 | 5.2 | - | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 98 | 105 / 0 / 0 / 0 | 28.4 | 33.6 | 5.9 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 63 / 0 / 0 / 0 | 15 | 12.2 | 2 | - | PASS |  |
| AV1 | main 10-bit | 1080p30 | MP4 | yes | **SW** (Chrome Dav1d) | 0 / 360 | 0 | 61 / 0 / 0 / 0 | 13.2 | 80.9 | 1.7 | - | FAIL | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
