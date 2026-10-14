// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct MicrophonePage: View {
    @Bindable var audio: AudioModel
    @Bindable var microphone: MicrophoneModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable ROG Clear Mic", isOn: $audio.micEnabled)
                Toggle("Noise cancellation", isOn: $audio.noiseCancellation)
                    .disabled(!audio.micEnabled)
                ValueSlider(title: "Strength", value: $audio.noiseStrength, range: 0...100) { String(format: "%.0f%%", $0) }
                    .disabled(!audio.noiseCancellation || !audio.micEnabled)
            } header: {
                Text("ROG Clear Mic")
            } footer: {
                Text(audio.micEnabled ? "The built-in mic is captured only while an app records from ROG Clear Mic."
                                      : "Off: RogAudio never captures the built-in mic, and ROG Clear Mic delivers silence.")
            }
            Section {
                Picker("Source", selection: $microphone.source) {
                    ForEach(MicSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(microphone.isBusy)
                LevelMeter(level: microphone.level, isActive: microphone.isBusy)
                HStack {
                    Button {
                        microphone.toggleMonitor()
                    } label: {
                        Label(microphone.isListening ? "Stop Monitoring" : "Hear Yourself",
                              systemImage: microphone.isListening ? "stop.fill" : "ear")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!microphone.isListening && !microphone.canMonitor)
                    Button {
                        microphone.toggleTest()
                    } label: {
                        Label(microphone.isTesting ? "Stop Test" : "Test Level", systemImage: microphone.isTesting ? "stop.fill" : "mic")
                    }
                    .disabled(microphone.isListening || (!microphone.isTesting && !microphone.canTest))
                    Spacer()
                    Text(microphone.result).foregroundStyle(.secondary)
                }
                ValueSlider(title: "Monitor gain", value: $microphone.monitorGain, range: 0...4) { String(format: "%.1fx", $0) }
                    .disabled(microphone.isListening)
                if !audio.headphonesPlugged && !microphone.isListening {
                    Notice(text: "Plug in headphones to hear yourself. Through the speakers the mic would feed back.")
                }
                if microphone.source == .clear && !audio.micEnabled {
                    Notice(text: "Enable ROG Clear Mic to listen to the noise-cancelled signal.")
                }
                if !microphone.error.isEmpty { Notice(text: microphone.error, kind: .caution) }
            } header: {
                Text("Listen and test")
            }
        }
    }
}
