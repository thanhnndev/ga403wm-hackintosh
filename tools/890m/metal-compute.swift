// SPDX-License-Identifier: BSD-3-Clause-Clear
// Runs one Metal compute kernel on the first Metal device and checks the result (890M bring-up: does a command buffer
// actually execute on the GPU through NVMTLDriver -> RADV -> NMXGPU?).
//   swiftc -O metal-compute.swift -o build/metal-compute && build/metal-compute
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
func fail(_ s: String) -> Never { print("FAIL:", s); exit(1) }
guard let dev = MTLCopyAllDevices().first else { fail("no Metal device") }
print("device:", dev.name)
let n = 1 << 20
let lib: MTLLibrary
do { lib = try dev.makeLibrary(source: src, options: nil) } catch { fail("makeLibrary: \(error)") }
guard let fn = lib.makeFunction(name: "fma3") else { fail("makeFunction") }
let pso: MTLComputePipelineState
do { pso = try dev.makeComputePipelineState(function: fn) } catch { fail("pipeline: \(error)") }
let a = (0..<n).map { Float($0 % 1000) }, b = (0..<n).map { Float($0 % 7) }
guard let ba = dev.makeBuffer(bytes: a, length: n * 4, options: .storageModeShared),
      let bb = dev.makeBuffer(bytes: b, length: n * 4, options: .storageModeShared),
      let bo = dev.makeBuffer(length: n * 4, options: .storageModeShared) else { fail("makeBuffer") }
guard let q = dev.makeCommandQueue(), let cb = q.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder()
else { fail("queue/command buffer/encoder") }
enc.setComputePipelineState(pso)
enc.setBuffer(ba, offset: 0, index: 0); enc.setBuffer(bb, offset: 0, index: 1); enc.setBuffer(bo, offset: 0, index: 2)
enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: min(256, pso.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
enc.endEncoding()
let t0 = Date()
cb.commit(); cb.waitUntilCompleted()
print("command buffer:", cb.status == .completed ? "completed" : "status \(cb.status.rawValue)",
      cb.error.map { "error \($0)" } ?? "", String(format: "%.2f ms", Date().timeIntervalSince(t0) * 1000))
let out = bo.contents().bindMemory(to: Float.self, capacity: n)
var bad = 0
for i in 0..<n where out[i] != a[i] * 3 + b[i] { bad += 1; if bad <= 3 { print("  mismatch at \(i): \(out[i])") } }
print(bad == 0 ? "result: all \(n) values correct (GPU executed the kernel)" : "result: \(bad) of \(n) wrong")
exit(bad == 0 ? 0 : 2)
