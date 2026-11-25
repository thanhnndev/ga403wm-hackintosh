| app | codec | profile / depth | size | container | plays | decoder | frame check ok / near / bad / unreadable | VTDec % | WebKit GPU % | WebContent % | QuickTime % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Safari | H.264 | High 8-bit | 1080p60 | MP4 | yes | **SW** (WebKit) | 1 / 0 / 1 / 0 | 4.2 | 79.6 | 0.3 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 2160p30 | MP4 | yes | **SW** (WebKit) | 0 / 1 / 0 / 0 | 4.8 | 159.6 | 2.1 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 1080p60 | MSE fMP4 | yes | **SW** (WebKit) | 1 / 1 / 0 / 0 | 4.1 | 145.8 | 4.1 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 1 / 0 | 29.3 | 203.2 | 0.5 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | HEVC | Main10 10-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 1 / 0 | 57.2 | 166.9 | 0.3 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 2160p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 1 / 0 / 0 / 0 | 126.4 | 97.2 | 1.9 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 1080p60 | MSE fMP4 | yes | **SW** (VideoToolbox, Apple software) | 2 / 0 / 0 / 0 | 27.3 | 101.9 | 3.5 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p30 | WebM | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 1 / 1 / 0 / 0 | 12 | 180.8 | 2.2 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p30 | MSE WebM | yes | **SW** (WebKit; VCNDec failed) | 2 / 0 / 0 / 0 | 1.9 | 243.5 | 3.6 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 2 10-bit | 1080p60 | WebM | yes | **SW** (WebKit; VCNDec refused) | 2 / 0 / 0 / 0 | 0.8 | 286.7 | 6.4 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 2 10-bit | 1080p60 | MSE WebM | yes | **SW** (VideoToolbox, Apple software; VCNDec refused) | 0 / 2 / 0 / 0 | 9.9 | 306.6 | 13.3 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 2 / 0 / 0 / 0 | 10.5 | 198.7 | 1.8 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 1 / 1 / 0 / 0 | 11.2 | 101.1 | 2.1 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 2 / 0 / 0 | 13.1 | 140.7 | 5.5 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 1 / 0 / 0 | 15.4 | 78 | 8.1 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 0 / 2 / 0 | 36.6 | 102.3 | 0.4 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 10-bit | 1080p30 | MP4 | no | - | 0 / 0 / 0 / 0 | - | - | - | - | FAIL | page hidden (background window): few strip reads; Media failed to decode |
