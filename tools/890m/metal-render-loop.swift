// SPDX-License-Identifier: BSD-3-Clause-Clear
// Same triangle as metal-render.swift, but N submissions inside ONE process (one MTLDevice, one command queue).
// Discriminates "a new process/VM per run" from "anything after the first job": run 2 of render-stress.sh fails
// every time, so if this loop passes all N, the failing ingredient is the new VM (or the new connection), not the
// second submission as such.
//   swiftc -O -o build/metal-render-loop metal-render-loop.swift   (run the copy as nvmtltest: NVMTL allow list)
import Metal
import Foundation
let n = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 6) : 6
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device:", dev.name, "submissions:", n)
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
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 64, height: 64, mipmapped: false)
td.usage = [.renderTarget]; td.storageMode = .shared
let tex = dev.makeTexture(descriptor: td)!
let q = dev.makeCommandQueue()!
var pass = 0, fail = 0
for i in 1...n {
    let rp = MTLRenderPassDescriptor()
    rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
    rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    let cb = q.makeCommandBuffer()!
    let e = cb.makeRenderCommandEncoder(descriptor: rp)!
    e.setRenderPipelineState(pso); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    cb.commit()
    let t0 = Date()
    while cb.status.rawValue < MTLCommandBufferStatus.completed.rawValue && Date().timeIntervalSince(t0) < 5 { usleep(1000) }
    var out = "run \(i): status \(cb.status.rawValue) after \(Int(Date().timeIntervalSince(t0) * 1000)) ms"
    if cb.status == .completed {
        var px = [UInt8](repeating: 0, count: 4)
        tex.getBytes(&px, bytesPerRow: 256, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
        out += " pixel \(px) " + (px == [255, 128, 64, 255] ? "CORRECT" : "WRONG")
        pass += 1
    } else {
        out += " " + (cb.error.map { "\($0)" } ?? "")
        fail += 1
    }
    print(out)
    fflush(stdout)
    if cb.status != .completed { break }
}
print("same-process pass \(pass) fail \(fail)")
// optional: keep the device/queue/VM alive for N seconds, so another process can be started while this one still
// owns its VM (tests whether the failure needs the *first* VM's teardown or only a second VM). With a third
// argument the held process keeps submitting every that many seconds, so we can see whether a second VM makes the
// *first* one fail too (shared ring) or only itself.
if let hold = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil, hold > 0 {
    print("holding device \(hold)s")
    fflush(stdout)
    let probe = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 0) : 0
    let end = Date().addingTimeInterval(Double(hold))
    while Date() < end {
        sleep(UInt32(probe > 0 ? probe : hold))
        if probe <= 0 { break }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        let cb = q.makeCommandBuffer()!
        let e = cb.makeRenderCommandEncoder(descriptor: rp)!
        e.setRenderPipelineState(pso); e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        cb.commit()
        let t0 = Date()
        while cb.status.rawValue < MTLCommandBufferStatus.completed.rawValue && Date().timeIntervalSince(t0) < 5 { usleep(1000) }
        var px = [UInt8](repeating: 0, count: 4)
        if cb.status == .completed { tex.getBytes(&px, bytesPerRow: 256, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0) }
        print("probe: status \(cb.status.rawValue) after \(Int(Date().timeIntervalSince(t0) * 1000)) ms \(px)")
        fflush(stdout)
    }
}
