// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct SettingsPage: View {
    @Bindable var laptop: LaptopModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at Login", isOn: $laptop.startsAtLogin)
            }
            Section("System") {
                LabeledContent("Driver", value: laptop.isAvailable ? "AsusWmi loaded" : "Not loaded")
                LabeledContent("Keyboard", value: laptop.state.lighting ? "Lighting control available" : "Unavailable")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                LabeledContent("Device", value: "ROG Zephyrus G14 (GA403WM)")
            }
        }
    }
}
