// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

enum AppPage: String, CaseIterable, Identifiable {
    case overview, performance, battery, lighting, sound, microphone, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .performance: "Performance"
        case .battery: "Battery"
        case .lighting: "Lighting"
        case .sound: "Speakers"
        case .microphone: "Microphone"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .performance: "gauge.with.dots.needle.50percent"
        case .battery: "battery.100"
        case .lighting: "keyboard"
        case .sound: "speaker.wave.2"
        case .microphone: "mic"
        case .settings: "gearshape"
        }
    }
}
