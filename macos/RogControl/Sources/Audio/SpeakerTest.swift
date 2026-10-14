// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

/// One entry of the synthesized speaker test set (tools/gen-audio-test.py writes index.json next to the files).
struct SpeakerTest: Decodable, Identifiable, Equatable {
    let file: String
    let title: String
    let group: String
    let description: String
    let channels: String
    let seconds: Double

    var id: String { file }
}
