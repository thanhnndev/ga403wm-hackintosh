// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct PageContent: View {
    @Environment(AppModel.self) private var app
    let page: AppPage

    var body: some View {
        Group {
            switch page {
            case .overview: OverviewPage(laptop: app.laptop, audio: app.audio)
            case .performance: PerformancePage(laptop: app.laptop)
            case .battery: BatteryPage(laptop: app.laptop)
            case .lighting: LightingPage(laptop: app.laptop)
            case .sound: NavigationStack { SpeakersPage(audio: app.audio, tests: app.speakerTests) }
            case .microphone: MicrophonePage(audio: app.audio, microphone: app.microphone)
            case .settings: SettingsPage(laptop: app.laptop)
            case .about: AboutPage()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
    }
}
