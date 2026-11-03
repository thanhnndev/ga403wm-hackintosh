// SPDX-License-Identifier: BSD-3-Clause-Clear
// Readback / upload speed of a panel-sized texture through the Metal driver (NVMTL on the 890M).
// The GPU clears a shared 2880x1800 rgba8 texture, then getBytes reads all of it back (NVMTL: nvmtl_vk_image_read,
// a staging buffer copied out with memmove), and replaceRegion writes it (nvmtl_vk_image_write). Every pixel is checked.
//   swiftc -O -o build/metal-readback metal-readback.swift
//   cp build/metal-readback /tmp/nvd/bin/nvmtltest && /tmp/nvd/bin/nvmtltest [iterations]
import Foundation
import Metal

let w = 2880, h = 1800, iters = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 5 : 5
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device:", dev.name)
guard let q = dev.makeCommandQueue() else { print("no queue"); exit(2) }
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]
td.storageMode = .shared
guard let tex = dev.makeTexture(descriptor: td) else { print("no texture"); exit(2) }
var px = [UInt8](repeating: 0, count: w * h * 4)
var bad = 0
for i in 0..<iters {
    let c = (UInt8((32 + i * 40) % 256), UInt8((200 + i * 226) % 256), UInt8((64 + i * 7) % 256), UInt8(255))
    let rp = MTLRenderPassDescriptor()
    rp.colorAttachments[0].texture = tex
    rp.colorAttachments[0].loadAction = .clear
    rp.colorAttachments[0].storeAction = .store
    rp.colorAttachments[0].clearColor = MTLClearColor(red: Double(c.0) / 255, green: Double(c.1) / 255,
                                                      blue: Double(c.2) / 255, alpha: 1)
    guard let cb = q.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { print("no cb"); exit(2) }
    enc.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
    if cb.status != .completed { print("render status", cb.status.rawValue, cb.error.map { "\($0)" } ?? ""); exit(3) }
    let t0 = Date()
    tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    let rd = Date().timeIntervalSince(t0)
    var wrong = 0
    for p in stride(from: 0, to: px.count, by: 4) {
        if abs(Int(px[p]) - Int(c.0)) > 1 || abs(Int(px[p + 1]) - Int(c.1)) > 1 || abs(Int(px[p + 2]) - Int(c.2)) > 1 { wrong += 1 }
    }
    bad += wrong
    let t1 = Date()
    px.withUnsafeBytes { tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 4) }
    let wr = Date().timeIntervalSince(t1)
    let mb = Double(w * h * 4) / 1e6
    print(String(format: "iter %d: getBytes %.1f ms (%.0f MB/s), replaceRegion %.1f ms (%.0f MB/s), wrong pixels %d",
                 i, rd * 1000, mb / rd, wr * 1000, mb / wr, wrong))
}
print(bad == 0 ? "CORRECT" : "WRONG (\(bad) pixels)")
exit(bad == 0 ? 0 : 1)
