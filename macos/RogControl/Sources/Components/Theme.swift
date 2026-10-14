// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// One accent (ROG red) marks the selection and the primary action. Text, surfaces and separators come from the system, so light,
// dark and increased contrast all follow the Mac. Orange is reserved for cautions, so a warning is never mistaken for a selection.
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.89, green: 0.09, blue: 0.22)
    static let caution = Color.orange

    enum Radius {
        static let control: CGFloat = 10
    }
}
