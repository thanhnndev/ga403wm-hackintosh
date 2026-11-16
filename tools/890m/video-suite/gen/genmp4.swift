// H.264 / HEVC test clips with AVAssetWriter (VideoToolbox; on this machine the encoders are software). Draws the same
// layout as gen/content.js with CoreGraphics: moving gradient, shapes, scrolling text, two-layer grain, a large frame
// counter (top left) and a 16-bit frame index strip (bottom left). moov at the front (network-friendly).
// usage: genmp4 out.mp4 h264|hevc width height fps seconds bitrate
import AVFoundation
import CoreGraphics
import CoreText
import Foundation

let a = CommandLine.arguments
guard a.count == 8, let W = Int(a[3]), let H = Int(a[4]), let fps = Int(a[5]), let secs = Int(a[6]), let br = Int(a[7]) else {
  print("usage: genmp4 out.mp4 h264|hevc width height fps seconds bitrate"); exit(2)
}
let url = URL(fileURLWithPath: a[1]); try? FileManager.default.removeItem(at: url)
let label = url.lastPathComponent
let s = CGFloat(H) / 1080
let w = try! AVAssetWriter(outputURL: url, fileType: .mp4)
w.shouldOptimizeForNetworkUse = true
var comp: [String: Any] = [AVVideoAverageBitRateKey: br, AVVideoMaxKeyFrameIntervalKey: fps * 2,
  AVVideoExpectedSourceFrameRateKey: fps, AVVideoAllowFrameReorderingKey: true]
if a[2] == "h264" { comp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: a[2] == "hevc" ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
  AVVideoWidthKey: W, AVVideoHeightKey: H, AVVideoCompressionPropertiesKey: comp])
inp.expectsMediaDataInRealTime = false
let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
w.add(inp); w.startWriting(); w.startSession(atSourceTime: .zero)

