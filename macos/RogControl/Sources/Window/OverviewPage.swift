// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct OverviewPage: View {
    let laptop: LaptopModel
    let audio: AudioModel

    var body: some View {
        Form {
            Section("Performance") {
                ModeSelector(laptop: laptop)
                    .padding(.vertical, 4)
                if !laptop.modeError.isEmpty { Notice(text: laptop.modeError, kind: .caution) }
            }
            Section("Live") {
                HStack(alignment: .top, spacing: 24) {
                    LiveMetric(title: "CPU temperature", value: laptop.temperature.map { String(format: "%.0f", $0) } ?? "-",
                               unit: "°C", symbol: "thermometer.medium", history: laptop.temperatureHistory)
                    LiveMetric(title: "Package power", value: laptop.watts.map { String(format: "%.0f", $0) } ?? "-",
                               unit: "W", symbol: "bolt", history: laptop.powerHistory)
                    LiveMetric(title: "CPU fan", value: "\(laptop.state.cpuFan)", unit: "rpm", symbol: "fan")
                    LiveMetric(title: "GPU fan", value: "\(laptop.state.gpuFan)", unit: "rpm", symbol: "fan")
                }
                .padding(.vertical, 6)
            }
            Section("Battery") {
                LabeledContent("Charge", value: laptop.batteryPercent.map { "\($0)%" } ?? "Unavailable")
                LabeledContent("Status", value: laptop.batteryTitle)
                LabeledContent("Charge limit", value: "\(laptop.chargeLimitSetting)%")
            }
            Section("Audio") {
                LabeledContent("Sound profile", value: audio.profile.title)
                LabeledContent("Microphone", value: audio.micState)
                LabeledContent("Output", value: audio.headphonesPlugged ? "Headphones" : "Speakers")
            }
        }
    }
}
