// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// Input level, -60 dBFS (empty) to 0 dBFS (full). The number is shown too, so the bar is never the only signal.
struct LevelMeter: View {
    let level: Double
    let isActive: Bool

    private var fraction: Double { min(1, max(0, (level + 60) / 60)) }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(barColor)
                            .frame(width: max(8, proxy.size.width * fraction))
                            .animation(.easeOut(duration: 0.12), value: fraction)
                    }
                }
            Text(level > -119 ? String(format: "%.0f dBFS", level) : "silent")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(level > -119 ? String(format: "%.0f decibels full scale", level) : "silent")
    }

    private var barColor: Color {
        guard isActive else { return .secondary }
        return fraction > 0.9 ? Theme.caution : Theme.accent
    }
}
