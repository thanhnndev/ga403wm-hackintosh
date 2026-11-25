// M2 size ladder: at which buffer size does a compute dispatch stop completing on the 890M?
// The plain probe waits with -waitUntilCompleted, which parks the process in an uninterruptible kernel wait when the
// job never finishes: no log, no way out, and every later process on that GPU hangs too. This one polls the command
// buffer status and gives up, so the run leaves a trace of the last size that started.
//   NVMTL_PREFER_VENDOR=0x1002 build/metal-compute-ladder
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
let sizes = [256, 1024, 4096, 16384, 65536, 262144, 1048576]
guard let dev = MTLCopyAllDevices().first else { print("FAIL no Metal device"); exit(1) }
print("device: \(dev.name)"); fflush(stdout)
guard let lib = try? dev.makeLibrary(source: src, options: nil),
      let fn = lib.makeFunction(name: "fma3"),
      let pso = try? dev.makeComputePipelineState(function: fn) else { print("FAIL pipeline"); exit(1) }
print("pipeline: maxThreads \(pso.maxTotalThreadsPerThreadgroup)"); fflush(stdout)

for n in sizes {
    let bytes = n * 4
    guard let ba = dev.makeBuffer(length: bytes, options: .storageModeShared),
          let bb = dev.makeBuffer(length: bytes, options: .storageModeShared),
          let bo = dev.makeBuffer(length: bytes, options: .storageModeShared) else {
        print("FAIL makeBuffer n=\(n)"); exit(1)
    }
    let a = ba.contents().bindMemory(to: Float.self, capacity: n)
    let b = bb.contents().bindMemory(to: Float.self, capacity: n)
    for i in 0..<n { a[i] = Float(i % 1000); b[i] = Float(i % 7) }
    guard let q = dev.makeCommandQueue(), let cb = q.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
        print("FAIL encoder n=\(n)"); exit(1)
    }
    enc.setComputePipelineState(pso)
    enc.setBuffer(ba, offset: 0, index: 0); enc.setBuffer(bb, offset: 0, index: 1); enc.setBuffer(bo, offset: 0, index: 2)
    let tp = min(256, pso.maxTotalThreadsPerThreadgroup)
    enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: tp, height: 1, depth: 1))
    enc.endEncoding()
    print("n=\(n) (\(bytes/1024) KB) commit", terminator: " "); fflush(stdout)
    let t0 = Date()
    cb.commit()
    var done = false
    while Date().timeIntervalSince(t0) < 5.0 {
        if cb.status == .completed || cb.status == .error { done = true; break }
        usleep(3000)
    }
    let ms = Date().timeIntervalSince(t0) * 1000
    if !done {
        print(String(format: "TIMEOUT after %.0f ms, status %d", ms, cb.status.rawValue))
        print("RESULT hang at n=\(n) (\(bytes/1024) KB)"); fflush(stdout)
        exit(3)
    }
    func verify() -> (Int, Int, Float, Float) {
        let out = bo.contents().bindMemory(to: Float.self, capacity: n)
        var bad = 0, first = -1
        for i in 0..<n where out[i] != a[i] * 3 + b[i] { bad += 1; if first < 0 { first = i } }
        return (bad, first, first >= 0 ? out[first] : 0, first >= 0 ? a[first] * 3 + b[first] : 0)
    }
    var (bad, first, got, want) = verify()
    if bad != 0 {
        // A late write means the completion signal fired before the GPU finished; a wrong write that stays wrong means
        // the job read or wrote the wrong memory.
        usleep(200_000)
        let after = verify()
        print(String(format: "%.1f ms, %d/%d wrong (first %d: got %.1f want %.1f) after 200ms: %d wrong",
                     ms, bad, n, first, got, want, after.0)); fflush(stdout)
        print(after.0 == 0 ? "RESULT late write at n=\(n) (fence signalled early)" : "RESULT wrong values at n=\(n)")
        exit(after.0 == 0 ? 4 : 2)
    }
    print(String(format: "%.1f ms, correct", ms)); fflush(stdout)
}
print("RESULT all sizes correct")
