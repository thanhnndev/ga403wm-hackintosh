// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

private struct KeepsModelFresh: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .onAppear { app.watchers += 1 }
            .onDisappear { app.watchers = max(0, app.watchers - 1) }
    }
}

extension View {
    /// While this view is on screen the model polls every 2 seconds instead of every 30.
    func keepsModelFresh() -> some View { modifier(KeepsModelFresh()) }
}
