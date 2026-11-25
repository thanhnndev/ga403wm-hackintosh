// SPDX-License-Identifier: BSD-3-Clause-Clear
// Bounded graphics-job test for the 890M (Step38): render one triangle into a 64x64 offscreen texture, poll the
// command buffer for at most 5 s (never waitUntilCompleted), read a pixel back. Run as a copy named nvmtltest.
//   swiftc -O -o build/metal-render metal-render.swift
import Metal
import Foundation
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device:", dev.name)
let src = """
#include <metal_stdlib>
using namespace metal;
vertex float4 vs(uint i [[vertex_id]]) { float2 p[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) }; return float4(p[i], 0, 1); }
fragment float4 fs() { return float4(1, 0.5, 0.25, 1); }
"""
let lib = try dev.makeLibrary(source: src, options: nil)
let d = MTLRenderPipelineDescriptor()
d.vertexFunction = lib.makeFunction(name: "vs"); d.fragmentFunction = lib.makeFunction(name: "fs")
d.colorAttachments[0].pixelFormat = .rgba8Unorm
let pso = try dev.makeRenderPipelineState(descriptor: d)
print("pipeline ok")
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 64, height: 64, mipmapped: false)
td.usage = [.renderTarget]; td.storageMode = .shared
let tex = dev.makeTexture(descriptor: td)!
let rp = MTLRenderPassDescriptor()
rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
let q = dev.makeCommandQueue()!, cb = q.makeCommandBuffer()!
let e = cb.makeRenderCommandEncoder(descriptor: rp)!
e.setRenderPipelineState(pso); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
cb.commit()
let t0 = Date()
while cb.status.rawValue < MTLCommandBufferStatus.completed.rawValue && Date().timeIntervalSince(t0) < 5 { usleep(1000) }
print("status", cb.status.rawValue, "after", Int(Date().timeIntervalSince(t0) * 1000), "ms", cb.error.map { "\($0)" } ?? "")
if cb.status == .completed {
    var px = [UInt8](repeating: 0, count: 4)
    tex.getBytes(&px, bytesPerRow: 256, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
    print("pixel", px, px == [255, 128, 64, 255] ? "CORRECT" : "WRONG")
}
