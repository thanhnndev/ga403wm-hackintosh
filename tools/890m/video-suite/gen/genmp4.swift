// H.264 / HEVC test clips with AVAssetWriter (VideoToolbox; on this machine the encoders are software). Draws the same
// layout as gen/content.js with CoreGraphics: moving gradient, shapes, scrolling text, two-layer grain, a large frame
// counter (top left) and a 16-bit frame index strip (bottom left). moov at the front (network-friendly).
// usage: genmp4 out.mp4 h264|hevc|hevc10|av1|av110 width height fps seconds bitrate [frag]   (av1*: bitrate = quality 0..1)
//   hevc10 = HEVC Main10 (10-bit stream); frag = fragmented MP4 (moov + moof every 2 s) for Media Source Extensions
import AVFoundation
import VideoToolbox
import UniformTypeIdentifiers
import CoreGraphics
import CoreText
import Foundation

let a = CommandLine.arguments
guard a.count == 8 || a.count == 9, let W = Int(a[3]), let H = Int(a[4]), let fps = Int(a[5]), let secs = Int(a[6]), let brq = Double(a[7]) else {
  print("usage: genmp4 out.mp4 h264|hevc|hevc10|av1|av110 width height fps seconds bitrate|quality [frag]"); exit(2)
}
let br = brq >= 1 ? Int(brq) : 1_000_000   // bits/s for H.264/HEVC; AV1 reads a[7] as quality 0..1
let url = URL(fileURLWithPath: a[1]); try? FileManager.default.removeItem(at: url)
let label = url.lastPathComponent
let s = CGFloat(H) / 1080
let frag = a.count == 9 && a[8] == "frag"
// frag: CMAF segments through the delegate (init segment, then one moof+mdat per 2 s). movieFragmentInterval is not
// enough: finishWriting rewrites that file into a plain moov+mdat, which MSE rejects ("Detected unfragmented MP4").
final class SegmentSink: NSObject, AVAssetWriterDelegate {
  let h: FileHandle
  init(_ u: URL) { FileManager.default.createFile(atPath: u.path, contents: nil); h = try! FileHandle(forWritingTo: u) }
  func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) { h.write(segmentData) }
}
var sink: SegmentSink? = nil
let w: AVAssetWriter
if frag {
  w = AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue)!)
  w.outputFileTypeProfile = .mpeg4CMAFCompliant
  w.preferredOutputSegmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
  w.initialSegmentStartTime = .zero
  sink = SegmentSink(url); w.delegate = sink
} else { w = try! AVAssetWriter(outputURL: url, fileType: .mp4); w.shouldOptimizeForNetworkUse = true }
let hevc = a[2].hasPrefix("hevc")
let av1 = a[2].hasPrefix("av1")   // av1 / av110: AOM software encoder through VTCompressionSession (AVAssetWriter has no AV1 encoder)
var comp: [String: Any] = [AVVideoAverageBitRateKey: br, AVVideoMaxKeyFrameIntervalKey: fps * 2,
  AVVideoExpectedSourceFrameRateKey: fps, AVVideoAllowFrameReorderingKey: true]
if a[2] == "h264" { comp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
if a[2] == "hevc" { comp[AVVideoProfileLevelKey] = "HEVC_Main_AutoLevel" }    // without it the encoder picks Main10
if a[2] == "hevc10" { comp[AVVideoProfileLevelKey] = "HEVC_Main10_AutoLevel" }
let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
  AVVideoWidthKey: W, AVVideoHeightKey: H, AVVideoCompressionPropertiesKey: comp])
inp.expectsMediaDataInRealTime = false
let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
  kCVPixelBufferCGBitmapContextCompatibilityKey as String: true, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
