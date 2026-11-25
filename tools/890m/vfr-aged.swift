// vfr-aged.swift: row 12 variant of tools/890m/vision-fault-repro.swift. The same 4 IOSurface-backed pixel buffers are
// recognized, left idle 65 s (past debug.nmx_userptr_park_ms = 60 s, so their imports can park), then recognized again.
// Synthetic images only. Exits after the second batch or on the first Vision error. Run bounded (alarm 170).
import Foundation
import Vision
import CoreVideo
import CoreGraphics
import AppKit

func makeImage(_ i: Int) -> CGImage {
    let w = 800, h = 1376
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let s = NSAttributedString(string: "frame path row 12 aged \(i) The quick brown fox 0123456789",
                               attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(s)
    for y in stride(from: 60, to: h, by: 120) { ctx.textPosition = CGPoint(x: 20, y: y); CTLineDraw(line, ctx) }
    return ctx.makeImage()!
}
func pixelBuffer(_ cg: CGImage) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
    CVPixelBufferCreate(nil, cg.width, cg.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
    let p = pb!
    CVPixelBufferLockBaseAddress(p, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(p), width: cg.width, height: cg.height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(p), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    CVPixelBufferUnlockBaseAddress(p, [])
    return p
}

let t0 = Date()
func stamp() -> String { String(format: "%.1f s", Date().timeIntervalSince(t0)) }
let pbs = (0..<4).map { pixelBuffer(makeImage($0)) }
for (i, p) in pbs.enumerated() {
    if let s = CVPixelBufferGetIOSurface(p)?.takeUnretainedValue() { print("buffer \(i): IOSurface \(IOSurfaceGetID(s))") }
}
var errors = 0
func batch(_ name: String) {
    let q = DispatchQueue(label: "vfr", attributes: .concurrent), g = DispatchGroup(), lock = NSLock()
    for p in pbs {
        g.enter()
        q.async {
            defer { g.leave() }
            autoreleasepool {
                let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate
                let cls = VNClassifyImageRequest()
                do { try VNImageRequestHandler(cvPixelBuffer: p, options: [:]).perform([text, cls])
                     let lines = (text.results ?? []).count
                     lock.lock(); print("\(name): \(lines) text lines at \(stamp())"); lock.unlock() }
                catch { lock.lock(); errors += 1; print("\(name): Vision error at \(stamp()): \(error)"); lock.unlock() }
            }
        }
    }
    g.wait()
}
print("batch 1 start \(stamp())"); batch("batch 1"); print("batch 1 done \(stamp())")
if errors == 0 {
    print("idle 75 s (park time 60 s + 3 sweeps) from \(stamp())")
    Thread.sleep(forTimeInterval: 75)
    print("batch 2 start \(stamp())"); batch("batch 2"); print("batch 2 done \(stamp())")
}
print("exit: \(errors) Vision errors at \(stamp())")
