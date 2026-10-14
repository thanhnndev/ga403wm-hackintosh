// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

/// Slash lighting (asuswmi_abi.h ASUS_SLASH_*): animation index, brightness 0..3 (0 is off), interval 0..5.
struct Slash: Equatable {
    static let animations = ["Static", "Bounce", "Slash", "Loading", "Bit Stream", "Transmission", "Flow", "Flux",
                             "Phantom", "Spectrum", "Hazard", "Interfacing", "Ramp", "Game Over", "Start", "Buzzer"]

    var animation = 2
    var brightness = 2
    var interval = 0

    var packed: Int { animation | (brightness << 8) | (interval << 12) }

    init() {}

    init(packed value: Int) {
        animation = value & 0xff
        brightness = (value >> 8) & 0xf
        interval = (value >> 12) & 0xf
    }
}
