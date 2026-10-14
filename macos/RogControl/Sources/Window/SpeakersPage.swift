// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct SpeakersPage: View {
    @Bindable var audio: AudioModel
    let tests: SpeakerTestModel

    var body: some View {
        Form {
            Section("Sound profile") {
                ProfileSelector(audio: audio)
                    .padding(.vertical, 4)
            }
            Section("Volume") {
                ValueSlider(title: "Amp volume", value: $audio.volume, range: -60...0) { String(format: "%.0f dB", $0) }
                    .disabled(audio.isMuted)
                Toggle("Mute speaker amps", isOn: $audio.isMuted)
            }
            Section {
                NavigationLink {
                    SpeakerTestsPage(tests: tests)
                } label: {
                    Label("Speaker Tests", systemImage: "waveform")
                }
            } footer: {
                Text("Play test files through the built-in output or ROG Speakers to check clarity, bass and stereo.")
            }
            Section("Status") {
                LabeledContent("Settings", value: audio.statusTitle)
                LabeledContent("Amplifiers", value: audio.ampState)
                LabeledContent("Firmware", value: audio.firmware)
                LabeledContent("Output", value: audio.headphonesPlugged ? "Headphones" : "Speakers")
                if !audio.error.isEmpty { Notice(text: audio.error, kind: .caution) }
            }
        }
    }
}
