// ws-x420-clips.swift: WindowServer two-plane surface leak check (FRAME-PATH / VIDEO-CODEC-MATRIX "Wired memory").
// Plays N synthetic "clips": each clip is a new CVPixelBufferPool of 3840x2160 x420 (10-bit two-plane, the Aerial
// wallpaper's shape) shown through a new AVSampleBufferDisplayLayer at 30 fps for PLAY seconds; then the layer and pool
// are torn down and the window shows nothing for GAP seconds (past NVMTL_KEEP_MS 30 s so WindowServer's surface-keep
// entries can expire). Prints WindowServer's line of debug.nmx_gtt every 5 s. Synthetic pixels only.
//   ws-x420-clips [clips=3] [play=20] [gap=40]       run bounded: perl -e 'alarm 260; exec @ARGV' ./ws-x420-clips
import AppKit
import AVFoundation
import CoreVideo

let args = CommandLine.arguments
let clips = args.count > 1 ? Int(args[1]) ?? 3 : 3
let play = args.count > 2 ? Double(args[2]) ?? 20 : 20
let gap = args.count > 3 ? Double(args[3]) ?? 40 : 40
let W = 3840, H = 2160
let t0 = Date()
func stamp() -> String { String(format: "%6.1f s", Date().timeIntervalSince(t0)) }

func wsGtt() -> String {
    var len = 0
    guard sysctlbyname("debug.nmx_gtt", nil, &len, nil, 0) == 0, len > 0 else { return "nmx_gtt unreadable" }
    var buf = [CChar](repeating: 0, count: len + 1)
    guard sysctlbyname("debug.nmx_gtt", &buf, &len, nil, 0) == 0 else { return "nmx_gtt unreadable" }
    let s = String(cString: buf)
    var total = ""
    var ws = "WindowServer not listed"
    for l in s.split(separator: "\n") {
        if l.hasPrefix("gtt used") { let f = l.split(separator: " "); if f.count > 2, let b = Double(f[2]) { total = String(format: "gtt_used %.0f MB", b / 1048576) } }
        let f = l.split(separator: " ")
        // pid name cpu_resident gtt_resident vram_resident gtt_evicted vram_evicted bos
        if f.count >= 8, f[1] == "WindowServer", let g = Double(f[3]) { ws = String(format: "WS gtt %.0f MB bos %@", g / 1048576, String(f[7])) }
    }
    return "\(ws), \(total)"
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 960, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
win.title = "ws-x420-clips"
win.contentView!.wantsLayer = true
win.makeKeyAndOrderFront(nil)

var layer: AVSampleBufferDisplayLayer?
var pool: CVPixelBufferPool?
var filled = Set<UInt32>()
var frame = 0

func newClip(_ n: Int) {
    let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                  kCVPixelBufferWidthKey: W, kCVPixelBufferHeightKey: H,
                                  kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
    var p: CVPixelBufferPool?
    guard CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 6] as CFDictionary, attrs as CFDictionary, &p) == kCVReturnSuccess else {
        print("ABORT: pool"); exit(2) }
    pool = p; filled = []
    let l = AVSampleBufferDisplayLayer()
    l.frame = win.contentView!.bounds
    l.videoGravity = .resizeAspect
    win.contentView!.layer!.addSublayer(l)
    layer = l
    print("\(stamp()) clip \(n) start: \(wsGtt())")
}
func endClip(_ n: Int) {
    layer?.flushAndRemoveImage()
    layer?.removeFromSuperlayer()
    layer = nil; pool = nil; filled = []
    print("\(stamp()) clip \(n) end: \(wsGtt())")
}
func pushFrame() {
    guard let pool, let layer else { return }
    var pb: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { print("ABORT: pool buffer"); exit(2) }
    let sid = IOSurfaceGetID(CVPixelBufferGetIOSurface(pb)!.takeUnretainedValue())
    if !filled.contains(sid) {     // fill each pool buffer once: a gradient in luma, neutral chroma (10-bit in 16-bit words)
        CVPixelBufferLockBaseAddress(pb, [])
        let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt16.self), yr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0) / 2
        let c = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt16.self), cr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1) / 2
        let shade = UInt16(64 + (Int(sid) * 97) % 800)
        for r in 0..<H { let row = y + r * yr; for x in stride(from: 0, to: W, by: 1) { row[x] = (shade &+ UInt16((x + r) & 127)) << 6 } }
        for r in 0..<(H / 2) { let row = c + r * cr; for x in 0..<W { row[x] = 512 << 6 } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        filled.insert(sid)
    }
    var fd: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fd)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 30),
                                    decodeTimeStamp: .invalid)
    var sb: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: fd!, sampleTiming: &timing, sampleBufferOut: &sb)
    if let sb, let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary], let d = a.first {
        d[kCMSampleAttachmentKey_DisplayImmediately] = true }
    if let sb { layer.enqueue(sb) }
    if layer.status == .failed { print("ABORT: layer failed: \(String(describing: layer.error))"); exit(2) }
    frame += 1
}

print("\(stamp()) before: \(wsGtt())  (\(clips) clips, play \(play) s, gap \(gap) s)")
var clip = 0, phaseStart = Date(), playing = false
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in print("\(stamp()) \(playing ? "play" : "gap ") \(wsGtt())") }
Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
    let el = Date().timeIntervalSince(phaseStart)
    if playing {
        if el >= play { endClip(clip); playing = false; phaseStart = Date() } else { pushFrame() }
    } else if clip == 0 || el >= gap {
        if clip == clips { print("\(stamp()) after: \(wsGtt())"); exit(0) }
        clip += 1; newClip(clip); playing = true; phaseStart = Date()
    }
}
app.run()
