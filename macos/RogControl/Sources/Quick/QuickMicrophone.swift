// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickMicrophone: View {
    @Bindable var audio: AudioModel
    @Bindable var microphone: MicrophoneModel

    var body: some View {
        QuickSection(title: "Microphone", symbol: "mic") {
            Toggle("ROG Clear Mic", isOn: $audio.micEnabled)
            Toggle("Noise cancellation", isOn: $audio.noiseCancellation)
                .disabled(!audio.micEnabled)
            if audio.micEnabled && audio.noiseCancellation {
                HStack(spacing: 10) {
                    Text("Strength").font(.callout).foregroundStyle(.secondary)
                    Slider(value: $audio.noiseStrength, in: 0...100)
                        .accessibilityLabel("Noise cancellation strength")
                    Text(String(format: "%.0f%%", audio.noiseStrength))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Button {
                microphone.toggleMonitor()
            } label: {
                Label(microphone.isListening ? "Stop monitoring" : "Hear yourself",
                      systemImage: microphone.isListening ? "stop.fill" : "ear")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .disabled(!microphone.isListening && !microphone.canMonitor)
            if !audio.headphonesPlugged && !microphone.isListening {
                Text("Plug in headphones to hear yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if microphone.isListening {
                LevelMeter(level: microphone.level, isActive: true)
            }
        }
    }
}
