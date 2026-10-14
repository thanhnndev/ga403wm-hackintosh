// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// A titled slider with its current value in a fixed-width column, so the track does not move while dragging.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .accessibilityLabel(title)
                Text(format(value))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
        }
    }
}
