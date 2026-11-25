| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | yes | **SW** (Chrome FFmpeg) | 4 / 360 | 6 | 61 / 0 / 0 / 0 | 6.8 | 27.6 | 21.7 | - | FAIL |  |
| VP9 | profile 0 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 125 / 0 / 0 / 0 | 13.9 | 12.5 | 1.8 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 13.6 | 12.1 | 1.7 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 127 / 0 / 0 / 0 | 15 | 12.3 | 4.2 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 15.5 | 11.8 | 4 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 33 | 120 / 0 / 0 / 0 | 17.1 | 29.2 | 2.2 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 719 | 42 | 119 / 0 / 0 / 0 | 16.8 | 25.7 | 1.9 | - | PASS | MSE appendBuffer: Failed to execute 'appendBuffer' on 'SourceBuffer': The SourceBuffer is full, and cannot free space to |
| H.264 | High 8-bit | 1080p60 | MP4 | yes | **SW** (Chrome FFmpeg) | 0 / 720 | 0 | 123 / 0 / 0 / 0 | 9.7 | 47.1 | 1.9 | - | FAIL |  |
| H.264 | High 8-bit | 2160p30 | MP4 | yes | **SW** (Chrome FFmpeg) | 0 / 360 | 0 | 62 / 0 / 0 / 0 | 7.9 | 92.6 | 1.1 | - | FAIL |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | yes | **SW** (Chrome FFmpeg) | 0 / 721 | 0 | 123 / 0 / 0 / 0 | 9.9 | 51.5 | 1.7 | - | FAIL |  |
| HEVC | Main 8-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 7 / 722 | 3 | 125 / 0 / 0 / 0 | 15.6 | 14.8 | 1.8 | - | FAIL |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 720 | 1 | 125 / 0 / 0 / 0 | 22.5 | 16.5 | 2.7 | - | FAIL |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 722 | 79 | 108 / 0 / 0 / 0 | 21 | 31.2 | 2.3 | - | PASS |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | yes | HW (VCNDec 8-bit) | 6 / 722 | 2 | 129 / 0 / 0 / 0 | 16.8 | 15.1 | 2.2 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p30 | WebM | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 32 / 163 | 32 | 25 / 0 / 0 / 0 | 4.4 | 3.5 | 0.5 | - | FAIL | PipelineStatus::PIPELINE_ERROR_DECODE: Error Domain=NSOSStatusErrorDomain Code=-12911 "(null)" (-12911): VTDecompression |
| VP9 | profile 0 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 63 / 0 / 0 / 0 | 10.1 | 8.9 | 1.5 | - | PASS |  |
| VP9 | profile 2 10-bit | 1080p60 | WebM | yes | **SW** (Chrome Vpx) | 0 / 720 | 0 | 125 / 0 / 0 / 0 | 16.1 | 122.5 | 2.2 | - | FAIL | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
| VP9 | profile 2 10-bit | 1080p60 | MSE WebM | yes | **SW** (Chrome Vpx) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 16.2 | 121.6 | 2.2 | - | FAIL | Error Domain=NSOSStatusErrorDomain Code=-12910 "(null)" (-12910): VTDecompressionSessionCreate() |
| AV1 | main 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 11.8 | 9.4 | 2.9 | - | PASS |  |
| AV1 | main 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 360 | 0 | 64 / 0 / 0 / 0 | 11.4 | 8.8 | 2.5 | - | PASS |  |
| AV1 | main 10-bit | ?p? | WebM | no clip | - | - / - | - | - | - | - | - | - | FAIL |  |
| AV1 | main 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 720 | 90 | 95 / 0 / 0 / 0 | 21.4 | 30.5 | 4.5 | - | PASS |  |
| AV1 | main 8-bit | 2160p60 | MSE WebM | no | - | 0 / 0 | 0 | 1 / 0 / 1 / 0 | 2.9 | 1.5 | 0.1 | - | FAIL | PipelineStatus::PIPELINE_ERROR_DECODE: Error Domain=NSOSStatusErrorDomain Code=-12911 "(null)" (-12911): VTDecompression |
