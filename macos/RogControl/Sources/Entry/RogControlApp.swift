// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct RogControlApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            QuickPanel()
                .environment(model)
        } label: {
            MenuBarLabel(laptop: model.laptop)
                .modifier(OpenWindowOnLaunch())
        }
        .menuBarExtraStyle(.window)

        Window("ROG Control", id: WindowID.main) {
            MainWindow()
                .environment(model)
        }
        .defaultSize(width: 980, height: 700)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

enum WindowID {
    static let main = "main"
}

/// Opens the window once when the app was started by hand; a login start (`--background`) stays in the menu bar.
private struct OpenWindowOnLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @State private var done = false

    func body(content: Content) -> some View {
        content.task {
            guard !done, !CommandLine.arguments.contains("--background") else { return }
            done = true
            openWindow(id: WindowID.main)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
