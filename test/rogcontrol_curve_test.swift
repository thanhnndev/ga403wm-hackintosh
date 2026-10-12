// SPDX-License-Identifier: BSD-3-Clause-Clear
// Run: bash scripts/test-rogcontrol.sh
import Foundation

let performance: [UInt8] = [47, 62, 65, 68, 70, 72, 74, 76, 1, 8, 13, 18, 22, 32, 39, 53]
let normal = FanCurveData(performance)
precondition(normal.points.count == 8 && normal.omitted == 0)
precondition(normal.points.first?.temperature == 47 && normal.points.last?.duty == 53)

// Real GA403WM Turbo firmware endpoint: never plot 255°C or clamp it to 105°C.
let turbo = FanCurveData([43, 68, 70, 72, 74, 76, 78, 255, 1, 6, 8, 13, 18, 22, 32, 32])
precondition(turbo.points.count == 7 && turbo.omitted == 1)
precondition(turbo.points.last?.temperature == 78)

// Repeated temperatures from the GPU firmware are meaningful, so keep them.
let gpu = FanCurveData([43, 67, 68, 70, 70, 70, 70, 255, 1, 6, 8, 13, 18, 22, 32, 32])
precondition(gpu.points.filter { $0.temperature == 70 }.count == 4)

// A bad interior sample must break the line instead of inventing a connection.
var gap = performance; gap[3] = 255
let interrupted = FanCurveData(gap)
precondition(interrupted.points[2].segment != interrupted.points[3].segment)

var badDuty = performance; badDuty[10] = 255
precondition(FanCurveData(badDuty).omitted == 1)
var descending = performance; descending[4] = 50
precondition(FanCurveData(descending).omitted == 1)
precondition(FanCurveData([]).points.isEmpty)
precondition(FanCurveData([1, 2, 3]).points.isEmpty)
precondition(FanCurveData(Array(repeating: 255, count: 16)).points.isEmpty)
print("Fan curve tests passed: real firmware, sentinel, duplicates, gaps, invalid duty, ordering, short/empty data.")
