| codec | profile / depth | size | container | plays | decoder | dropped / decoded | late | frame check ok / near / bad / unreadable | GPU-proc % | renderer % | WS % | W over pre-idle | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| HEVC | Main 8-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 720 | 0 | 120 / 0 / 0 / 0 | 17.2 | 16.7 | 6.1 | - | FAIL |  |
| HEVC | Main10 10-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 9 / 720 | 4 | 125 / 0 / 0 / 0 | 22.1 | 16.4 | 15.8 | - | FAIL |  |
| HEVC | Main 8-bit | 2160p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 6 / 720 | 94 | 105 / 0 / 0 / 0 | 22.5 | 35.5 | 2.5 | - | FAIL |  |
| HEVC | Main 8-bit | 1080p60 | MSE fMP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 720 | 0 | 127 / 0 / 0 / 0 | 16.9 | 15 | 2.1 | - | FAIL |  |