var seed: UInt32 = 0x9e3779b9
func rnd() -> Double { seed = seed &+ 0x6D2B79F5; var t = (seed ^ (seed >> 15)) &* (1 | seed); t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t; return Double(t ^ (t >> 14)) / 4294967296 }
let cs = CGColorSpaceCreateDeviceRGB()
func tile(_ n: Int) -> CGImage {
  var px = [UInt8](repeating: 0, count: n * n); for i in 0..<px.count { px[i] = UInt8(rnd() * 255) }
  let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
  return ctx.makeImage()!
}
let g1 = tile(256), g2 = tile(193)
struct Shape { var sp, ph, sz, hue, rs: Double; var kind: Int }
let shapes = (0..<24).map { k in Shape(sp: (1.5 + rnd() * 6) * Double(s), ph: rnd() * 6.28, sz: (40 + rnd() * 120) * Double(s), hue: rnd() * 360, rs: (rnd() - 0.5) * 0.15, kind: k % 3) }
let words = "the quick brown fox jumps over the lazy dog while frames tick by at a steady pace and every pixel moves".split(separator: " ").map(String.init)
let lines = (0..<64).map { _ in (0..<9).map { _ in words[Int(rnd() * Double(words.count))] }.joined(separator: " ") }
func hsl(_ h: Double, _ sat: Double, _ l: Double, _ al: Double = 1) -> CGColor {
  let c = (1 - abs(2 * l - 1)) * sat, hp = h.truncatingRemainder(dividingBy: 360) / 60, x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
  var r = 0.0, g = 0.0, b = 0.0
  switch Int(hp) { case 0: (r, g, b) = (c, x, 0); case 1: (r, g, b) = (x, c, 0); case 2: (r, g, b) = (0, c, x); case 3: (r, g, b) = (0, x, c); case 4: (r, g, b) = (x, 0, c); default: (r, g, b) = (c, 0, x) }
  let m = l - c / 2; return CGColor(red: r + m, green: g + m, blue: b + m, alpha: al)
}
func hash(_ i: Int, _ k: Int) -> Int { var x = UInt32(truncatingIfNeeded: i &* 374761393 &+ k &* 668265263); x = (x ^ (x >> 13)) &* 1274126177; return Int(x ^ (x >> 16)) }
func text(_ ctx: CGContext, _ str: String, _ x: CGFloat, _ yTop: CGFloat, _ size: CGFloat, bold: Bool = false) {
  let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
  let attr = NSAttributedString(string: str, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)])
  let line = CTLineCreateWithAttributedString(attr)
  ctx.textPosition = CGPoint(x: x, y: CGFloat(H) - yTop); CTLineDraw(line, ctx)   // yTop = baseline from the top
}
let Wf = CGFloat(W), Hf = CGFloat(H)
let total = fps * secs
let q = DispatchQueue(label: "enc"); let done = DispatchSemaphore(value: 0)
var i = 0
let t0 = Date()
inp.requestMediaDataWhenReady(on: q) {
  while inp.isReadyForMoreMediaData && i < total {
    var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
    let p = pb!; CVPixelBufferLockBaseAddress(p, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(p), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(p),
      space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let t = Double(i) / Double(fps), h0 = (Double(i) * 0.6).truncatingRemainder(dividingBy: 360)
    // CG origin is bottom left; draw in top-left coordinates by flipping y for geometry
    let grad = CGGradient(colorsSpace: cs, colors: [hsl(h0, 0.6, 0.35), hsl(h0 + 120, 0.55, 0.30), hsl(h0 + 240, 0.6, 0.35)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: Hf), end: CGPoint(x: Wf, y: 0), options: [])
    for (k, sh) in shapes.enumerated() {
      let x = (Double(k) * Double(W) / 24 + Double(i) * sh.sp).truncatingRemainder(dividingBy: Double(W) + 2 * sh.sz) - sh.sz
      let y = Double(H) * 0.12 + Double(H) * 0.62 * (0.5 + 0.5 * sin(t * 0.9 + sh.ph + Double(k)))
      ctx.saveGState(); ctx.translateBy(x: x, y: Double(H) - y); ctx.rotate(by: -Double(i) * sh.rs)
      ctx.setFillColor(hsl(sh.hue + Double(i), 0.7, 0.55)); let z = sh.sz
      switch sh.kind {
      case 0: ctx.fill(CGRect(x: -z / 2, y: -z / 2, width: z, height: z))
      case 1: ctx.fillEllipse(in: CGRect(x: -z / 2, y: -z / 2, width: z, height: z))
      default: ctx.move(to: CGPoint(x: 0, y: z / 2)); ctx.addLine(to: CGPoint(x: z / 2, y: -z / 2)); ctx.addLine(to: CGPoint(x: -z / 2, y: -z / 2)); ctx.fillPath()
      }
      ctx.restoreGState()
    }
    let panel = CGRect(x: Wf * 0.64, y: Hf - Hf * 0.86, width: Wf * 0.33, height: Hf * 0.78)
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.45)); ctx.fill(panel)
    ctx.saveGState(); ctx.clip(to: panel)
    let lh = 34 * s, off = (CGFloat(i) * 3 * s).truncatingRemainder(dividingBy: CGFloat(lines.count) * lh)
    for L in 0..<(lines.count * 2) { let y = Hf * 0.1 + CGFloat(L) * lh - off; if y > Hf * 0.06 && y < Hf * 0.9 { text(ctx, lines[L % lines.count], Wf * 0.65, y, 24 * s) } }
    ctx.restoreGState()
    for (g, al, k, mode) in [(g1, 0.10, 1, CGBlendMode.overlay), (g2, 0.08, 2, CGBlendMode.softLight)] {
      let n = g.width, ox = hash(i, k) % n, oy = hash(i, k + 7) % n
      ctx.saveGState(); ctx.setAlpha(al); ctx.setBlendMode(mode)
      var y = -oy; while y < H { var x = -ox; while x < W { ctx.draw(g, in: CGRect(x: x, y: H - y - n, width: n, height: n)); x += n }; y += n }
      ctx.restoreGState()
    }
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.75)); ctx.fill(CGRect(x: 30 * s, y: Hf - 240 * s, width: 760 * s, height: 210 * s))
    text(ctx, String(format: "%05d", i), 50 * s, 150 * s, 120 * s, bold: true)
    text(ctx, String(format: "t=%.3fs %@", t, label), 50 * s, 210 * s, 36 * s)
    let c = (28 * s).rounded(), x0 = 30 * s, yb = 30 * s
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: x0 - 4 * s, y: yb - 4 * s, width: 16 * c + 8 * s, height: c + 8 * s))
    for b in 0..<16 { ctx.setFillColor(CGColor(gray: (i >> (15 - b)) & 1 == 1 ? 1 : 0, alpha: 1)); ctx.fill(CGRect(x: x0 + CGFloat(b) * c, y: yb, width: c, height: c)) }
    CVPixelBufferUnlockBaseAddress(p, [])
    ad.append(p, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
    if i % (fps * 10) == 0 { print("\(label): \(i)/\(total) frames, \(String(format: "%.1f", Double(i) / max(Date().timeIntervalSince(t0), 0.001))) fps") }
    i += 1
  }
  if i >= total { inp.markAsFinished(); w.finishWriting { done.signal() } }
}
done.wait()
if w.status != .completed { print("failed: \(String(describing: w.error))"); exit(1) }
print("\(label): done \(total) frames")
