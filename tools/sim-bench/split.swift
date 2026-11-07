// SPDX-License-Identifier: BSD-3-Clause-Clear
// split (W=, H= env for the surface size): where does a GPU's frame time go? (NVMTL_GPU=amd|nvidia)
//  1. empty command buffer commit -> completed (submit + fence round trip)
//  2. the xgpu frame (1206x2622, 25 blended quads) into a private texture vs a shared IOSurface texture
//  3. ALU-only compute (no memory traffic) -> shading throughput in GFLOP/s
import Metal
import IOSurface
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let W = Int(ProcessInfo.processInfo.environment["W"] ?? "1206")!, H = Int(ProcessInfo.processInfo.environment["H"] ?? "2622")!
let d = MTLCreateSystemDefaultDevice()!
print("device: \(d.name)")
let q = d.makeCommandQueue()!
func med(_ n: Int, _ body: () -> Void) -> (Double, Double) {
    var t: [Double] = []
    for i in 0..<n { let t0 = CFAbsoluteTimeGetCurrent(); body(); if i >= 5 { t.append((CFAbsoluteTimeGetCurrent() - t0) * 1000) } }
    t.sort(); return (t[t.count / 2], t[t.count * 95 / 100])
}
let src = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint id [[vertex_id]], constant float &t [[buffer(0)]], uint inst [[instance_id]]) {
  float2 q[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,-1),float2(1,1),float2(-1,1)};
  float a = t + inst * 0.26; float2 s = inst == 0 ? float2(1,1) : float2(0.08, 0.25);
  float2 o = inst == 0 ? float2(0) : float2(sin(a), cos(a)) * 0.5;
  V v; v.p = float4(q[id] * s + o, 0, 1); v.uv = q[id] * 0.5 + 0.5; return v; }
fragment half4 fs(V in [[stage_in]], constant float &t [[buffer(0)]]) {
  half3 c = half3(0); for (int i = 0; i < 8; i++) c += half3(sin(in.uv.x * 9 + t + i), cos(in.uv.y * 7 + i), 0.5h) * 0.06h;
  return half4(c + 0.3h, 0.7h); }
kernel void alu(device float *o [[buffer(0)]], uint g [[thread_position_in_grid]]) {
  float a = float(g) * 1e-6, b = 1.0001, c = 0.9999;
  for (int i = 0; i < 4096; i++) { a = fma(a, b, c); b = fma(b, c, a); c = fma(c, a, b); a = fma(a, c, b); }
  if (a == 12345.0) o[0] = a + b + c; }
"""
let lib = try! d.makeLibrary(source: src, options: nil)
// 1. submit round trip
let (s1, s1p) = med(105) { let cb = q.makeCommandBuffer()!; cb.commit(); cb.waitUntilCompleted() }
print(String(format: "empty commit->completed: median %.3f ms p95 %.3f ms", s1, s1p))
// 2. frame into private vs IOSurface
let pd = MTLRenderPipelineDescriptor()
pd.vertexFunction = lib.makeFunction(name: "vs"); pd.fragmentFunction = lib.makeFunction(name: "fs")
pd.colorAttachments[0].pixelFormat = .bgra8Unorm; pd.colorAttachments[0].isBlendingEnabled = true
pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
let ps = try! d.makeRenderPipelineState(descriptor: pd)
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
let priv = d.makeTexture(descriptor: td)!
let surf = IOSurface(properties: [.width: W, .height: H, .bytesPerElement: 4, .pixelFormat: 0x42475241])!
td.storageMode = .shared
let shared = d.makeTexture(descriptor: td, iosurface: surf, plane: 0)!
func frame(_ t: MTLTexture, _ frames: Int) {
    let cb = q.makeCommandBuffer()!
    for f in 0..<frames {
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = t
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        let e = cb.makeRenderCommandEncoder(descriptor: rp)!
        var tt = Float(f) * 0.05
        e.setRenderPipelineState(ps); e.setVertexBytes(&tt, length: 4, index: 0); e.setFragmentBytes(&tt, length: 4, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 25); e.endEncoding()
    }
    cb.commit(); cb.waitUntilCompleted()
}
for (name, t) in [("private (VRAM)", priv), ("IOSurface", shared)] {
    let (one, _) = med(65) { frame(t, 1) }
    let (ten, _) = med(25) { frame(t, 10) }
    print(String(format: "frame into %@: 1 frame/cb %.2f ms, 10 frames/cb %.2f ms -> %.2f ms per frame of GPU work", name, one, ten, ten / 10))
}
// 3. ALU
let cp = try! d.makeComputePipelineState(function: lib.makeFunction(name: "alu")!)
let ob = d.makeBuffer(length: 4, options: .storageModeShared)!
let threads = 1 << 20
let (a1, _) = med(15) {
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(cp); e.setBuffer(ob, offset: 0, index: 0)
    e.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
}
let flops = Double(threads) * 4096 * 4 * 2
print(String(format: "ALU: %.2f ms -> %.0f GFLOP/s (fp32 FMA)", a1, flops / (a1 / 1000) / 1e9))
