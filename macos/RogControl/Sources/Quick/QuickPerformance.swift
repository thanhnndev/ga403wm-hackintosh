// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickPerformance: View {
    let laptop: LaptopModel

    var body: some View {
        QuickSection(title: "Performance", symbol: "gauge.with.dots.needle.50percent") {
            ModeSelector(laptop: laptop, isCompact: true)
            if let mode = laptop.activeMode {
                Text(mode.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !laptop.modeError.isEmpty {
                Notice(text: laptop.modeError, kind: .caution)
            }
        }
    }
}
