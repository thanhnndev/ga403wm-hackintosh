// M2: does a new process fail its FIRST submission and succeed on the next one?
// Build15's two-client check showed the second client failing at 252 ms with a different VMID and no GCVM fault.
// If the first dispatch in a process writes nothing and a retry in the SAME process works, the job ran before the
// new VMID's page table was live; if retries keep failing, the problem is elsewhere.
//   NVMTL_PREFER_VENDOR=0x1002 build/metal-first-job [--delay-ms N] [--attempts N]
// A delay before the first submission separates "the job ran before the new VMID's page table was live" (the delay
// makes it pass) from a broken command stream (the delay changes nothing).
import Foundation
import Metal

let src = """
#include <metal_stdlib>
using namespace metal;
kernel void fma3(device const float *a [[buffer(0)]], device const float *b [[buffer(1)]],
                 device float *out [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    out[i] = a[i] * 3.0f + b[i];
}
"""
var delayMs = 0
var maxAttempts = 4
let argv = CommandLine.arguments
var ai = 1
while ai < argv.count {
    if argv[ai] == "--delay-ms", ai + 1 < argv.count { delayMs = Int(argv[ai + 1]) ?? 0; ai += 1 }
    else if argv[ai] == "--attempts", ai + 1 < argv.count { maxAttempts = Int(argv[ai + 1]) ?? 4; ai += 1 }
    ai += 1
}
if delayMs > 0 { usleep(UInt32(delayMs) * 1000) }
guard let dev = MTLCopyAllDevices().first else { print("FAIL no device"); exit(1) }
guard let lib = try? dev.makeLibrary(source: src, options: nil), let fn = lib.makeFunction(name: "fma3"),
      let pso = try? dev.makeComputePipelineState(function: fn) else { print("FAIL pipeline"); exit(1) }
let n = 256
var attempts: [String] = []
for attempt in 1...maxAttempts {
    guard let ba = dev.makeBuffer(length: n * 4, options: .storageModeShared),
          let bb = dev.makeBuffer(length: n * 4, options: .storageModeShared),
          let bo = dev.makeBuffer(length: n * 4, options: .storageModeShared) else {
        attempts.append("a\(attempt):alloc"); continue
    }
    let a = ba.contents().bindMemory(to: Float.self, capacity: n)
    let b = bb.contents().bindMemory(to: Float.self, capacity: n)
    for i in 0..<n { a[i] = Float(i % 1000); b[i] = Float(i % 7) }
    guard let q = dev.makeCommandQueue(), let cb = q.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
        attempts.append("a\(attempt):queue"); continue
    }
    enc.setComputePipelineState(pso)
    enc.setBuffer(ba, offset: 0, index: 0); enc.setBuffer(bb, offset: 0, index: 1); enc.setBuffer(bo, offset: 0, index: 2)
    enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: min(64, pso.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
    enc.endEncoding()
    cb.commit()
    var done = false
    let t0 = Date()
    while Date().timeIntervalSince(t0) < 5 { if cb.status == .completed || cb.status == .error { done = true; break }; usleep(2000) }
    if !done { attempts.append("a\(attempt):timeout"); print("RESULT hang at attempt \(attempt)"); exit(3) }
    let out = bo.contents().bindMemory(to: Float.self, capacity: n)
    var bad = 0
    for i in 0..<n where out[i] != a[i] * 3 + b[i] { bad += 1 }
    attempts.append(String(format: "a%d:%@", attempt, bad == 0 ? "ok" : "\(bad)bad"))
    if bad == 0 { break }
}
print("delay \(delayMs)ms:", attempts.joined(separator: " "), "->", attempts.contains { $0.hasSuffix(":ok") } ? "pass" : "fail")
