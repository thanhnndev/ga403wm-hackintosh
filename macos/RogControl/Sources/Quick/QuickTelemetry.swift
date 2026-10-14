// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickTelemetry: View {
    let laptop: LaptopModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            LiveMetric(title: "CPU", value: laptop.temperature.map { String(format: "%.0f", $0) } ?? "-", unit: "°C",
                       symbol: "thermometer.medium", history: laptop.temperatureHistory)
            LiveMetric(title: "Power", value: laptop.watts.map { String(format: "%.0f", $0) } ?? "-", unit: "W",
                       symbol: "bolt", history: laptop.powerHistory)
            LiveMetric(title: "Fans", value: "\(laptop.state.cpuFan)", unit: "rpm", symbol: "fan")
        }
    }
}
