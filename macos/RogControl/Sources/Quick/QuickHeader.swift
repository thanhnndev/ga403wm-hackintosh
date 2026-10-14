// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

struct QuickHeader: View {
    let laptop: LaptopModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ROG Zephyrus G14")
                .font(.headline)
            Text(laptop.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
