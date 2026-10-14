// Animated load on the Built-in (iGPU/OLED) display so StrixAccel's present path is exercised on purpose.
// Opens a borderless window covering the screen whose name contains "Built-in" and animates a moving bar plus a
// small gradient region, for N seconds. Prints achieved display-link fps and interval stats.
// Build: swiftc -O tools/strix_present_load.swift -o strix_present_load      Run: strix_present_load [seconds] [full|small]
import AppKit
import QuartzCore

let secs = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 6 : 6
let big = (CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "full") == "full"
let want = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Built-in"

final class App: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    var link: CADisplayLink?
    var last: CFTimeInterval = 0
    var iv: [Double] = []
    var bar = CALayer()
    var t0: CFTimeInterval = 0
    func applicationDidFinishLaunching(_ n: Notification) {
        let scr = NSScreen.screens.first { $0.localizedName.contains(want) } ?? NSScreen.main!
        let r = big ? scr.frame : NSRect(x: scr.frame.minX + 100, y: scr.frame.minY + 100, width: 600, height: 400)
        win = NSWindow(contentRect: r, styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .floating
        let v = NSView(frame: NSRect(origin: .zero, size: r.size)); v.wantsLayer = true
        v.layer!.backgroundColor = NSColor.darkGray.cgColor
        bar.frame = CGRect(x: 0, y: 0, width: 160, height: r.height)
        bar.backgroundColor = NSColor.systemOrange.cgColor
        v.layer!.addSublayer(bar)
        win.contentView = v
        win.setFrame(r, display: true)
        win.orderFrontRegardless()
        print("screen: \(scr.localizedName) \(Int(r.width))x\(Int(r.height)) mode=\(big ? "full" : "small")")
        t0 = CACurrentMediaTime()
        link = scr.displayLink(target: self, selector: #selector(tick(_:)))
        link!.add(to: .main, forMode: .common)
    }
    @objc func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        if last > 0 { iv.append((now - last) * 1000) }
        last = now
        let t = now - t0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let w = win.contentView!.bounds.width - bar.bounds.width
        bar.frame.origin.x = CGFloat((sin(t * 3) * 0.5 + 0.5)) * w
        CATransaction.commit()
        if t >= secs {
            link?.invalidate()
            iv.sort()
            let n = iv.count
            if n > 0 {
                let avg = iv.reduce(0, +) / Double(n)
                print(String(format: "ticks=%d fps=%.1f avg=%.2fms p50=%.2f p95=%.2f p99=%.2f max=%.2f", n, Double(n) / secs, avg,
                             iv[n / 2], iv[Int(Double(n) * 0.95)], iv[min(n - 1, Int(Double(n) * 0.99))], iv[n - 1]))
            }
            NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
let d = App(); app.delegate = d
app.setActivationPolicy(.accessory)
app.run()
