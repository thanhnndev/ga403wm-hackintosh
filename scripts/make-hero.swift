// SPDX-License-Identifier: BSD-3-Clause-Clear
// Composes docs/images/hero.png from rogcontrol-window.png, about-this-mac.png and rogcontrol-popover.png.
// Run from the repo root:  swiftc -O scripts/make-hero.swift -o /tmp/make-hero && /tmp/make-hero 1600
//   sips -s format jpeg -s formatOptions 88 docs/images/hero.png --out docs/images/hero.jpg && rm docs/images/hero.png
import AppKit
let W = 1600, H = 900
let OUT = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1600")!
let K = OUT / 1600.0
let dir = "docs/images/"
func load(_ n: String) -> NSImage { NSImage(contentsOfFile: dir + n)! }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(OUT), pixelsHigh: Int(OUT * 9 / 16), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctm = NSAffineTransform(); ctm.scale(by: CGFloat(K)); ctm.concat()
// background: deep blue to violet with a soft teal glow, like the macOS wallpaper in use
let bg = NSGradient(colors: [NSColor(red: 0.07, green: 0.06, blue: 0.20, alpha: 1), NSColor(red: 0.13, green: 0.12, blue: 0.40, alpha: 1),
                             NSColor(red: 0.10, green: 0.30, blue: 0.48, alpha: 1)])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
let glow = NSGradient(colors: [NSColor(red: 0.55, green: 0.85, blue: 0.60, alpha: 0.35), NSColor(red: 0.55, green: 0.85, blue: 0.60, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: 1050, y: 760), radius: 0, toCenter: NSPoint(x: 1050, y: 760), radius: 620, options: [])

func card(_ img: NSImage, x: CGFloat, top: CGFloat, height: CGFloat, radius: CGFloat, cutBottom: CGFloat = 0) {
    let keep = NSRect(x: 0, y: cutBottom, width: img.size.width, height: img.size.height - cutBottom)
    let w = height * keep.width / keep.height
    let r = NSRect(x: x, y: CGFloat(H) - top - height, width: w, height: height)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.55); sh.shadowBlurRadius = 36; sh.shadowOffset = NSSize(width: 0, height: -14)
    sh.set()
    NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
    img.draw(in: r, from: keep, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius); b.lineWidth = 1; b.stroke()
}
func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: NSColor.white.withAlphaComponent(alpha)]
    (s as NSString).draw(at: NSPoint(x: x, y: CGFloat(H) - top - size * 1.2), withAttributes: a)
}
text("macOS Sequoia on the ASUS ROG Zephyrus G14 (GA403WM)", x: 60, top: 38, size: 38, weight: .semibold, alpha: 0.96)
text("Ryzen AI 9 HX 370  ·  RTX 5060  ·  OpenCore 1.0.9  ·  RogControl for performance, battery, keyboard and Slash", x: 62, top: 92, size: 19, weight: .regular, alpha: 0.72)

text("RogControl: performance modes, fan curves,", x: 62, top: 690, size: 21, weight: .regular, alpha: 0.80)
text("charge limit, keyboard light and Slash", x: 62, top: 722, size: 21, weight: .regular, alpha: 0.80)
text("github.com/thanhnndev/ga403wm-hackintosh", x: 62, top: 790, size: 17, weight: .regular, alpha: 0.55)
card(load("rogcontrol-window.png"), x: 50, top: 170, height: 480, radius: 12, cutBottom: 44)
card(load("about-this-mac.png"), x: 1010, top: 170, height: 430, radius: 14, cutBottom: 150)
card(load("rogcontrol-popover.png"), x: 700, top: 440, height: 420, radius: 14)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + "hero.png"))
