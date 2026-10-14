// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import SwiftUI

/// An inline message: an icon and words on a tinted surface with a full hairline border. Status never relies on colour alone.
struct Notice: View {
    enum Kind { case info, caution }

    let text: String
    var kind: Kind = .info

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind == .caution ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(kind == .caution ? Theme.caution : Color.secondary)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((kind == .caution ? Theme.caution : Color.secondary).opacity(0.1), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
    }
}
