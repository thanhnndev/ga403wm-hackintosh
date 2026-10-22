// SPDX-License-Identifier: BSD-3-Clause-Clear
// Render through Metal into a real IOSurface; verify texture readback and the CPU view used by a display pipe.
// Poll the
// command buffer for at most 5 s (never waitUntilCompleted), read a pixel back. Run as a copy named nvmtltest.
//   swiftc -O -o build/metal-iosurface metal-iosurface.swift
import Metal
import Foundation
import IOSurface
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
d.colorAttachments[0].pixelFormat = .bgra8Unorm
let pso = try dev.makeRenderPipelineState(descriptor: d)
print("pipeline ok")
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
td.usage = [.renderTarget]; td.storageMode = .shared
let props: [String: Any] = [kIOSurfaceWidth as String: 64, kIOSurfaceHeight as String: 64,
    kIOSurfaceBytesPerElement as String: 4, kIOSurfaceBytesPerRow as String: 256,
    kIOSurfaceAllocSize as String: 16384, kIOSurfacePixelFormat as String: UInt32(0x42475241)]
guard let surface = IOSurfaceCreate(props as CFDictionary),
      let tex = dev.makeTexture(descriptor: td, iosurface: surface, plane: 0) else {
    print("IOSurface texture creation failed"); exit(3)
}
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
var textureOK = false
if cb.status == .completed {
    var px = [UInt8](repeating: 0, count: 4)
    tex.getBytes(&px, bytesPerRow: 256, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
    textureOK = px == [64, 128, 255, 255]
    print("pixel", px, px == [64, 128, 255, 255] ? "CORRECT" : "WRONG")
}

guard cb.status == .completed else { exit(4) }
guard IOSurfaceLock(surface, .readOnly, nil) == kIOReturnSuccess else { exit(5) }
let base = IOSurfaceGetBaseAddress(surface).assumingMemoryBound(to: UInt8.self)
let offset = 32 * IOSurfaceGetBytesPerRow(surface) + 32 * 4
let cpu = Array(UnsafeBufferPointer(start: base + offset, count: 4))
IOSurfaceUnlock(surface, .readOnly, nil)
print("IOSurface CPU pixel:", cpu, cpu == [64, 128, 255, 255] ? "CORRECT" : "WRONG")
exit(textureOK && cpu == [64, 128, 255, 255] ? 0 : 6)
