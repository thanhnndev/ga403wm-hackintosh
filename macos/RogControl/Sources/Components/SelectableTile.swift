// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// A tappable tile for one-of-N choices. States: default, hover, pressed, focus (system ring), selected, disabled.
struct SelectableTile<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(isSelected ? Theme.accent : Color.primary.opacity(isHovering && isEnabled ? 0.28 : 0.12),
                                      lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(TilePressStyle())
        .onHover { isHovering = $0 }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return Theme.accent.opacity(0.12) }
        return Color.primary.opacity(isHovering && isEnabled ? 0.07 : 0.035)
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
