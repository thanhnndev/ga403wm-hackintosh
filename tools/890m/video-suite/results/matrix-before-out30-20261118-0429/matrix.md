| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | yes | **SW** (FFmpeg) | 0 / 360 | 0 | 62 / 0 / 0 / 0 | 7.5 | 31.4 | 1.1 | - | FAIL |  |
| VP9 | profile 0 8-bit | 1080p60 | WebM | yes | HW (VideoToolbox) | 0 / 720 | 19 | 124 / 0 / 0 / 0 | 16.2 | 13.3 | 2 | - | PASS |  |
| VP9 | profile 0 8-bit | 1080p60 | MSE WebM | yes | HW (VideoToolbox) | 6 / 720 | 3 | 127 / 0 / 0 / 0 | 15.9 | 13.9 | 2.4 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | WebM | yes | HW (VideoToolbox) | 0 / 720 | 0 | 130 / 0 / 0 / 0 | 19.2 | 15.5 | 4.6 | - | PASS |  |
| AV1 | main 8-bit | 1080p60 | MSE WebM | yes | HW (VideoToolbox) | 0 / 720 | 0 | 128 / 0 / 0 / 0 | 18.8 | 13.9 | 4.3 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | WebM | yes | HW (VideoToolbox) | 0 / 722 | 92 | 98 / 0 / 0 / 0 | 20.1 | 28.3 | 2.9 | - | PASS |  |
| VP9 | profile 0 8-bit | 2160p60 | MSE WebM | yes | HW (VideoToolbox) | 0 / 720 | 63 | 117 / 0 / 0 / 0 | 19.8 | 31.4 | 2.2 | - | PASS | MSE appendBuffer: Failed to execute 'appendBuffer' on 'SourceBuffer': The SourceBuffer is full, and cannot free space to |
| H.264 | High 8-bit | 1080p60 | MP4 | yes | **SW** (FFmpeg) | 2 / 720 | 0 | 124 / 0 / 0 / 0 | 11.8 | 58.2 | 1.9 | - | FAIL |  |
| H.264 | High 8-bit | 2160p30 | MP4 | yes | **SW** (FFmpeg) | 0 / 358 | 2 | 62 / 0 / 0 / 0 | 9.9 | 116.2 | 1.7 | - | FAIL |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | no | - | - / - | - | 0 / 0 / 0 / 0 | - | - | - | - | FAIL | PipelineStatus::CHUNK_DEMUXER_ERROR_APPEND_FAILED: Failure parsing MP4: Detected unfragmented MP4. Media Source Extensio |
| HEVC | Main 8-bit | 1080p60 | MP4 | yes | HW (VideoToolbox) | 9 / 722 | 2 | 127 / 0 / 0 / 0 | 23.7 | 16.3 | 2.8 | - | PASS |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | yes | HW (VideoToolbox) | 0 / 720 | 0 | 126 / 0 / 0 / 0 | 22.9 | 16.2 | 2.8 | - | PASS |  |
