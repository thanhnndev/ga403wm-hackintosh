// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation
import IOKit

enum ModeApplier {
    /// Returns an error text, or nil on success. Manual: the profile first (fresh firmware state), then the chosen firmware fan curves
    /// as custom curves (needed for power limits on this board), then the limits, kept in order SPL <= SPPT <= FPPT and in range.
    static func apply(_ plan: PowerPlan, state: AsusState) -> String? {
        var mode = plan.mode
        if mode == .turbo && !state.ac { mode = .performance }          // as Armoury Crate: no Turbo on battery
        guard mode == .manual else {
            return Asus.set(.profile, mode.firmwareProfile) == KERN_SUCCESS ? nil : "The performance profile was not applied."
        }
        guard Asus.set(.profile, PerformanceMode.performance.firmwareProfile) == KERN_SUCCESS else {
            return "The performance profile was not applied."
        }
        let base = plan.fanBase == .turbo && !state.ac ? PerformanceMode.performance : plan.fanBase
        for fan in 0..<2 {
            guard let curve = Asus.fanCurve(fan: fan, profile: base.firmwareProfile) else { return "The fan curve could not be read." }
            guard Asus.setFanCurve(fan: fan, curve) == KERN_SUCCESS else { return "The fan curve was refused." }
        }
        let ranges = state.ranges
        let spl = min(max(plan.spl, ranges[0].0), ranges[0].1)
        let sppt = min(max(max(plan.sppt, spl), ranges[1].0), ranges[1].1)
        let fppt = min(max(max(plan.fppt, sppt), ranges[2].0), ranges[2].1)
        for (setting, value) in [(Asus.Setting.spl, spl), (.sppt, sppt), (.fppt, fppt)] where Asus.set(setting, value) != KERN_SUCCESS {
            return "The \(value) W power limit was refused."
        }
        return nil
    }
}
