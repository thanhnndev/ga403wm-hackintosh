// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// The menu bar panel: everything used day to day on one page, no tabs. Power first, then sound, microphone and lighting.
import SwiftUI

struct QuickPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuickHeader(laptop: app.laptop)
            QuickPerformance(laptop: app.laptop)
            QuickTelemetry(laptop: app.laptop)
            Divider()
            QuickSound(audio: app.audio)
            QuickMicrophone(audio: app.audio, microphone: app.microphone)
            Divider()
            QuickLighting(laptop: app.laptop)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .tint(Theme.accent)
        .keepsModelFresh()
    }

    private var footer: some View {
        HStack {
            Button("Open ROG Control") {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
            Spacer()
            Menu {
                Toggle("Open at Login", isOn: Bindable(app.laptop).startsAtLogin)
                Divider()
                Button("Quit ROG Control") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }
}
