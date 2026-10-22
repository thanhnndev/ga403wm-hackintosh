// Frame pacing probe for the NullMoth display path. Opens a small window and, for N seconds,
// either moves it every display tick ("move", like dragging) or animates a layer inside it ("anim").
// Prints the app-side tick intervals and the NVRMFB flip counters (debug.nvrmfb_flip_*) over the run.
// Read-only apart from the window it opens. Build: swiftc -O tools/framepace.swift -o /tmp/framepace
// Run:   /tmp/framepace <move|anim|idle> <secs> [shadow|noshadow] [titled|borderless] [w] [h]
import AppKit
import QuartzCore

func sysctlQ(_ name: String) -> Int64 {
    var v: Int64 = 0; var n = MemoryLayout<Int64>.size
    if sysctlbyname(name, &v, &n, nil, 0) != 0 { return -1 }
    if n == 4 { return Int64(Int32(truncatingIfNeeded: v)) }
    return v
}
struct Flips { let n, us, max, miss, drop: Int64
    static func now() -> Flips { Flips(n: sysctlQ("debug.nvrmfb_flip_n"), us: sysctlQ("debug.nvrmfb_flip_us_sum"),
        max: sysctlQ("debug.nvrmfb_flip_us_max"), miss: sysctlQ("debug.nvaccel_iop_flip_miss"), drop: sysctlQ("debug.nvaccel_iop_async_drop")) } }

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "move"
let secs = args.count > 2 ? Double(args[2]) ?? 5 : 5
let shadow = args.count > 3 ? args[3] == "shadow" : true
let titled = args.count > 4 ? args[4] == "titled" : true
let ww = args.count > 5 ? Double(args[5]) ?? 600 : 600
let hh = args.count > 6 ? Double(args[6]) ?? 400 : 400

final class App: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    var ticks: [CFTimeInterval] = []
    var link: CADisplayLink?
    var t0: CFTimeInterval = 0
    var f0 = Flips.now()
    var origin = NSPoint.zero
    func applicationDidFinishLaunching(_ n: Notification) {
        let scr = NSScreen.main!
        let r = NSRect(x: 200, y: 200, width: ww, height: hh)
        win = NSWindow(contentRect: r, styleMask: titled ? [.titled] : [.borderless], backing: .buffered, defer: false)
        win.title = "framepace \(mode)"; win.hasShadow = shadow
        let v = NSView(frame: NSRect(origin: .zero, size: r.size)); v.wantsLayer = true
        v.layer!.backgroundColor = NSColor.systemTeal.cgColor
        if mode == "anim" {
            let sq = CALayer(); sq.frame = CGRect(x: 250, y: 150, width: 100, height: 100); sq.backgroundColor = NSColor.systemOrange.cgColor
            v.layer!.addSublayer(sq)
            let a = CABasicAnimation(keyPath: "transform.rotation.z"); a.fromValue = 0; a.toValue = Double.pi * 2
            a.duration = 1; a.repeatCount = .infinity; sq.add(a, forKey: "spin")
        }
        win.contentView = v; win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        origin = win.frame.origin
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in   // let the window settle first
            f0 = Flips.now(); t0 = CACurrentMediaTime()
            let l = scr.displayLink(target: self, selector: #selector(tick(_:))); l.add(to: .main, forMode: .common); link = l
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.finish(scr) }
        }
    }
    @objc func tick(_ l: CADisplayLink) {
        let t = CACurrentMediaTime(); ticks.append(t)
        if mode == "move" {
            let k = (t - t0) * 2 * Double.pi / 2.0
            win.setFrameOrigin(NSPoint(x: origin.x + 300 * cos(k), y: origin.y + 150 * sin(k)))
        }
    }
    func finish(_ scr: NSScreen) {
        link?.invalidate()
        let el = CACurrentMediaTime() - t0, f1 = Flips.now()
        var d = zip(ticks.dropFirst(), ticks).map { ($0 - $1) * 1000 }; d.sort()
        func pct(_ p: Double) -> Double { d.isEmpty ? 0 : d[min(d.count - 1, Int(Double(d.count) * p))] }
        let hz = scr.maximumFramesPerSecond
        let budget = 1000.0 / Double(hz)
        let late = d.filter { $0 > budget * 1.5 }.count
        print(String(format: "mode %@  %.2f s  screen max %d Hz", mode, el, hz))
        print(String(format: "app ticks: %d (%.1f/s)  interval ms p50 %.2f p90 %.2f p99 %.2f max %.2f  late(>1.5 frame) %d",
                     ticks.count, Double(ticks.count) / el, pct(0.5), pct(0.9), pct(0.99), d.last ?? 0, late))
        let dn = f1.n - f0.n
        print(String(format: "flips: %lld (%.1f/s)  avg flip call %.2f ms  max ever %.2f ms  flip_miss +%lld  async_drop +%lld",
                     dn, Double(dn) / el, dn > 0 ? Double(f1.us - f0.us) / Double(dn) / 1000 : 0, Double(f1.max) / 1000,
                     f1.miss - f0.miss, f1.drop - f0.drop))
        NSApp.terminate(nil)
    }
}
if mode == "idle" {
    let f0 = Flips.now(); Thread.sleep(forTimeInterval: secs); let f1 = Flips.now(); let dn = f1.n - f0.n
    print(String(format: "idle %.0f s  flips %lld (%.1f/s)  avg flip call %.2f ms", secs, dn, Double(dn) / secs,
                 dn > 0 ? Double(f1.us - f0.us) / Double(dn) / 1000 : 0))
    exit(0)
}
let app = NSApplication.shared; let del = App(); app.delegate = del; app.setActivationPolicy(.regular); app.run()
