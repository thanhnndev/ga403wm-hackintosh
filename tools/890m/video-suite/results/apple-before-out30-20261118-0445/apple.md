| app | codec | profile / depth | size | container | plays | decoder | frame check ok / near / bad / unreadable | VTDec % | WebKit GPU % | WebContent % | QuickTime % | pass | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Safari | H.264 | High 8-bit | 1080p30 | MP4 | yes | **SW** (WebKit) | 0 / 1 / 1 / 0 | 1.7 | 154.9 | 0.7 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p60 | WebM | yes | **SW** (WebKit; VCNDec failed) | 1 / 6 / 0 / 0 | 0.9 | 139.4 | 10.3 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | VP9 | profile 0 8-bit | 1080p60 | MSE WebM | yes | **SW** (VideoToolbox, Apple software; VCNDec failed) | 6 / 1 / 0 / 0 | 14.4 | 122.2 | 8.6 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | AV1 | main 8-bit | 1080p60 | WebM | yes | HW (VCNDec 8-bit) | 0 / 0 / 0 / 0 | 10.8 | 131 | 2.6 | 4.6 | PASS | decoding in software: WebKit GPU 131 % + VTDecoderXPCService 10.8 % CPU (page hidden) |
| Safari | AV1 | main 8-bit | 1080p60 | MSE WebM | yes | HW (VCNDec 8-bit) | 0 / 0 / 0 / 2 | 0 | 0 | 2.5 | 0 | FAIL | page hidden (background window): few strip reads; Media failed to decode |
| Safari | VP9 | profile 0 8-bit | 2160p60 | WebM | yes | **SW** (WebKit; VCNDec failed) | 0 / 0 / 0 / 0 | 0 | 251.8 | 0.7 | 0 | FAIL | decoding in software: WebKit GPU 251.8 % + VTDecoderXPCService 0 % CPU (page hidden) |
| Safari | VP9 | profile 0 8-bit | 2160p60 | MSE WebM | yes | **SW** (WebKit; VCNDec failed) | 0 / 0 / 0 / 0 | 0 | 515.8 | 21.5 | 0 | FAIL | decoding in software: WebKit GPU 515.8 % + VTDecoderXPCService 0 % CPU (page hidden) |
| Safari | H.264 | High 8-bit | 1080p60 | MP4 | yes | **SW** (WebKit) | 0 / 0 / 0 / 0 | 0 | 239.2 | 0.5 | 0 | FAIL | decoding in software: WebKit GPU 239.2 % + VTDecoderXPCService 0 % CPU (page hidden) |
| Safari | H.264 | High 8-bit | 2160p30 | MP4 | yes | **SW** (WebKit) | 1 / 0 / 0 / 0 | 0 | 323.9 | 1.2 | 0 | FAIL | page hidden (background window): few strip reads |
| Safari | H.264 | High 8-bit | 1080p60 | MSE fMP4 | no | - | 0 / 0 / 0 / 0 | - | - | - | - | FAIL | page hidden (background window): few strip reads; play(): The operation is not supported. |
| Safari | HEVC | Main 8-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 0 / 0 / 0 | 53 | 157.7 | 0.4 | 0.4 | FAIL | decoding in software: WebKit GPU 157.7 % + VTDecoderXPCService 53 % CPU (page hidden) |
| Safari | HEVC | Main10 10-bit | 1080p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 0 / 0 / 0 | 164.6 | 200.5 | 0.7 | 0.1 | FAIL | decoding in software: WebKit GPU 200.5 % + VTDecoderXPCService 164.6 % CPU (page hidden) |
| Safari | HEVC | Main 8-bit | 2160p60 | MP4 | yes | **SW** (VideoToolbox, Apple software) | 0 / 0 / 0 / 1 | 123.2 | 0 | 7 | 0.1 | FAIL | page hidden (background window): few strip reads |
