// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickLighting: View {
    @Bindable var laptop: LaptopModel

    var body: some View {
        QuickSection(title: "Lighting", symbol: "keyboard") {
            Picker("Keyboard", selection: $laptop.keyboardLight) {
                Text("Off").tag(0)
                Text("Low").tag(1)
                Text("Medium").tag(2)
                Text("High").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!laptop.state.lighting || laptop.state.kbd == nil)
            .accessibilityLabel("Keyboard light")
            Toggle("Slash lighting", isOn: $laptop.slashEnabled)
                .disabled(!laptop.state.lighting)
        }
    }
}
