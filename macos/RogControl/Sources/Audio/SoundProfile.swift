// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

enum SoundProfile: String, CaseIterable, Identifiable {
    case off, balanced, music, movie, voice

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .off: "speaker.slash"
        case .balanced: "slider.horizontal.3"
        case .music: "music.note"
        case .movie: "film"
        case .voice: "person.wave.2"
        }
    }

    var detail: String {
        switch self {
        case .off: "Flat. No processing, for measurement or your own EQ."
        case .balanced: "Gentle bass lift and clearer mids. The everyday default."
        case .music: "Wider and fuller, with controlled bass."
        case .movie: "Strong low end and a wide stage for effects."
        case .voice: "Cuts boom and boosts presence for speech."
        }
    }
}
