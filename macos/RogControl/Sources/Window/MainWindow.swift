// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct MainWindow: View {
    @SceneStorage("window.page") private var page: AppPage = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section("Laptop") {
                    row(.overview)
                    row(.performance)
                    row(.battery)
                    row(.lighting)
                }
                Section("Audio") {
                    row(.sound)
                    row(.microphone)
                }
                Section {
                    row(.settings)
                    row(.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            PageContent(page: page)
        }
        .frame(minWidth: 840, minHeight: 560)
        .tint(Theme.accent)
        .keepsModelFresh()
    }

    private func row(_ page: AppPage) -> some View {
        Label(page.title, systemImage: page.symbol).tag(page)
    }
}
