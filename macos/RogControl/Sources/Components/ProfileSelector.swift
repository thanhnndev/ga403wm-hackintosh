// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// The five sound profiles as one row of tiles, with the selected profile described underneath.
struct ProfileSelector: View {
    @Bindable var audio: AudioModel
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(SoundProfile.allCases) { profile in
                    SelectableTile(isSelected: audio.profile == profile) {
                        audio.profile = profile
                    } content: {
                        VStack(spacing: 6) {
                            Image(systemName: profile.symbol)
                                .font(isCompact ? .body : .title2)
                                .foregroundStyle(audio.profile == profile ? Theme.accent : Color.primary)
                                .frame(height: isCompact ? 20 : 26)
                            Text(profile.title)
                                .font(.caption)
                                .fontWeight(audio.profile == profile ? .semibold : .regular)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityLabel(profile.title)
                    .accessibilityHint(profile.detail)
                    .help(profile.detail)
                }
            }
            Text(audio.profile.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
