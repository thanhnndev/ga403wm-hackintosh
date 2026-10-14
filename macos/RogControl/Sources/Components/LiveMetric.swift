// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Charts
import SwiftUI

/// One live reading: a large value, its unit, and a one minute sparkline when history is available.
struct LiveMetric: View {
    let title: String
    let value: String
    var unit: String?
    let symbol: String
    var history: [TelemetrySample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(.callout).foregroundStyle(.secondary)
                }
            }
            if history.count > 2 {
                Chart(history) { sample in
                    LineMark(x: .value("Sample", sample.id), y: .value(title, sample.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 28)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value) \(unit ?? "")")
    }
}
