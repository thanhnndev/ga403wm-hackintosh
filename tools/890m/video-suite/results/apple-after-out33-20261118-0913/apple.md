| app | codec | profile / depth | size | container | plays | decoder | frame check ok / near / bad / unreadable | VTDec % | WebKit GPU % | WebContent % | QuickTime % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Safari | H.264 | High 8-bit | 1080p30 | MP4 | yes | HW (VCNDec 8-bit) | 0 / 1 / 1 / 0 | 0 | 139.2 | 1 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 9 / 0 / 0 / 0 | 0 | 9.1 | 4.1 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 9 / 0 / 0 / 0 | 0 | 8.9 | 3.3 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 1 / 0 / 0 / 0 | 18.5 | 29.1 | 4.5 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 2 / 4 / 0 / 0 | 7.2 | 8.8 | 4.7 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 3 / 4 / 0 / 0 | 0 | 15 | 5.4 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 3 / 0 / 0 | 0 | 22.5 | 14.3 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 1080p60 | MP4 | yes | HW (VCNDec 8-bit) | 7 / 0 / 0 / 0 | 0 | 7 | 0.3 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 2160p30 | MP4 | yes | HW (VCNDec 8-bit) | 5 / 1 / 1 / 0 | 0 | 17.7 | 5.9 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 1080p60 | MSE fMP4 | yes | HW (VCNDec 8-bit) | 4 / 5 / 0 / 0 | 0 | 12.8 | 6.7 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 1080p60 | MP4 | yes | HW (VCNDec 8-bit) | 8 / 0 / 0 / 0 | 5.6 | 8.9 | 2.5 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | HEVC | Main10 10-bit | 1080p60 | MP4 | yes | HW (VCNDec 10-bit) | 1 / 0 / 1 / 0 | 8.8 | 35.5 | 0.4 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 2160p60 | MP4 | yes | HW (VCNDec 8-bit) | 5 / 0 / 0 / 0 | 20.9 | 14.1 | 4.5 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | HEVC | Main 8-bit | 1080p60 | MSE fMP4 | yes | HW (VCNDec 8-bit) | 8 / 1 / 0 / 0 | 14.3 | 12 | 7 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 2 / 1 / 0 / 0 | 5.7 | 46 | 2.6 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 4 / 3 / 0 / 0 | 4 | 5.9 | 2.9 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | VP9 | profile 2 10-bit | 1080p60 | WebM | yes | **SW** (WebKit) | 2 / 0 / 0 / 0 | 4 | 42.1 | 7.4 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 2 10-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 10-bit) | 4 / 2 / 0 / 0 | 4.4 | 10.1 | 5.4 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | WebM | yes | HW (VCNDec 8-bit) | 4 / 2 / 0 / 0 | 8.4 | 8.2 | 5 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | MSE WebM | yes | HW (VCNDec 8-bit) | 4 / 2 / 0 / 0 | 4.8 | 6.5 | 3.7 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 2160p60 | WebM | yes | HW (VCNDec 8-bit) | 3 / 2 / 0 / 0 | 11.3 | 10.8 | 5.4 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 2160p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 1 / 0 / 0 | 9.4 | 13.9 | 9.2 | 0 | PASS | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p30 | MP4 | yes | **SW** (WebKit) | 6 / 1 / 0 / 0 | 3.8 | 5.8 | 1.8 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | AV1 | main 10-bit | 1080p30 | MP4 | yes | HW (VCNDec 10-bit) | 6 / 0 / 0 / 0 | 2.6 | 3.6 | 0.4 | 0 | PASS | page hidden (background window): few strip reads |
