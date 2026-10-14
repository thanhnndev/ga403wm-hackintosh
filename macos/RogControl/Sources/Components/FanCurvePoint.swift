// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

struct FanCurvePoint: Identifiable {
    let id: Int
    let temperature: Int
    let duty: Int
    let segment: Int
}

/// The firmware's 8 temperature / duty pairs. Raw data can hold 255 endpoints or repeated temperatures; points outside the valid
/// range or order are skipped and counted, never extrapolated or replaced.
struct FanCurveData {
    let points: [FanCurvePoint]
    let omitted: Int

    init(_ bytes: [UInt8]) {
        guard bytes.count == 16 else { points = []; omitted = bytes.isEmpty ? 0 : 8; return }
        var valid: [FanCurvePoint] = []
        var skipped = 0
        var segment = 0
        var previous: Int?
        for index in 0..<8 {
            let temperature = Int(bytes[index])
            let duty = Int(bytes[8 + index])
            guard (20...105).contains(temperature), (0...100).contains(duty), previous.map({ temperature >= $0 }) ?? true else {
                skipped += 1
                segment += 1
                continue
            }
            valid.append(FanCurvePoint(id: index, temperature: temperature, duty: duty, segment: segment))
            previous = temperature
        }
        points = valid
        omitted = skipped
    }
}
