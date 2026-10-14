// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AmdCppc sysctl sensors: "tctl=<m°C> pkg_mw=<mW>" (power averaged since the previous read) and the per-CPU clock report.
import Foundation

enum Sensors {
    struct Reading {
        var temperature: Double?   // °C
        var watts: Double?
    }

    private static func string(_ name: String) -> String? {
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length + 1)
        guard sysctlbyname(name, &buffer, &length, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func read() -> Reading {
        guard let report = string("debug.amdcppc.sensors") else { return Reading() }
        var reading = Reading()
        for pair in report.split(separator: " ") {
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let value = Double(parts[1]) else { continue }
            if parts[0] == "tctl", value > -1 { reading.temperature = value / 1000 }
            if parts[0] == "pkg_mw", value > 0 { reading.watts = value / 1000 }
        }
        return reading
    }

    /// Average effective MHz of the busy CPUs 0-7 (Zen 5) and 8-23 (Zen 5c) from debug.amdcppc.freq.
    static func clocks() -> (big: Int, little: Int)? {
        guard let report = string("debug.amdcppc.freq") else { return nil }
        var big: [Int] = [], little: [Int] = []
        for part in report.split(separator: "|").dropFirst() {
            let fields = part.split(separator: " ")
            guard fields.count >= 2, let cpu = Int(fields[0]) else { continue }
            let values = fields[1].split(separator: "/")
            guard values.count >= 2, let mhz = Int(values[0]), let busy = Int(values[1].dropLast()), busy >= 50 else { continue }
            if cpu < 8 { big.append(mhz) } else { little.append(mhz) }
        }
        func average(_ values: [Int]) -> Int { values.isEmpty ? 0 : values.reduce(0, +) / values.count }
        return (average(big), average(little))
    }
}
