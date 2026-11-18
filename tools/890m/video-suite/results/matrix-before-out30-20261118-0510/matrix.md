| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AV1 | main 10-bit | ?p? | WebM | no clip | - | - / - | - | - | - | - | - | - | FAIL |  |
| AV1 | main 10-bit | 1080p30 | MP4 | yes | **SW** (Chrome Dav1d) | 3 / 308 | 1 | 38 / 0 / 0 / 0 | 7.3 | 81.4 | 0.8 | - | FAIL | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
