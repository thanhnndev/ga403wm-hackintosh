// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

/// The chosen mode and manual limits for one power source, kept in UserDefaults as "ac.mode", "battery.spl", ...
struct PowerPlan: Equatable {
    var mode: PerformanceMode
    var spl: Int
    var sppt: Int
    var fppt: Int
    /// Whose firmware fan curve Manual uses (silent, performance or turbo).
    var fanBase: PerformanceMode

    static func load(onAC: Bool) -> PowerPlan {
        let defaults = UserDefaults.standard
        let prefix = onAC ? "ac." : "battery."
        func integer(_ name: String, _ fallback: Int) -> Int {
            defaults.object(forKey: prefix + name) == nil ? fallback : defaults.integer(forKey: prefix + name)
        }
        return PowerPlan(mode: PerformanceMode(rawValue: defaults.string(forKey: prefix + "mode") ?? "") ?? .performance,
                         spl: integer("spl", onAC ? 45 : 30), sppt: integer("sppt", onAC ? 65 : 35), fppt: integer("fppt", onAC ? 80 : 50),
                         fanBase: PerformanceMode(rawValue: defaults.string(forKey: prefix + "fanBase") ?? "") ?? .performance)
    }

    func save(onAC: Bool) {
        let defaults = UserDefaults.standard
        let prefix = onAC ? "ac." : "battery."
        defaults.set(mode.rawValue, forKey: prefix + "mode")
        defaults.set(spl, forKey: prefix + "spl")
        defaults.set(sppt, forKey: prefix + "sppt")
        defaults.set(fppt, forKey: prefix + "fppt")
        defaults.set(fanBase.rawValue, forKey: prefix + "fanBase")
    }
}