if !av1 { w.add(inp); w.startWriting(); w.startSession(atSourceTime: .zero) }

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
let t0 = Date()
// draws frame i (content + counter + index strip) into a BGRA pixel buffer
func drawFrame(_ p: CVPixelBuffer, _ i: Int) {
CVPixelBufferLockBaseAddress(p, [])
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
}
if av1 {
  // The AV1 encoder (/System/Library/Video/Plug-Ins/AV1EncoderSW.bundle) is not in VTCopyVideoEncoderList and only
  // opens by its EncoderID. It has no bitrate property (Quality only) and takes 420v / x420: x420 input = 10-bit AV1.
  let ten = a[2] == "av110"
  var sess: VTCompressionSession?
  let spec = [kVTVideoEncoderSpecification_EncoderID: "com.apple.videotoolbox.videoencoder.av1.sw"] as CFDictionary
  guard VTCompressionSessionCreate(allocator: nil, width: Int32(W), height: Int32(H), codecType: CMVideoCodecType(0x61763031),
      encoderSpecification: spec, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
      compressionSessionOut: &sess) == 0, let es = sess else { print("failed: no AV1 encoder"); exit(1) }
  VTSessionSetProperty(es, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
  VTSessionSetProperty(es, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
  VTSessionSetProperty(es, key: kVTCompressionPropertyKey_Quality, value: (Double(a[7]) ?? 0.5) as CFNumber)  // "bitrate" arg = quality 0..1
  VTSessionSetProperty(es, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
  var xfer: VTPixelTransferSession?; VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &xfer)
  VTSessionSetProperty(xfer!, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
  VTSessionSetProperty(xfer!, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
  VTSessionSetProperty(xfer!, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
  let io: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
  var srcPool: CVPixelBufferPool?, dstPool: CVPixelBufferPool?
  CVPixelBufferPoolCreate(nil, nil, (io.merging([kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H]) { $1 }) as CFDictionary, &srcPool)
  CVPixelBufferPoolCreate(nil, nil, (io.merging([kCVPixelBufferPixelFormatTypeKey as String: ten ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H]) { $1 }) as CFDictionary, &dstPool)
  var out: [CMSampleBuffer] = []; let lk = NSLock(); var encErr: OSStatus = 0
  for i in 0..<total {
    var sp: CVPixelBuffer?, dp: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, srcPool!, &sp); CVPixelBufferPoolCreatePixelBuffer(nil, dstPool!, &dp)
    drawFrame(sp!, i)
    VTPixelTransferSessionTransferImage(xfer!, from: sp!, to: dp!)
    VTCompressionSessionEncodeFrame(es, imageBuffer: dp!, presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)),
      duration: CMTime(value: 1, timescale: CMTimeScale(fps)), frameProperties: nil, infoFlagsOut: nil) { st, _, sb in
      lk.lock(); if st != 0 { encErr = st } else if let sb = sb { out.append(sb) }; lk.unlock() }
    if i % (fps * 5) == 0 { print("\(label): \(i)/\(total) frames, \(String(format: "%.1f", Double(i) / max(Date().timeIntervalSince(t0), 0.001))) fps") }
  }
  VTCompressionSessionCompleteFrames(es, untilPresentationTimeStamp: .invalid)
  guard encErr == 0, out.count == total else { print("failed: encoder status \(encErr), \(out.count)/\(total) samples"); exit(1) }
  // MP4 by passthrough (av01 sample entry + av1C from the encoder's format description)
  let mw = try! AVAssetWriter(outputURL: url, fileType: .mp4); mw.shouldOptimizeForNetworkUse = true
  let mi = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: CMSampleBufferGetFormatDescription(out[0]))
  mi.expectsMediaDataInRealTime = false
  mw.add(mi); mw.startWriting(); mw.startSession(atSourceTime: .zero)
  for sb in out { while !mi.isReadyForMoreMediaData { usleep(2000) }; if !mi.append(sb) { print("failed: append \(String(describing: mw.error))"); exit(1) } }
  mi.markAsFinished(); let fin = DispatchSemaphore(value: 0); mw.finishWriting { fin.signal() }; fin.wait()
  if mw.status != .completed { print("failed: \(String(describing: mw.error))"); exit(1) }
  print("\(label): done \(total) frames"); exit(0)
}
let q = DispatchQueue(label: "enc"); let done = DispatchSemaphore(value: 0)
var i = 0
inp.requestMediaDataWhenReady(on: q) {
  while inp.isReadyForMoreMediaData && i < total {
    var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb)
    let p = pb!; drawFrame(p, i)
    ad.append(p, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
    if i % (fps * 10) == 0 { print("\(label): \(i)/\(total) frames, \(String(format: "%.1f", Double(i) / max(Date().timeIntervalSince(t0), 0.001))) fps") }
    i += 1
  }
  if i >= total { inp.markAsFinished(); w.finishWriting { done.signal() } }
}
done.wait()
sink?.h.closeFile()
if w.status != .completed { print("failed: \(String(describing: w.error))"); exit(1) }
print("\(label): done \(total) frames")
