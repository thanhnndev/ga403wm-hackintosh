// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

enum MicSource: String, CaseIterable, Identifiable {
    case clear, builtin

    var id: String { rawValue }
    var title: String { self == .clear ? "ROG Clear Mic" : "Built-in Mic" }
    var uid: String { self == .clear ? "com.itlmt7925.rogaudio.mic" : "AppleHDAEngineInput:0,6,0,1,0:1" }
}

enum PlaybackTarget: String, CaseIterable, Identifiable {
    case direct, dsp

    var id: String { rawValue }
    var title: String { self == .direct ? "Built-in output" : "ROG Speakers" }
}
