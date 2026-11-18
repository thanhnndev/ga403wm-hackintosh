// vision-fault-repro.swift [seconds=120] [images-dir]: FRAME-PATH row 12 reproducer. Runs what mediaanalysisd ran when
// it faulted (Vision text recognition + scene classification -> Espresso MetalLowmemEngine -> MPSImage copy from an
// IOSurface-backed CVPixelBuffer, NVMTL "storage twin") in our own process, with fresh pixel buffers every request so
// IOSurface imports are created and dropped as in the daemon. Stops at the first Vision error (the GPU fault shows up as
// "queue submit -> -4" in NVMTL's log and a Vision error here) or after the time limit.
//
// GPU fault risk: each fault costs a 3 s gfx ring soft recovery; on 2026-11-18 15:52 repeated faults preceded a freeze.
// Run only with the owner's OK, nothing unsaved open, and bounded:
//   swiftc -O tools/890m/vision-fault-repro.swift -o /tmp/vfr && perl -e 'alarm 180; exec @ARGV' /tmp/vfr 120
// Then: /usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "page fault" OR eventMessage CONTAINS "in page starting"'
import Foundation
import Vision
import CoreVideo
import CoreGraphics
import AppKit

let secs = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 120 : 120
let dir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

// inputs: the given images, else synthetic text images (sizes like the daemon's 800x1376 crops)
var cgImages: [CGImage] = []
if let dir = dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) {
    for n in names.prefix(64) {
        if let im = NSImage(contentsOfFile: dir + "/" + n), let cg = im.cgImage(forProposedRect: nil, context: nil, hints: nil) { cgImages.append(cg) }
    }
}
if cgImages.isEmpty {
    for i in 0..<8 {
        let w = 800, h = 1376
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let s = NSAttributedString(string: "frame path row 12 test \(i) The quick brown fox 0123456789",
                                   attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        let line = CTLineCreateWithAttributedString(s)
        for y in stride(from: 60, to: h, by: 120) { ctx.textPosition = CGPoint(x: 20, y: y); CTLineDraw(line, ctx) }
        cgImages.append(ctx.makeImage()!)
    }
}

func pixelBuffer(_ cg: CGImage) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
    guard CVPixelBufferCreate(nil, cg.width, cg.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
          let p = pb else { return nil }
    CVPixelBufferLockBaseAddress(p, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(p), width: cg.width, height: cg.height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(p), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    CVPixelBufferUnlockBaseAddress(p, [])
    return p
}

let t0 = Date()
var n = 0, errors = 0
let q = DispatchQueue(label: "vfr", attributes: .concurrent)   // mediaanalysisd runs several Vision requests at once
let g = DispatchGroup()
while Date().timeIntervalSince(t0) < secs && errors == 0 {
    for k in 0..<4 {
        g.enter()
        let cg = cgImages[(n + k) % cgImages.count]
        q.async {
            defer { g.leave() }
            autoreleasepool {
                guard let pb = pixelBuffer(cg) else { return }        // a fresh IOSurface every request
                let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate
                let cls = VNClassifyImageRequest()
                do { try VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([text, cls]) }
                catch { errors += 1; print("Vision error after \(n) requests at \(Date().timeIntervalSince(t0)) s: \(error)") }
            }
        }
    }
    g.wait()
    n += 4
    if n % 200 == 0 { print("\(n) requests, \(Int(Date().timeIntervalSince(t0))) s") }
}
print("done: \(n) requests in \(Int(Date().timeIntervalSince(t0))) s, \(errors) Vision errors")
