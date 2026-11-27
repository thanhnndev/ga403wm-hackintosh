// rec UID seconds [channels]: records an input device, prints per-channel peak / RMS (dBFS) every 0.5 s.
// With CORR=1 also prints the correlation of each channel pair (identical channels -> 1.000).
import AudioToolbox
import Foundation
let uidArg = CommandLine.arguments[1], secs = Double(CommandLine.arguments[2]) ?? 3
let ch = UInt32(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "2")!
let C = Int(ch), corr = ProcessInfo.processInfo.environment["CORR"] == "1"
var f = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 4*ch, mFramesPerPacket: 1, mBytesPerFrame: 4*ch, mChannelsPerFrame: ch, mBitsPerChannel: 32, mReserved: 0)
var pk = [Float](repeating: 0, count: C), ss = [Double](repeating: 0, count: C), n = 0, total = 0
var xy = [[Double]](repeating: [Double](repeating: 0, count: C), count: C)
func db(_ x: Double) -> String { x <= 0 ? "-inf" : String(format: "%.1f", 20*log10(x)) }
let cb: AudioQueueInputCallback = { _, q, b, _, _, _ in
    let fr = Int(b.pointee.mAudioDataByteSize) / (4*C); let p = b.pointee.mAudioData.assumingMemoryBound(to: Float.self)
    for i in 0..<fr { for c in 0..<C { let v = p[i*C+c]; pk[c] = max(pk[c], abs(v)); ss[c] += Double(v*v)
        if corr { for d in 0..<C { xy[c][d] += Double(v) * Double(p[i*C+d]) } } } }
    n += fr; total += fr
    if n >= 24000 {
        var line = String(format: "t=%.1f ", Double(total)/48000) + (0..<C).map { "ch\($0) peak \(db(Double(pk[$0]))) rms \(db(sqrt(ss[$0]/Double(n))))" }.joined(separator: " | ")
        if corr { for a in 0..<C { for b in (a+1)..<C where C > 1 { let r = xy[a][b] / max(1e-30, sqrt(xy[a][a]*xy[b][b])); line += String(format: "  r%d%d %.3f", a, b, r) } } }
        print(line); pk = pk.map{_ in 0}; ss = ss.map{_ in 0}; xy = xy.map { $0.map{_ in 0} }; n = 0 }
    AudioQueueEnqueueBuffer(q, b, 0, nil)
}
var q: AudioQueueRef?
guard AudioQueueNewInput(&f, cb, nil, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &q) == 0 else { print("new failed"); exit(1) }
var uid = uidArg as CFString
AudioQueueSetProperty(q!, kAudioQueueProperty_CurrentDevice, &uid, UInt32(MemoryLayout<CFString>.size))
for _ in 0..<4 { var b: AudioQueueBufferRef?; AudioQueueAllocateBuffer(q!, 2048*4*ch, &b); AudioQueueEnqueueBuffer(q!, b!, 0, nil) }
AudioQueueStart(q!, nil); CFRunLoopRunInMode(.defaultMode, secs, false); AudioQueueStop(q!, true)
