import CoreGraphics

let target = CGMainDisplayID()
if let modes = CGDisplayCopyAllDisplayModes(target, nil) as? [CGDisplayMode] {
    var seen = Set<String>()
    for m in modes {
        let key = "\(m.width)x\(m.height)@\(m.refreshRate)"
        if seen.insert(key).inserted {
            print(key)
        }
    }
} else {
    print("no modes")
}
