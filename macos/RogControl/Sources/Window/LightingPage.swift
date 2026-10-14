// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct LightingPage: View {
    @Bindable var laptop: LaptopModel

    var body: some View {
        Form {
            Section("Keyboard") {
                Picker("Backlight", selection: $laptop.keyboardLight) {
                    Text("Off").tag(0)
                    Text("Low").tag(1)
                    Text("Medium").tag(2)
                    Text("High").tag(3)
                }
                .pickerStyle(.segmented)
                .disabled(laptop.state.kbd == nil)
            }
            Section {
                Toggle("Slash lighting", isOn: $laptop.slashEnabled)
                if laptop.slashEnabled {
                    Picker("Animation", selection: $laptop.slashAnimation) {
                        ForEach(Slash.animations.indices, id: \.self) { Text(Slash.animations[$0]).tag($0) }
                    }
                    Picker("Brightness", selection: $laptop.slashBrightness) {
                        Text("Low").tag(1)
                        Text("Medium").tag(2)
                        Text("High").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Picker("Interval", selection: $laptop.slashInterval) {
                        ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Slash")
            } footer: {
                Text("Fn+F4 also switches the Slash lighting on and off.")
            }
            if !laptop.lightingError.isEmpty {
                Section { Notice(text: laptop.lightingError, kind: .caution) }
            }
        }
        .disabled(!laptop.state.lighting)
    }
}
