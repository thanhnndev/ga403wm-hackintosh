// ws-redraw-load.swift: a repeatable WindowServer redraw load for WS-CPU.md (synthetic, no owner data, exits by itself).
//   ws-redraw-load <mode> <seconds> [size]
//   mode ca     : one window, one layer rotated by a Core Animation animation that runs in the render server
//                 (WindowServer composites every frame; this process commits nothing after the start)
//   mode color  : one window, the layer's background colour changed by this process at 60 Hz (one CA commit per frame,
//                 no client GPU work, WindowServer composites a flat colour)
//   mode bitmap : one window, the layer's contents replaced at 60 Hz by a CPU-drawn CGImage (a new IOSurface-backed
//                 image per frame, the way a CPU-drawn app updates; WindowServer uploads/samples it)
// size = window side in points (default 600). Prints the frames it committed. Bounded by <seconds>.
import AppKit
import QuartzCore

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "ca"
let secs = args.count > 2 ? Double(args[2]) ?? 20 : 20
let side = args.count > 3 ? CGFloat(Double(args[3]) ?? 600) : 600

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: side, height: side), styleMask: [.titled], backing: .buffered, defer: false)
win.title = "ws-redraw-load \(mode)"
let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
view.wantsLayer = true
win.contentView = view
let layer = CALayer()
layer.frame = CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6)
layer.backgroundColor = CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
view.layer!.addSublayer(layer)
win.orderFrontRegardless()

var frames = 0
let t0 = Date()
func image(_ i: Int) -> CGImage {
    let w = Int(side * 0.6 * 2), h = w   // 2x for the HiDPI panel
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(red: CGFloat(i % 60) / 60, green: 0.4, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: (i * 8) % w, y: 0, width: 16, height: h))
    return ctx.makeImage()!
}
switch mode {
case "ca":
    let a = CABasicAnimation(keyPath: "transform.rotation.z")
    a.fromValue = 0; a.toValue = 2 * Double.pi; a.duration = 2; a.repeatCount = .infinity
    layer.add(a, forKey: "spin")
default:
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if mode == "color" {
            layer.backgroundColor = CGColor(red: CGFloat(frames % 60) / 60, green: 0.5, blue: 0.9, alpha: 1)
        } else {
            layer.contents = image(frames)
        }
        CATransaction.commit()
        frames += 1
    }
}
Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { _ in
    print(String(format: "ws-redraw-load %@: %d client commits in %.1f s", mode, frames, Date().timeIntervalSince(t0)))
    exit(0)
}
app.run()
