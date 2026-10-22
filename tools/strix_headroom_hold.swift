// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// StrixHeadroomHold: keeps one EDR headroom request open in WindowServer so CoreDisplay caches the display headroom.
//
// Why (docs/890M-TRACE.md "Step14"): with the OLED on the display pipe, RunFullDisplayPipe -> CombineLUTs calls
// Display::CurrentHeadroom for every LUT entry on ~24 dispatch_apply workers. CurrentHeadroom only caches its result
// when EDRDisplay+0x11 ("headroom requested") is set, and the only writer is CoreDisplay_XRPresent(bool), which
// SkyLight calls from CoreDisplayManager::set_edr_present() when some window in the session asks for EDR. Without a
// request every call takes the Display mutex: WindowServer 1400-1650 % CPU and window drags at ~28 fps. With one
// request open: ~150 % and ~119 fps. EDR itself stays off (current headroom 1.0) because the request content is SDR.
//
// The window is 1x1 pt, fully transparent, click-through, on all spaces. Run as a LaunchAgent
// (scripts/macos-strix-headroom-hold.sh install). Build: swiftc -O tools/strix_headroom_hold.swift -o strix-headroom-hold
// Args: [--visible] (8x8 grey square for debugging), [--seconds N] (exit after N s, default: forever).
import AppKit
import Metal
import QuartzCore

let args = CommandLine.arguments
let visible = args.contains("--visible")
let seconds: Double? = args.firstIndex(of: "--seconds").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }

final class Hold: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    let layer = CAMetalLayer()
    var queue: MTLCommandQueue?

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
        queue = dev.makeCommandQueue()
        let side: CGFloat = visible ? 8 : 1
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless],
                       backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        v.wantsLayer = true
        layer.device = dev
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        layer.isOpaque = false
        layer.frame = v.bounds
        v.layer!.addSublayer(layer)
        win.contentView = v
        win.orderFrontRegardless()
        draw()
        // Re-draw now and then so the surface stays live (cheap: one 1x1 clear).
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.draw() }
        // Re-assert after display reconfiguration (sleep/wake, mode change).
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.win.orderFrontRegardless(); self?.draw() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.win.orderFrontRegardless(); self?.draw() }
        if let s = seconds { DispatchQueue.main.asyncAfter(deadline: .now() + s) { NSApp.terminate(nil) } }
        print("strix-headroom-hold: request open (\(visible ? "visible" : "hidden") \(Int(side))x\(Int(side)))")
    }

    func draw() {
        guard let q = queue, let d = layer.nextDrawable() else { return }
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = d.texture
        p.colorAttachments[0].loadAction = .clear
        p.colorAttachments[0].storeAction = .store
        p.colorAttachments[0].clearColor = visible ? MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                                                   : MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let c = q.makeCommandBuffer(), let e = c.makeRenderCommandEncoder(descriptor: p) else { return }
        e.endEncoding()
        c.present(d)
        c.commit()
    }
}

let app = NSApplication.shared
let hold = Hold()
app.delegate = hold
app.setActivationPolicy(.prohibited)
app.run()
