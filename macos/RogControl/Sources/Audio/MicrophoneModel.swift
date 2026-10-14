// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Microphone checks: an 8 second level test, and a live "hear yourself" monitor (headphones only, speakers would feed back).
import Foundation
import Observation

@MainActor
@Observable
final class MicrophoneModel {
    enum Phase { case idle, testing, monitoring }

    private(set) var phase: Phase = .idle
    private(set) var level = -120.0
    private(set) var result = "Not tested"
    private(set) var error = ""
    var source: MicSource = .clear
    var monitorGain = 1.0

    @ObservationIgnored private let audio: AudioModel
    @ObservationIgnored private var process: ProbeProcess?
    @ObservationIgnored private var peak = -120.0

    init(audio: AudioModel) { self.audio = audio }

    var isBusy: Bool { phase != .idle }
    var isListening: Bool { phase == .monitoring }
    var isTesting: Bool { phase == .testing }

    /// ROG Clear Mic only delivers sound while it is enabled; the raw built-in mic is always available.
    var sourceAvailable: Bool { source == .builtin || audio.micEnabled }
    var canMonitor: Bool { sourceAvailable && audio.headphonesPlugged && ProbeProcess.isInstalled }
    var canTest: Bool { sourceAvailable && ProbeProcess.isInstalled }

    func toggleTest() {
        if phase == .testing { process?.stop(); return }
        guard canTest else { fail("Enable ROG Clear Mic first, or pick the built-in mic."); return }
        stopCurrent()
        begin(.testing, arguments: ["input", source.uid, "8"], status: "Listening") { [weak self] exit in
            guard let self else { return }
            if exit.wasSignalled { self.result = "Stopped" }
            else if exit.status != 0 { self.result = "Capture failed"; self.error = "The microphone test failed." }
            else { self.result = self.peak > -100 ? "Signal detected" : "No signal" }
        }
    }

    func toggleMonitor() {
        if phase == .monitoring { process?.stop(); return }
        guard audio.headphonesPlugged else {
            fail("Plug in headphones first. Monitoring through the speakers would feed back."); return
        }
        guard let output = AudioDevices.builtInOutputUID() else { fail("Built-in output not found."); return }
        stopCurrent()
        let label = source == .clear ? "Monitoring ROG Clear Mic" : "Monitoring the raw built-in mic"
        begin(.monitoring, arguments: ["monitor", source.uid, output, "600", String(monitorGain)], status: label) { [weak self] exit in
            guard let self else { return }
            let finishedCleanly = exit.wasSignalled || exit.status == 0
            self.result = finishedCleanly ? "Monitor stopped" : "Monitor failed. Is the microphone enabled?"
        }
    }

    /// Stops a running test or monitor, for example when the window closes.
    func stop() { process?.stop() }

    private func stopCurrent() {
        process?.stop()
        process = nil
        phase = .idle
    }

    private func begin(_ phase: Phase, arguments: [String], status: String, finished: @escaping @MainActor (ProbeProcess.Exit) -> Void) {
        guard ProbeProcess.isInstalled else { fail("The audio test helper is not installed."); return }
        level = -120
        peak = -120
        error = ""
        let probe = ProbeProcess(arguments: arguments, onLine: { [weak self] line in
            guard let value = ProbeProcess.level(in: line) else { return }
            Task { @MainActor in self?.receive(level: value) }
        }, onExit: { [weak self] exit in
            Task { @MainActor in
                guard let self else { return }
                self.phase = .idle
                self.process = nil
                finished(exit)
            }
        })
        do {
            try probe.start()
            process = probe
            self.phase = phase
            result = status
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func receive(level value: Double) {
        level = max(-120, min(0, value))
        peak = max(peak, level)
    }

    private func fail(_ message: String) {
        error = message
        result = "Not tested"
    }
}
