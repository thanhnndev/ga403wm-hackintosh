// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// RogAudio settings. They live in a plist shared with the root strixampctl and the user rogaudiod daemons; both write back a
// status plist that this model reads to say whether the settings are applied (see docs/AUDIO-ROG.md).
import Foundation
import IOKit
import Observation

@MainActor
@Observable
final class AudioModel {
    var profile: SoundProfile { didSet { scheduleSave() } }
    /// Amp volume in dB, -60...0.
    var volume: Double { didSet { scheduleSave() } }
    var isMuted: Bool { didSet { scheduleSave() } }
    var noiseCancellation: Bool { didSet { scheduleSave() } }
    /// 0...100 percent.
    var noiseStrength: Double { didSet { scheduleSave() } }
    var micEnabled: Bool { didSet { scheduleSave() } }

    private(set) var ampState = "Unavailable"
    private(set) var micState = "Unavailable"
    private(set) var firmware = "Unavailable"
    private(set) var isConnected = false
    private(set) var isApplied = false
    private(set) var headphonesPlugged = false
    private(set) var error = ""

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RogAudio")

    private var settingsURL: URL { directory.appendingPathComponent("settings.plist") }

    init() {
        let stored = Self.readPlist(directory.appendingPathComponent("settings.plist")) ?? [:]
        profile = SoundProfile(rawValue: stored["profile"] as? String ?? "") ?? .balanced
        volume = min(0, max(-60, stored["volume"] as? Double ?? -20))
        isMuted = stored["muted"] as? Bool ?? false
        noiseCancellation = stored["noiseCancellation"] as? Bool ?? true
        micEnabled = stored["micEnabled"] as? Bool ?? false
        noiseStrength = min(100, max(0, (stored["strength"] as? Double ?? 1) * 100))
        save()
        refresh()
    }

    // ---- persistence --------------------------------------------------------------------------------------------------------
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes the settings now. The daemons pick the file up within a second.
    func save() {
        saveTask?.cancel()
        let contents: [String: Any] = ["profile": profile.rawValue, "volume": min(0, max(-60, volume)), "muted": isMuted,
                                       "noiseCancellation": noiseCancellation, "micEnabled": micEnabled,
                                       "strength": min(1, max(0, noiseStrength / 100))]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: settingsURL, options: .atomic)
            error = ""
            isApplied = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    // ---- status -------------------------------------------------------------------------------------------------------------
    func refresh() {
        let amp = Self.readPlist(URL(fileURLWithPath: "/var/run/strixamp-status.plist"))
        let dsp = Self.readPlist(directory.appendingPathComponent("status.plist"))
        let ampLive = amp.map(Self.isFresh) ?? false
        let dspLive = dsp.map(Self.isFresh) ?? false
        isConnected = ampLive && dspLive
        ampState = ampLive ? ((amp?["state"] as? Int == 2) ? "Ready" : "Starting") : "Unavailable"
        micState = !dspLive ? "Unavailable" : !micEnabled ? "Disabled" : ((dsp?["micActive"] as? Bool == true) ? "Active" : "On demand")
        firmware = Self.amplifierDescription()

        let strength = noiseCancellation ? noiseStrength / 100 : 0
        let ampMatches = ampLive && amp?["state"] as? Int == 2 && amp?["muted"] as? Bool == isMuted
            && abs((amp?["volume"] as? Double ?? 1) - volume) < 0.1
        let dspMatches = dspLive && dsp?["profile"] as? String == profile.rawValue
            && (dsp?["micEnabled"] as? Bool ?? false) == micEnabled
            && abs((dsp?["strength"] as? Double ?? -1) - strength) < 0.002
        isApplied = ampMatches && dspMatches
        headphonesPlugged = AudioDevices.headphonesPlugged()
    }

    var statusTitle: String {
        if !isConnected { return "Audio services not running" }
        return isApplied ? "Applied" : "Applying"
    }

    // ---- helpers ------------------------------------------------------------------------------------------------------------
    private static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func isFresh(_ status: [String: Any]) -> Bool {
        guard let timestamp = status["updated"] as? Double else { return false }
        return abs(Date().timeIntervalSince1970 - timestamp) < 12
    }

    private static func amplifierDescription() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("StrixAmp"))
        guard service != 0 else { return "Unavailable" }
        defer { IOObjectRelease(service) }
        let identifier = IORegistryEntryCreateCFProperty(service, "SpeakerId" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber
        return identifier.map { "CS35L56 B0, speaker ID \($0.intValue)" } ?? "CS35L56 B0"
    }
}
