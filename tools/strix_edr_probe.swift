// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Prints, per screen, what macOS thinks about EDR/HDR (NSScreen potential/current EDR headroom) plus the
// CoreDisplay info-dictionary keys that matter for HDR. Read-only, no root.
//   swiftc -O tools/strix_edr_probe.swift -o strix_edr_probe && ./strix_edr_probe
import AppKit
import CoreGraphics

for s in NSScreen.screens {
    print("screen \"\(s.localizedName)\" edr_current=\(s.maximumExtendedDynamicRangeColorComponentValue) " +
          "edr_potential=\(s.maximumPotentialExtendedDynamicRangeColorComponentValue) " +
          "edr_reference=\(s.maximumReferenceExtendedDynamicRangeColorComponentValue)")
}
typealias InfoFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
if let h = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW),
   let sym = dlsym(h, "CoreDisplay_DisplayCreateInfoDictionary") {
    let f = unsafeBitCast(sym, to: InfoFn.self)
    var n: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    CGGetOnlineDisplayList(8, &ids, &n)
    for i in 0..<Int(n) {
        print("display \(ids[i]) builtin=\(CGDisplayIsBuiltin(ids[i])) " +
              "pixels=\(CGDisplayPixelsWide(ids[i]))x\(CGDisplayPixelsHigh(ids[i]))")
        guard let d = f(ids[i])?.takeRetainedValue() as? [String: Any] else { continue }
        for k in ["IODisplayEDID", "IODisplayEDIDOriginal", "IODisplayConnectFlags", "IODisplayIsHDMISink",
                  "IODisplayAttributes", "DisplayProductID", "DisplayVendorID"] {
            if let v = d[k] { print("  \(k) = \(String("\(v)".prefix(160)))") }
        }
        for (k, v) in d where k.lowercased().contains("hdr") || k.lowercased().contains("edr") ||
                              k.lowercased().contains("dynamicrange") {
            print("  \(k) = \(v)")
        }
        if let m = CGDisplayCopyDisplayMode(ids[i]) {
            print("  mode \(m.width)x\(m.height) pixel \(m.pixelWidth)x\(m.pixelHeight) \(m.refreshRate) Hz")
        }
    }
}
