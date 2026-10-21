// Step58b: can WindowServer be moved onto the iGPU by making the built-in panel the main display?
// The OLED's pipe now belongs to NMXAccel (the accelerator on the GPU that owns the panel), and WindowServer still
// opens its display-pipe clients on NVAccel and reports "Unable to find display pipe" for the panel's framebuffer.
// On a two-GPU Mac the compositor follows the main display, so this probe moves the main display and back.
//   swift tools/890m/display-arrangement.swift list
//   swift tools/890m/display-arrangement.swift main      (built-in panel to 0,0; the other display to its right)
//   swift tools/890m/display-arrangement.swift restore   (origins saved by `main`)
import CoreGraphics
import Foundation

let stateFile = "/tmp/890m-arrangement.json"

func online() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    _ = CGGetOnlineDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let m = CGDisplayCopyDisplayMode(id)
    return String(format: "id=0x%x builtin=%d origin=(%d,%d) size=%dx%d main=%d mode=%dx%d px=%dx%d@%.0f",
                  id, CGDisplayIsBuiltin(id), Int(b.origin.x), Int(b.origin.y),
                  Int(b.size.width), Int(b.size.height), CGDisplayIsMain(id),
                  m?.width ?? 0, m?.height ?? 0, m?.pixelWidth ?? 0, m?.pixelHeight ?? 0, m?.refreshRate ?? 0)
}

func list(_ tag: String) {
    print("== \(tag)")
    for id in online() { print("  " + describe(id)) }
}

func apply(_ moves: [(CGDirectDisplayID, Int32, Int32)]) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
    for (id, x, y) in moves {
        let r = CGConfigureDisplayOrigin(cfg, id, x, y)
        if r != .success { print("  origin 0x\(String(id, radix: 16)) refused: \(r.rawValue)"); CGCancelDisplayConfiguration(cfg); return false }
    }
    let r = CGCompleteDisplayConfiguration(cfg, .forSession)
    if r != .success { print("  configuration refused: \(r.rawValue)"); return false }
    return true
}

let ids = online()
let builtin = ids.filter { CGDisplayIsBuiltin($0) != 0 }
let external = ids.filter { CGDisplayIsBuiltin($0) == 0 }

switch CommandLine.arguments.dropFirst().first ?? "list" {
case "list":
    list("online displays")
case "main":
    guard builtin.count == 1, external.count == 1, let oled = builtin.first, let hdmi = external.first else {
        print("need one built-in and one external display"); exit(2)
    }
    let before = Dictionary(uniqueKeysWithValues: ids.map { (String($0), CGDisplayBounds($0).origin) })
    if let data = try? JSONSerialization.data(withJSONObject: before.mapValues { ["x": Int($0.x), "y": Int($0.y)] }) {
        try? data.write(to: URL(fileURLWithPath: stateFile))
    }
    list("before")
    let w = Int32(CGDisplayBounds(oled).width)
    if apply([(oled, 0, 0), (hdmi, w, 0)]) { list("after (built-in panel at 0,0 = main display)") } else { exit(3) }
case "restore":
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
          let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Int]] else {
        print("no saved arrangement at \(stateFile)"); exit(2)
    }
    var moves: [(CGDirectDisplayID, Int32, Int32)] = []
    for id in ids {
        if let o = saved[String(id)], let x = o["x"], let y = o["y"] { moves.append((id, Int32(x), Int32(y))) }
    }
    if apply(moves) { list("restored") } else { exit(3) }
default:
    print("usage: list | main | restore"); exit(2)
}
