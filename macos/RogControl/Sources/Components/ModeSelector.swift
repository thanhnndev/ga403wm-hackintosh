// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// The four performance modes as one row of tiles. Turbo needs the AC adapter, as in Armoury Crate.
struct ModeSelector: View {
    let laptop: LaptopModel
    var isCompact = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PerformanceMode.allCases) { mode in
                let isUnavailable = mode == .turbo && !laptop.state.ac
                SelectableTile(isSelected: laptop.activeMode == mode) {
                    laptop.select(mode)
                } content: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.title2)
                            .foregroundStyle(laptop.activeMode == mode ? Theme.accent : Color.primary)
                            .frame(height: 26)
                        Text(mode.title)
                            .font(isCompact ? .caption : .callout)
                            .fontWeight(laptop.activeMode == mode ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if !isCompact {
                            Text(isUnavailable ? "Needs AC power" : mode.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .disabled(isUnavailable || !laptop.isAvailable)
                .accessibilityLabel(mode.title)
                .accessibilityHint(isUnavailable ? "Turbo needs the AC adapter" : mode.caption)
                .help(isUnavailable ? "Turbo needs the AC adapter" : mode.caption)
            }
        }
    }
}
