// SPDX-License-Identifier: BSD-3-Clause-Clear
// Round-trip latency of commit + waitUntilCompleted on the 890M through NVMTL, against GPU execution time.
//   1. tiny: a 4-byte blit fill (the GPU does ~nothing): what one submit -> fence -> wake costs.
//   2. frame: a 2880x1800 bgr10a2 clear + full-screen draw sampling a same-size texture (about one WindowServer composite).
// Prints wall time per wait and GPUEndTime - GPUStartTime when the backend reports it.
//   swiftc -O -o /tmp/nvd/src/metal-latency metal-latency.swift ; copy to /tmp/nvd/bin/nvmtltest (allow list) and run
import Metal
import Foundation
import IOSurface
let n = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 60) : 60
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device:", dev.name)
let q = dev.makeCommandQueue()!
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
func report(_ name: String, _ wall: [Double], _ gpu: [Double]) {
    let w = wall.sorted(), g = gpu.sorted()
    func p(_ a: [Double], _ f: Double) -> String { a.isEmpty ? "-" : String(format: "%.2f", a[min(a.count - 1, Int(Double(a.count) * f))]) }
    print("\(name): wall ms p50 \(p(w, 0.5)) p90 \(p(w, 0.9)) max \(p(w, 1.0)); gpu ms p50 \(p(g, 0.5)) p90 \(p(g, 0.9)) (n=\(w.count))")
}
let buf = dev.makeBuffer(length: 4096, options: .storageModeShared)!
var wall = [Double](), gpu = [Double]()
for _ in 0..<n {
    let cb = q.makeCommandBuffer()!
    let b = cb.makeBlitCommandEncoder()!; b.fill(buffer: buf, range: 0..<4, value: 7); b.endEncoding()
    let t0 = now(); cb.commit(); cb.waitUntilCompleted(); wall.append(now() - t0)
    if cb.gpuEndTime > cb.gpuStartTime && cb.gpuStartTime > 0 { gpu.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }
}
report("tiny", wall, gpu)

let W = 2880, H = 1800
let src = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; float2 uv; };
vertex V vs(uint i [[vertex_id]]) { float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
  V o; o.p = float4(p[i], 0, 1); o.uv = p[i] * 0.5 + 0.5; return o; }
fragment float4 fs(V v [[stage_in]], texture2d<float> t [[texture(0)]]) {
  constexpr sampler s(filter::linear); return t.sample(s, v.uv) * 0.9 + 0.05; }
"""
let lib = try dev.makeLibrary(source: src, options: nil)
let d = MTLRenderPipelineDescriptor()
d.vertexFunction = lib.makeFunction(name: "vs"); d.fragmentFunction = lib.makeFunction(name: "fs")
d.colorAttachments[0].pixelFormat = .bgr10a2Unorm
let pso = try dev.makeRenderPipelineState(descriptor: d)
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgr10a2Unorm, width: W, height: H, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
let a = dev.makeTexture(descriptor: td)!, bt = dev.makeTexture(descriptor: td)!
wall = []; gpu = []
for i in 0..<n {
    let dst = i % 2 == 0 ? a : bt, srcT = i % 2 == 0 ? bt : a
    let rp = MTLRenderPassDescriptor()
    rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
    let cb = q.makeCommandBuffer()!
    let e = cb.makeRenderCommandEncoder(descriptor: rp)!
    e.setRenderPipelineState(pso); e.setFragmentTexture(srcT, index: 0)
    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    let t0 = now(); cb.commit(); cb.waitUntilCompleted(); wall.append(now() - t0)
    if cb.status != .completed { print("frame \(i): status \(cb.status.rawValue) \(String(describing: cb.error))"); break }
    if cb.gpuEndTime > cb.gpuStartTime && cb.gpuStartTime > 0 { gpu.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }
}
report("frame 2880x1800 private", wall, gpu)

// 3. the same frame on IOSurface-backed textures (what WindowServer composites: host-imported system memory)
func surf() -> IOSurfaceRef {
    let props: [IOSurfacePropertyKey: Any] = [.width: W, .height: H, .bytesPerElement: 4, .pixelFormat: 0x6C313072 /* l10r */]
    return IOSurfaceCreate(props as CFDictionary)!
}
let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgr10a2Unorm, width: W, height: H, mipmapped: false)
sd.usage = [.renderTarget, .shaderRead]; sd.storageMode = .shared
let s1 = surf(), s2 = surf()
let sa = dev.makeTexture(descriptor: sd, iosurface: s1, plane: 0)!, sb = dev.makeTexture(descriptor: sd, iosurface: s2, plane: 0)!
for mode in ["iosurface", "iosurface->private", "private->iosurface"] {
    wall = []; gpu = []
    for i in 0..<n {
        var dst: MTLTexture, srcT: MTLTexture
        switch mode {
        case "iosurface": dst = i % 2 == 0 ? sa : sb; srcT = i % 2 == 0 ? sb : sa
        case "iosurface->private": dst = a; srcT = sa
        default: dst = sa; srcT = a
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = dst; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        let cb = q.makeCommandBuffer()!
        let e = cb.makeRenderCommandEncoder(descriptor: rp)!
        e.setRenderPipelineState(pso); e.setFragmentTexture(srcT, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        let t0 = now(); cb.commit(); cb.waitUntilCompleted(); wall.append(now() - t0)
        if cb.status != .completed { print("\(mode) \(i): status \(cb.status.rawValue) \(String(describing: cb.error))"); break }
        if cb.gpuEndTime > cb.gpuStartTime && cb.gpuStartTime > 0 { gpu.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }
    }
    report("frame 2880x1800 \(mode)", wall, gpu)
}
