// vfr-420f.swift: row 12 variant (FRAME-PATH 12.14), the mediaanalysisd shape. 2-plane 420f pixel buffers from a
// CVPixelBufferPool are filled with synthetic text, run through Vision (text + classification) and through MPS
// (MPSImage over the planes via CVMetalTextureCache, an MPSCNN pooling kernel that WRITES into another pool surface's
// plane), returned to the pool, left idle 75 s (past debug.nmx_userptr_park_ms = 60 s), then taken from the pool again
// (the same IOSurfaces, recycled) and used the same way. Synthetic data only. Exits non-zero on the first error.
// Run bounded: perl -e 'alarm 200; exec @ARGV' ./vfr-420f
import Foundation
import Vision
import CoreVideo
import CoreGraphics
import CoreText
import Metal
import MetalPerformanceShaders

let t0 = Date()
func stamp() -> String { String(format: "%.1f s", Date().timeIntervalSince(t0)) }
func die(_ s: String) -> Never { print("ABORT at \(stamp()): \(s)"); exit(2) }

let W = 1920, H = 1080
var pool: CVPixelBufferPool?
let pbAttrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                kCVPixelBufferWidthKey: W, kCVPixelBufferHeightKey: H,
                                kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
guard CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 5] as CFDictionary, pbAttrs as CFDictionary, &pool) == kCVReturnSuccess,
      let pool else { die("CVPixelBufferPoolCreate") }
guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { die("no Metal device") }
var cacheOut: CVMetalTextureCache?
guard CVMetalTextureCacheCreate(nil, nil, dev, nil, &cacheOut) == kCVReturnSuccess, let cache = cacheOut else { die("texture cache") }
let pooling = MPSCNNPoolingMax(device: dev, kernelWidth: 1, kernelHeight: 1, strideInPixelsX: 1, strideInPixelsY: 1)

func fill(_ pb: CVPixelBuffer, _ tag: Int) {
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!, yr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
    let c = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!, cr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
    memset(c, 128, cr * H / 2)
    let ctx = CGContext(data: y, width: W, height: H, bitsPerComponent: 8, bytesPerRow: yr, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let font = CTFontCreateWithName("Helvetica" as CFString, 44, nil)
    let s = NSAttributedString(string: "row 12 420f pool \(tag) The quick brown fox 0123456789",
                               attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
    let line = CTLineCreateWithAttributedString(s)
    for yy in stride(from: 50, to: H, by: 110) { ctx.textPosition = CGPoint(x: 30, y: yy); CTLineDraw(line, ctx) }
}
func texture(_ pb: CVPixelBuffer, plane: Int, _ fmt: MTLPixelFormat) -> MTLTexture {
    var t: CVMetalTexture?
    let w = CVPixelBufferGetWidthOfPlane(pb, plane), h = CVPixelBufferGetHeightOfPlane(pb, plane)
    guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, fmt, w, h, plane, &t) == kCVReturnSuccess,
          let t, let mt = CVMetalTextureGetTexture(t) else { die("texture plane \(plane)") }
    return mt
}
func sid(_ pb: CVPixelBuffer) -> UInt32 { IOSurfaceGetID(CVPixelBufferGetIOSurface(pb)!.takeUnretainedValue()) }

func batch(_ name: String) {
    var pbs: [CVPixelBuffer] = []
    for i in 0..<4 {
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { die("pool buffer") }
        fill(pb, i); pbs.append(pb)
    }
    print("\(name): IOSurfaces \(pbs.map { sid($0) }) at \(stamp())")
    // MPS: read plane 0 of buffer i (MPSImage over the Y plane), write plane 0 of buffer (i+1)%4 through an MPSCNN kernel
    let cb = queue.makeCommandBuffer()!
    for i in 0..<4 {
        let src = MPSImage(texture: texture(pbs[i], plane: 0, .r8Unorm), featureChannels: 1)
        let dst = MPSImage(texture: texture(pbs[(i + 1) % 4], plane: 0, .r8Unorm), featureChannels: 1)
        _ = MPSImage(texture: texture(pbs[i], plane: 1, .rg8Unorm), featureChannels: 2)   // the chroma plane imported too
        pooling.encode(commandBuffer: cb, sourceImage: src, destinationImage: dst)
    }
    cb.commit(); cb.waitUntilCompleted()
    if let e = cb.error { die("MPS command buffer: \(e)") }
    print("\(name): MPS pooling 4/4 done at \(stamp())")
    for (i, pb) in pbs.enumerated() {
        let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate
        let cls = VNClassifyImageRequest()
        do { try VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([text, cls]) }
        catch { die("Vision on buffer \(i): \(error)") }
        print("\(name): buffer \(i) \((text.results ?? []).count) text lines, \((cls.results ?? []).count) classes at \(stamp())")
    }
    CVMetalTextureCacheFlush(cache, 0)
}   // the buffers go back to the pool here

batch("batch 1")
print("idle 75 s (park 60 s + 3 sweeps) from \(stamp())")
Thread.sleep(forTimeInterval: 75)
batch("batch 2")
print("exit 0 at \(stamp())")
