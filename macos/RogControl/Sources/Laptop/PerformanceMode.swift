// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable {
    case silent, performance, turbo, manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silent: "Silent"
        case .performance: "Performance"
        case .turbo: "Turbo"
        case .manual: "Manual"
        }
    }

    var caption: String {
        switch self {
        case .silent: "Quiet and cool"
        case .performance: "Balanced for everyday work"
        case .turbo: "Maximum power, on AC only"
        case .manual: "Your own power limits"
        }
    }

    var symbol: String {
        switch self {
        case .silent: "leaf"
        case .performance: "gauge.with.dots.needle.50percent"
        case .turbo: "flame"
        case .manual: "slider.horizontal.3"
        }
    }

    /// asus-wmi throttle_thermal_policy: 0 balanced, 1 overboost, 2 silent.
    var firmwareProfile: Int {
        switch self {
        case .silent: 2
        case .turbo: 1
        case .performance, .manual: 0
        }
    }

    static func from(profile: Int?) -> PerformanceMode? {
        switch profile {
        case 0: .performance
        case 1: .turbo
        case 2: .silent
        default: nil
        }
    }
}
