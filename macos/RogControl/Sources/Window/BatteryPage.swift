// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct BatteryPage: View {
    @Bindable var laptop: LaptopModel

    var body: some View {
        Form {
            Section {
                Picker("Charge limit", selection: $laptop.chargeLimitSetting) {
                    Text("60%").tag(60)
                    Text("80%").tag(80)
                    Text("100%").tag(100)
                }
                .pickerStyle(.segmented)
                .disabled(laptop.state.charge == nil)
                if !laptop.chargeError.isEmpty { Notice(text: laptop.chargeError, kind: .caution) }
            } header: {
                Text("Charging")
            } footer: {
                Text("A lower limit keeps the battery cooler and slows wear when the laptop stays plugged in.")
            }
            Section("Status") {
                LabeledContent("Charge", value: laptop.batteryPercent.map { "\($0)%" } ?? "Unavailable")
                LabeledContent("State", value: laptop.batteryTitle)
                LabeledContent("Health", value: laptop.batteryHealth.map { "\($0)% of design capacity" } ?? "Unavailable")
                LabeledContent("Capacity", value: laptop.state.batFull > 0 ? "\(laptop.state.batFull) of \(laptop.state.batDesign) mAh" : "Unavailable")
            }
        }
    }
}
