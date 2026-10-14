// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Start at login through a user LaunchAgent (no signing needed).
import Foundation

enum LoginItem {
    static let label = "com.itlmt7925.RogControl"

    private static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func set(_ enabled: Bool) {
        guard enabled else { try? FileManager.default.removeItem(at: plist); return }
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let contents: [String: Any] = ["Label": label, "ProgramArguments": [executable, "--background"], "RunAtLoad": true,
                                       "ProcessType": "Interactive", "LimitLoadToSessionType": "Aqua"]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (contents as NSDictionary).write(to: plist, atomically: true)
    }
}
