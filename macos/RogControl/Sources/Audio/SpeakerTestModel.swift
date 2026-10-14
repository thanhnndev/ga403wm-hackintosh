// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Plays the bundled test files to the built-in output (raw hardware) or to ROG Speakers (through the DSP).
import AVFoundation
import Observation

@MainActor
@Observable
final class SpeakerTestModel {
    private(set) var tests: [SpeakerTest] = []
    private(set) var playing: String?
    private(set) var progress = 0.0
    private(set) var heard: Set<String>
    private(set) var error = ""
    var target: PlaybackTarget = .direct

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    private static let heardKey = "audio.heard"
    private static var directory: URL? { Bundle.main.resourceURL?.appendingPathComponent("AudioTest") }

    init() {
        heard = Set(UserDefaults.standard.stringArray(forKey: Self.heardKey) ?? [])
        guard let directory = Self.directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let items = try? JSONDecoder().decode([SpeakerTest].self, from: data) else { return }
        tests = items.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path) }
    }

    var groups: [(name: String, tests: [SpeakerTest])] {
        let order = ["Overview", "Quality", "Cinema", "Drivers"]
        let names = order.filter { name in tests.contains { $0.group == name } }
            + Set(tests.map(\.group)).subtracting(order).sorted()
        return names.map { name in (name, tests.filter { $0.group == name }) }
    }

    func toggleHeard(_ test: SpeakerTest) {
        if heard.contains(test.file) { heard.remove(test.file) } else { heard.insert(test.file) }
        UserDefaults.standard.set(Array(heard), forKey: Self.heardKey)
    }

    func stop() {
        player?.stop()
        player = nil
        progressTask?.cancel()
        progressTask = nil
        playing = nil
        progress = 0
    }

    /// Plays one file, or stops it when it is already playing.
    @discardableResult
    func toggle(_ test: SpeakerTest) -> Bool {
        if playing == test.file { stop(); return true }
        stop()
        guard let directory = Self.directory else { error = "The test files are missing from the app."; return false }
        guard let uid = AudioDevices.outputUID(for: target) else {
            error = target == .direct ? "Built-in output not found." : "ROG Speakers device not found."
            return false
        }
        do {
            let player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(test.file))
            player.currentDevice = uid
            player.volume = 1
            guard player.prepareToPlay(), player.play() else { error = "Playback could not start."; return false }
            self.player = player
            playing = test.file
            error = ""
            track(player)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func track(_ player: AVAudioPlayer) {
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.player === player else { return }
                if player.isPlaying { self.progress = player.duration > 0 ? player.currentTime / player.duration : 0 } else { self.stop(); return }
            }
        }
    }
}
