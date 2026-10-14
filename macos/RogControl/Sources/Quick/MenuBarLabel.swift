// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// The menu bar icon follows the active performance mode.
struct MenuBarLabel: View {
    let laptop: LaptopModel

    var body: some View {
        Image(systemName: laptop.activeMode?.symbol ?? "bolt.slash")
            .accessibilityLabel("ROG Control, \(laptop.activeMode?.title ?? "unavailable")")
    }
}
