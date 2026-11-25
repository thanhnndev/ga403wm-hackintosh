| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H.264 | High 8-bit | 1080p30 | MP4 | yes | **SW** (FFmpeg) | 1 / 360 | 0 | 61 / 0 / 0 / 0 | 7.4 | 29.2 | 1.1 | - | FAIL |  |
| H.264 | High 8-bit | 1080p60 | MP4 | yes | **SW** (FFmpeg) | 0 / 720 | 0 | 123 / 0 / 0 / 0 | 10.8 | 51.7 | 1.8 | - | FAIL |  |
| H.264 | High 8-bit | 2160p30 | MP4 | yes | **SW** (FFmpeg) | 0 / 361 | 0 | 63 / 0 / 0 / 0 | 9 | 103.3 | 1.1 | - | FAIL |  |
| H.264 | High 8-bit | 1080p60 | MSE fMP4 | no | - | - / - | - | 0 / 0 / 0 / 0 | - | - | - | - | FAIL | PipelineStatus::CHUNK_DEMUXER_ERROR_APPEND_FAILED: Failure parsing MP4: Detected unfragmented MP4. Media Source Extensio |
