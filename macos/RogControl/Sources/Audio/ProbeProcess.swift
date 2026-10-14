// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Runs the unsigned rogaudio-probe helper. It must stay unsigned: macOS feeds zeros to ad-hoc signed command line audio clients.
import Foundation

final class ProbeProcess: @unchecked Sendable {
    static let executable = URL(fileURLWithPath: "/Library/Application Support/RogAudio/rogaudio-probe")
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    struct Exit: Sendable {
        let status: Int32
        let wasSignalled: Bool
    }

    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var buffer = ""

    /// `onLine` and `onExit` are called on a background queue.
    init(arguments: [String], onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Exit) -> Void) {
        process.executableURL = Self.executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.split(String(decoding: data, as: UTF8.self), onLine)
        }
        process.terminationHandler = { [pipe] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            onExit(Exit(status: process.terminationStatus, wasSignalled: process.terminationReason == .uncaughtSignal))
        }
    }

    private func split(_ chunk: String, _ onLine: @Sendable (String) -> Void) {
        let lines: [String] = lock.withLock {
            buffer += chunk
            var complete: [String] = []
            while let newline = buffer.firstIndex(of: "\n") {
                complete.append(String(buffer[..<newline]))
                buffer.removeSubrange(...newline)
            }
            return complete
        }
        lines.forEach(onLine)
    }

    func start() throws { try process.run() }
    func stop() { if process.isRunning { process.terminate() } }

    /// The `dBFS=` value of a `progress ...` line, if the line is one.
    static func level(in line: String) -> Double? {
        guard line.hasPrefix("progress ") else { return nil }
        for field in line.split(separator: " ") where field.hasPrefix("dBFS=") {
            if let value = Double(field.dropFirst(5)), value.isFinite { return value }
        }
        return nil
    }
}
