// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct SpeakerTestRow: View {
    let tests: SpeakerTestModel
    let test: SpeakerTest

    private var isPlaying: Bool { tests.playing == test.file }
    private var isHeard: Bool { tests.heard.contains(test.file) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                tests.toggle(test)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(isPlaying ? Theme.accent : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Stop \(test.title)" : "Play \(test.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(test.title)
                Text(test.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if isPlaying {
                    ProgressView(value: tests.progress)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Text("\(Int(test.seconds)) s")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                tests.toggleHeard(test)
            } label: {
                Image(systemName: isHeard ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isHeard ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isHeard ? "Marked as heard" : "Mark as heard")
            .accessibilityLabel("Heard")
            .accessibilityAddTraits(isHeard ? .isSelected : [])
        }
        .padding(.vertical, 2)
    }
}
