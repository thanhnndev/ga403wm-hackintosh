// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct PerformancePage: View {
    @Bindable var laptop: LaptopModel

    var body: some View {
        Form {
            Section {
                ModeSelector(laptop: laptop)
                    .padding(.vertical, 4)
                if !laptop.modeError.isEmpty { Notice(text: laptop.modeError, kind: .caution) }
            } header: {
                Text("Mode")
            } footer: {
                Text("Mode is remembered separately for AC and battery and applied when the power source changes.")
            }
            if laptop.activeMode == .manual || laptop.plan.mode == .manual {
                Section("Power limits") {
                    ValueSlider(title: "Sustained (SPL)", value: $laptop.splWatts, range: laptop.limitRanges[0]) { "\(Int($0)) W" }
                    ValueSlider(title: "Slow boost (SPPT)", value: $laptop.spptWatts, range: laptop.limitRanges[1]) { "\(Int($0)) W" }
                    ValueSlider(title: "Fast boost (FPPT)", value: $laptop.fpptWatts, range: laptop.limitRanges[2]) { "\(Int($0)) W" }
                    Picker("Fan curve", selection: $laptop.fanBase) {
                        ForEach([PerformanceMode.silent, .performance, .turbo]) { Text($0.title).tag($0) }
                    }
                    LabeledContent(laptop.hasUnappliedLimits ? "Changes are not applied yet"
                                   : "Applied: " + laptop.state.ppt.map { "\($0) W" }.joined(separator: " / ")) {
                        Button("Apply Limits") { laptop.applyLimits() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!laptop.hasUnappliedLimits)
                    }
                }
            }
            Section("Fan curve") {
                FanCurveView(laptop: laptop)
                    .padding(.vertical, 4)
            }
            Section("Graphics") {
                LabeledContent("Mode", value: laptop.graphicsTitle)
                if laptop.state.baseTgp > 0 { LabeledContent("GPU base power", value: "\(laptop.state.baseTgp) W") }
            }
        }
        .disabled(!laptop.isAvailable)
        .overlay {
            if !laptop.isAvailable {
                ContentUnavailableView("Driver not loaded", systemImage: "exclamationmark.triangle",
                                       description: Text("The AsusWmi kext is not loaded, so power controls are unavailable."))
            }
        }
    }
}
