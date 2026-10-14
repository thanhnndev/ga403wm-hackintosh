// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickSound: View {
    @Bindable var audio: AudioModel

    var body: some View {
        QuickSection(title: "Sound", symbol: "speaker.wave.2") {
            ProfileSelector(audio: audio, isCompact: true)
            HStack(spacing: 10) {
                Toggle(isOn: $audio.isMuted) {
                    Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.fill")
                }
                .toggleStyle(.button)
                .help(audio.isMuted ? "Unmute the speaker amps" : "Mute the speaker amps")
                .accessibilityLabel("Mute speaker amps")
                Slider(value: $audio.volume, in: -60...0)
                    .disabled(audio.isMuted)
                    .accessibilityLabel("Amp volume")
                Text(String(format: "%.0f dB", audio.volume))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
