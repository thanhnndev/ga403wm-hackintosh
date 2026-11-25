// Restore only the known OLED's native-backing HiDPI mode after its EDID arrives.
// No raster/timing changes, HDMI selection or WindowServer restart.
import CoreGraphics
import Foundation

let agent = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/dev.thanhnndev.890m-display-restore.plist")
func matches(_ m: CGDisplayMode) -> Bool {
    m.width == 1440 && m.height == 900 && m.pixelWidth == 2880 && m.pixelHeight == 1800 &&
    abs(m.refreshRate - 120) < 0.5 && m.isUsableForDesktopGUI()
}
func done() {
    try? FileManager.default.removeItem(at: agent)
    print("OLED 1440x900 HiDPI / 2880x1800 at 120 Hz restored; one-shot agent removed")
}
for _ in 0..<90 {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    if CGGetOnlineDisplayList(16, &ids, &count) == .success {
        let panels = ids.prefix(Int(count)).filter {
            CGDisplayVendorNumber($0) == 0x4c83 && CGDisplayModelNumber($0) == 0x419c &&
            CGDisplayIsBuiltin($0) != 0
        }
        if panels.count == 1, let id = panels.first, let current = CGDisplayCopyDisplayMode(id) {
            // Refuse another scanout geometry: never ask the fixed-mode bridge to scale/modeset.
            if current.pixelWidth != 2880 || current.pixelHeight != 1800 {
                print("OLED backing differs from reviewed native geometry; unchanged"); exit(2)
            }
            if matches(current) { done(); exit(0) }
            let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
            if let target = modes.first(where: matches) {
                var config: CGDisplayConfigRef?
                if CGBeginDisplayConfiguration(&config) == .success {
                    let r = CGConfigureDisplayWithDisplayMode(config, id, target, nil)
                    if r == .success {
                        let result = CGCompleteDisplayConfiguration(config, .permanently)
                        if result == .success, let actual = CGDisplayCopyDisplayMode(id), matches(actual) {
                            done(); exit(0)
                        }
                        print("OLED HiDPI selection not confirmed: \(result.rawValue)"); exit(3)
                    }
                    CGCancelDisplayConfiguration(config)
                    print("OLED HiDPI configuration refused: \(r.rawValue)"); exit(4)
                }
            }
        }
    }
    sleep(1)
}
print("Known OLED/usable native-backing 120 Hz HiDPI mode not ready; no mode changed")
exit(1)
