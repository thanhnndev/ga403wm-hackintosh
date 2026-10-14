// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Owns the domain models and the single polling loop. The loop runs every 2 s while the panel or the window is on screen and
// every 30 s otherwise, so a closed app costs almost nothing.
import Observation

@MainActor
@Observable
final class AppModel {
    let laptop = LaptopModel()
    let audio = AudioModel()
    let microphone: MicrophoneModel
    let speakerTests = SpeakerTestModel()

    /// Set by views that are currently on screen (see `View.keepsModelFresh()`).
    var watchers = 0 {
        didSet {
            if oldValue == 0, watchers > 0 { tick(); startPolling() }
        }
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        microphone = MicrophoneModel(audio: audio)
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.watchers > 0 ? 2 : 30
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        laptop.refresh()
        audio.refresh()
    }
}
