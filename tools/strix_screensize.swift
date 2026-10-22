import CoreGraphics

var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)
for id in ids.prefix(Int(count)) {
    let mm = CGDisplayScreenSize(id)
    let b = CGDisplayBounds(id)
    let main = (id == CGMainDisplayID()) ? "MAIN" : ""
    print("id=\(id) bounds=\(Int(b.width))x\(Int(b.height)) mm=\(Int(mm.width))x\(Int(mm.height)) \(main)")
}
