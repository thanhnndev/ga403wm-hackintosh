// Display arrangement probe.
//   swift tools/890m/display-arrangement.swift list
//   swift tools/890m/display-arrangement.swift save  [permanent]
//   swift tools/890m/display-arrangement.swift main  [permanent]   -- built-in panel at 0,0 (main display)
//   swift tools/890m/display-arrangement.swift side  [permanent]   -- external at 0,0, built-in to its right
//   swift tools/890m/display-arrangement.swift restore [permanent]
//
// The saved layout is keyed by ROLE (built-in vs external ordinal), not by CGDirectDisplayID: the IDs change on
// every boot (0x20d06706 one boot, 0x20d06700 the next), and an ID-keyed restore silently matched nothing.
import CoreGraphics
import Foundation

let stateDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/890m")
let stateFile = stateDir.appendingPathComponent("arrangement.json").path

func online() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    _ = CGGetOnlineDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func role(_ id: CGDirectDisplayID, in ids: [CGDirectDisplayID]) -> String {
    let builtins = ids.filter { CGDisplayIsBuiltin($0) != 0 }
    let externals = ids.filter { CGDisplayIsBuiltin($0) == 0 }
    if CGDisplayIsBuiltin(id) != 0 { return "builtin\(builtins.firstIndex(of: id) ?? 0)" }
    return "external\(externals.firstIndex(of: id) ?? 0)"
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let m = CGDisplayCopyDisplayMode(id)
    return String(format: "id=0x%x role=%@ origin=(%d,%d) size=%dx%d main=%d mode=%dx%d px=%dx%d@%.0f",
                  id, role(id, in: online()), Int(b.origin.x), Int(b.origin.y),
                  Int(b.size.width), Int(b.size.height), CGDisplayIsMain(id),
                  m?.width ?? 0, m?.height ?? 0, m?.pixelWidth ?? 0, m?.pixelHeight ?? 0, m?.refreshRate ?? 0)
}

func list(_ tag: String) {
    print("== \(tag)")
    for id in online() { print("  " + describe(id)) }
}

var permanent = false

func apply(_ moves: [(CGDirectDisplayID, Int32, Int32)]) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
    for (id, x, y) in moves {
        let r = CGConfigureDisplayOrigin(cfg, id, x, y)
        if r != .success { print("  origin 0x\(String(id, radix: 16)) refused: \(r.rawValue)"); CGCancelDisplayConfiguration(cfg); return false }
    }
    let r = CGCompleteDisplayConfiguration(cfg, permanent ? .permanently : .forSession)
    if r != .success { print("  configuration refused: \(r.rawValue)"); return false }
    return true
}

func saveLayout() {
    let ids = online()
    var saved: [String: [String: Int]] = [:]
    for id in ids {
        let b = CGDisplayBounds(id)
        saved[role(id, in: ids)] = ["x": Int(b.origin.x), "y": Int(b.origin.y)]
    }
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: stateFile))
        print("  saved \(saved) -> \(stateFile)")
    }
}

permanent = CommandLine.arguments.dropFirst(2).first == "permanent"
let ids = online()
let builtin = ids.filter { CGDisplayIsBuiltin($0) != 0 }
let external = ids.filter { CGDisplayIsBuiltin($0) == 0 }

switch CommandLine.arguments.dropFirst().first ?? "list" {
case "list":
    list("online displays")
case "save":
    saveLayout()
    list("layout now")
case "main":
    guard let oled = builtin.first else { print("no built-in display"); exit(2) }
    saveLayout()
    var moves: [(CGDirectDisplayID, Int32, Int32)] = [(oled, 0, 0)]
    var x = Int32(CGDisplayBounds(oled).width)
    for id in external { moves.append((id, x, 0)); x += Int32(CGDisplayBounds(id).width) }
    if apply(moves) { list("after: built-in panel at 0,0 (main display)") } else { exit(3) }
case "side":
    guard let oled = builtin.first, let first = external.first else { print("need a built-in and an external display"); exit(2) }
    saveLayout()
    var moves: [(CGDirectDisplayID, Int32, Int32)] = [(first, 0, 0)]
    moves.append((oled, Int32(CGDisplayBounds(first).width), 0))
    var x = Int32(CGDisplayBounds(first).width) + Int32(CGDisplayBounds(oled).width)
    for id in external.dropFirst() { moves.append((id, x, 0)); x += Int32(CGDisplayBounds(id).width) }
    if apply(moves) { list("after: external at 0,0, built-in to its right") } else { exit(3) }
case "restore":
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
          let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Int]] else {
        print("no saved layout at \(stateFile) — run 'save' first"); exit(2)
    }
    var moves: [(CGDirectDisplayID, Int32, Int32)] = []
    for id in ids {
        if let o = saved[role(id, in: ids)], let x = o["x"], let y = o["y"] { moves.append((id, Int32(x), Int32(y))) }
        else { print("  no saved origin for \(role(id, in: ids)) — left where it is") }
    }
    if apply(moves) { list("restored") } else { exit(3) }
default:
    print("usage: list | save | main [permanent] | side [permanent] | restore [permanent]"); exit(2)
}
