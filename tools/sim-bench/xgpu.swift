// SPDX-License-Identifier: BSD-3-Clause-Clear
// xgpu render N   : renders N sim-sized frames (1206x2622 BGRA) into a global IOSurface on this process's GPU
//                   (NVMTL_GPU=nvidia for the RTX), prints the IOSurface id and per-frame time.
// xgpu sample ID N: samples that IOSurface on this process's GPU (the 890M, like WindowServer compositing the
//                   Simulator window), prints per-frame time and the first pixel (did the other GPU's writes arrive?).
import Metal
import IOSurface
import Foundation
setvbuf(stdout, nil, _IOLBF, 0)
let W = 1206, H = 2622
let d = MTLCreateSystemDefaultDevice()!
print("device: \(d.name)")
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
  half3 c = half3(0); for (int i = 0; i < \(ProcessInfo.processInfo.environment["LOOPS"] ?? "8"); i++) c += half3(sin(in.uv.x * 9 + t + i), cos(in.uv.y * 7 + i), 0.5h) * 0.06h;
  return half4(c + 0.3h, 0.7h); }
kernel void sum(texture2d<half, access::read> t [[texture(0)]], device atomic_uint *o [[buffer(0)]], uint2 g [[thread_position_in_grid]]) {
  if (g.x >= t.get_width() || g.y >= t.get_height()) return;
  if (t.read(g).r > 0.5h) atomic_fetch_add_explicit(o, 1, memory_order_relaxed); }
"""
let lib = try! d.makeLibrary(source: src, options: nil)
let q = d.makeCommandQueue()!
func texture(_ s: IOSurface) -> MTLTexture {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
    return d.makeTexture(descriptor: td, iosurface: s, plane: 0)!
}
let args = CommandLine.arguments
let n = Int(args.last!) ?? 120
if args[1] == "render" {
    let s = IOSurface(properties: [.width: W, .height: H, .bytesPerElement: 4, .pixelFormat: 0x42475241 /* BGRA */,
                                   IOSurfacePropertyKey(rawValue: "IOSurfaceIsGlobal"): true])!
    print("iosurface \(s.surfaceID)")
    let t = texture(s)
    let pd = MTLRenderPipelineDescriptor()
    pd.vertexFunction = lib.makeFunction(name: "vs"); pd.fragmentFunction = lib.makeFunction(name: "fs")
    pd.colorAttachments[0].pixelFormat = .bgra8Unorm; pd.colorAttachments[0].isBlendingEnabled = true
    pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    let ps = try! d.makeRenderPipelineState(descriptor: pd)
    var times: [Double] = []
    for f in 0..<n {
        let t0 = CFAbsoluteTimeGetCurrent()
        let cb = q.makeCommandBuffer()!
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = t
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
        let e = cb.makeRenderCommandEncoder(descriptor: rp)!
        var tt = Float(f) * 0.05
        e.setRenderPipelineState(ps); e.setVertexBytes(&tt, length: 4, index: 0); e.setFragmentBytes(&tt, length: 4, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 25)
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }
    let st = Array(times.dropFirst(10)).sorted()
    print(String(format: "render: median %.2f ms p95 %.2f ms (%d frames)", st[st.count / 2], st[st.count * 95 / 100], st.count))
    print("holding"); fflush(stdout)
    Thread.sleep(forTimeInterval: Double(ProcessInfo.processInfo.environment["HOLD"] ?? "20")!)
} else {
    let id = IOSurfaceID(UInt32(args[2])!)
    guard let ref = IOSurfaceLookup(id) else { print("lookup failed"); exit(1) }
    let s = unsafeBitCast(ref, to: IOSurface.self)
    let t = texture(s)
    let cp = try! d.makeComputePipelineState(function: lib.makeFunction(name: "sum")!)
    let out = d.makeBuffer(length: 4, options: .storageModeShared)!
    var times: [Double] = []
    var hits: UInt32 = 0
    for _ in 0..<n {
        memset(out.contents(), 0, 4)
        let t0 = CFAbsoluteTimeGetCurrent()
        let cb = q.makeCommandBuffer()!
        let e = cb.makeComputeCommandEncoder()!
        e.setComputePipelineState(cp); e.setTexture(t, index: 0); e.setBuffer(out, offset: 0, index: 0)
        e.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        hits = out.contents().load(as: UInt32.self)
    }
    let st = Array(times.dropFirst(5)).sorted()
    s.lock(options: .readOnly, seed: nil)
    let px = s.baseAddress.load(as: UInt32.self)
    s.unlock(options: .readOnly, seed: nil)
    print(String(format: "sample: median %.2f ms p95 %.2f ms, red>0.5 pixels %u of %d, CPU first pixel 0x%08x", st[st.count / 2], st[st.count * 95 / 100], hits, W * H, px))
}
