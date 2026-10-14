// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// RogControl: ROG Control Center for macOS on the GA403WM (ROG Zephyrus G14 2025). Performance modes and power limits, fan curves,
// charge limit, keyboard and Slash lighting, plus the RogAudio speaker profiles, microphone noise cancellation, speaker tests and
// live mic monitor. A menu bar panel for everyday use, a window for the rest.
//
// Inspired by asusctl / rog-control-center (asus-linux.org, Luke Jones and contributors, MPL-2.0); no code is taken from it.
// Talks to kexts/AsusWmi through its user client (ABI: kexts/AsusWmi/asuswmi_abi.h, no sudo) and reads the sysctl
// debug.amdcppc.sensors of kexts/AmdCppc.
//
// Command line (same binary):
//   RogControl --bench [seconds]       Silent, Performance and Turbo in turn under full load; prints power, Tctl, fans, clocks
//   RogControl --audio-play FILE [direct|dsp], --audio-mic-test [builtin|clear], --audio-status, --audio-set ...
//   RogControl --background            start in the menu bar without opening the window (the login item uses this)
// Build: scripts/build-rogcontrol.sh
import SwiftUI

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if let status = MainActor.assumeIsolated({ CommandLineTool.run(arguments) }) { exit(status) }
        MainActor.assumeIsolated { RogControlApp.main() }
    }
}
