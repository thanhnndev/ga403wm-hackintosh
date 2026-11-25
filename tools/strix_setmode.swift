// Switch the main display to 1440x900 HiDPI at <hz> (60 or 120) through a CG display configuration transaction.
// CGDisplaySetDisplayMode() returns success but is ignored here; only the configuration transaction applies it.
// Build: swiftc -O tools/strix_setmode.swift -o /tmp/setmode   Run: /tmp/setmode 60
import CoreGraphics
let d = CGMainDisplayID()
let hz = Double(CommandLine.arguments[1])!
let ms = CGDisplayCopyAllDisplayModes(d, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as! [CGDisplayMode]
guard let m = ms.first(where: { $0.width == 1440 && abs($0.refreshRate - hz) < 0.5 && $0.pixelWidth == 2880 }) else { print("no"); exit(1) }
var cfg: CGDisplayConfigRef?
print("begin", CGBeginDisplayConfiguration(&cfg).rawValue)
print("conf", CGConfigureDisplayWithDisplayMode(cfg, d, m, nil).rawValue)
print("complete", CGCompleteDisplayConfiguration(cfg, .forSession).rawValue)
