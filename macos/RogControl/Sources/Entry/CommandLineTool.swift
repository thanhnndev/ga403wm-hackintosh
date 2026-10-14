// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Headless modes of the same binary. `run` returns an exit status, or nil when the arguments ask for the app.
import Foundation
import IOKit

@MainActor
enum CommandLineTool {
    static func run(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 2 else { return nil }
        switch arguments[1] {
        case "--audio-play": return arguments.count >= 3 ? play(file: arguments[2], target: arguments.dropFirst(3).first) : 2
        case "--audio-mic-test": return micTest(source: arguments.dropFirst(2).first)
        case "--audio-status", "--audio-set": return audio(arguments)
        case "--bench": return bench(seconds: arguments.count >= 3 ? max(5, Int(arguments[2]) ?? 20) : 20)
        default: return nil
        }
    }

    private static func pump(until condition: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    }

    private static func play(file: String, target: String?) -> Int32 {
        let tests = SpeakerTestModel()
        tests.target = target == "dsp" ? .dsp : .direct
        guard let test = tests.tests.first(where: { $0.file == file }) else { print("unknown test file"); return 2 }
        guard tests.toggle(test) else { print("play failed: \(tests.error)"); return 1 }
        print("playing \(test.file) via \(tests.target.rawValue)")
        pump(until: { tests.playing != nil }, timeout: test.seconds + 5)
        return 0
    }

    private static func micTest(source: String?) -> Int32 {
        let audio = AudioModel()
        let mic = MicrophoneModel(audio: audio)
        mic.source = source == "builtin" ? .builtin : .clear
        mic.toggleTest()
        pump(until: { mic.isBusy }, timeout: 10)
        print("Mic test: \(mic.result), level \(mic.level) dBFS, error \(mic.error)")
        return mic.result == "Signal detected" && mic.error.isEmpty ? 0 : 1
    }

    private static func audio(_ arguments: [String]) -> Int32 {
        let audio = AudioModel()
        if arguments[1] == "--audio-set" {
            guard arguments.count == 7, SoundProfile(rawValue: arguments[2]) != nil,
                  let volume = Double(arguments[3]), volume.isFinite, (-60...0).contains(volume),
                  ["0", "1"].contains(arguments[4]), ["0", "1"].contains(arguments[5]),
                  let strength = Double(arguments[6]), strength.isFinite, (0...100).contains(strength) else {
                print("usage: RogControl --audio-set PROFILE VOLUME_DB MUTE_0_1 NOISE_0_1 STRENGTH_PERCENT")
                return 2
            }
            audio.profile = SoundProfile(rawValue: arguments[2]) ?? .balanced
            audio.volume = volume
            audio.isMuted = arguments[4] == "1"
            audio.noiseCancellation = arguments[5] == "1"
            audio.noiseStrength = strength
            audio.save()
            Thread.sleep(forTimeInterval: 4)
            audio.refresh()
        }
        print("Audio: \(audio.isApplied ? "Applied" : "Pending"), amps \(audio.ampState), mic \(audio.micState), "
              + "profile \(audio.profile.rawValue), volume \(audio.volume), mute \(audio.isMuted), "
              + "noise \(audio.noiseCancellation), strength \(audio.noiseStrength)")
        return audio.error.isEmpty ? 0 : 1
    }

    // ---- bench --------------------------------------------------------------------------------------------------------------
    private final class Load: @unchecked Sendable {
        private let lock = NSLock()
        private var running = true

        func start(threads: Int) {
            for _ in 0..<threads {
                Thread.detachNewThread { [self] in
                    var x: UInt64 = 88172645463325252
                    while lock.withLock({ running }) {
                        for _ in 0..<200_000 { x ^= x << 13; x ^= x >> 7; x ^= x << 17 }
                    }
                    if x == 42 { print("") }
                }
            }
        }

        func stop() { lock.withLock { running = false } }
    }

    private static func bench(seconds: Int) -> Int32 {
        let initial = Asus.state()
        guard initial.present else { print("AsusWmi is not loaded"); return 1 }
        let threads = ProcessInfo.processInfo.activeProcessorCount
        print("RogControl bench: \(threads) busy threads, \(seconds) s per mode, \(initial.ac ? "on AC" : "on battery"); "
              + "previous profile \(initial.profile.map(String.init) ?? "?")")
        print("mode         avg W   max W   Tctl max   CPU fan   GPU fan   Zen5 MHz   Zen5c MHz")
        var modes: [PerformanceMode] = [.silent, .performance]
        if initial.ac { modes.append(.turbo) }
        for mode in modes {
            guard Asus.set(.profile, mode.firmwareProfile) == KERN_SUCCESS else { print("\(mode.title): profile refused"); continue }
            Thread.sleep(forTimeInterval: 3)                    // let the firmware settle
            let load = Load()
            load.start(threads: threads)
            _ = Sensors.read()
            var samples: [Double] = []
            var hottest = 0.0, cpuFan = 0, gpuFan = 0
            for second in 0..<seconds {
                Thread.sleep(forTimeInterval: 1)
                let reading = Sensors.read()
                if second >= 2, let watts = reading.watts { samples.append(watts) }     // skip the first seconds of the fast boost
                hottest = max(hottest, reading.temperature ?? 0)
                let state = Asus.state()
                cpuFan = max(cpuFan, state.cpuFan)
                gpuFan = max(gpuFan, state.gpuFan)
            }
            let clocks = Sensors.clocks()
            load.stop()
            let average = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
            print(String(format: "%-11@ %6.1f  %6.1f   %6.1f°C   %7d   %7d   %8d   %9d", mode.title as NSString, average,
                         samples.max() ?? 0, hottest, cpuFan, gpuFan, clocks?.big ?? 0, clocks?.little ?? 0))
            Thread.sleep(forTimeInterval: 5)                    // cool down between modes
        }
        if let profile = initial.profile { Asus.set(.profile, profile) }
        print("previous profile restored (custom fan curves and power limits, if any, are reset; RogControl re-applies its mode at the next power change or start)")
        return 0
    }
}
