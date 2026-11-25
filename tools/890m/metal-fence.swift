// SPDX-License-Identifier: BSD-3-Clause-Clear
// Fence-ordered swap check (NVMTL NMXFencePending/NMXFenceDone). Run with NVMTL_NMX_FENCE=2 so the plugin marks
// surfaces outside WindowServer. For each frame: render into an IOSurface, commit, read the marks (pending set at commit,
// done not past it), wait, read again (done == pending), check the pixels.
//   swiftc -O -o /tmp/nvd/src/metal-fence metal-fence.swift ; copy to /tmp/nvd/bin/nvmtltest ; NVMTL_NMX_FENCE=2 nvmtltest
import Metal
import Foundation
import IOSurface
guard let dev = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(2) }
print("device:", dev.name)
let W = 2880, H = 1800
let props: [IOSurfacePropertyKey: Any] = [.width: W, .height: H, .bytesPerElement: 4, .pixelFormat: 0x42475241]
let surf = IOSurfaceCreate(props as CFDictionary)!
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
let tex = dev.makeTexture(descriptor: td, iosurface: surf, plane: 0)!
let q = dev.makeCommandQueue()!
func mark(_ k: String) -> UInt64 { (IOSurfaceCopyValue(surf, k as CFString) as? NSNumber)?.uint64Value ?? 0 }
var bad = 0, last: UInt64 = 0, waitedAtCommit = 0
for i in 0..<40 {
    let rp = MTLRenderPassDescriptor()
    let c = Double(i % 4) / 4
    rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
    rp.colorAttachments[0].clearColor = MTLClearColor(red: c, green: 0.5, blue: 0.25, alpha: 1)
    let cb = q.makeCommandBuffer()!
    cb.makeRenderCommandEncoder(descriptor: rp)!.endEncoding()
    cb.commit()
    let p0 = mark("NMXFencePending"), d0 = mark("NMXFenceDone")
    cb.waitUntilCompleted()
    let p1 = mark("NMXFencePending"), d1 = mark("NMXFenceDone")
    if d0 < p0 { waitedAtCommit += 1 }
    IOSurfaceLock(surf, .readOnly, nil)
    let px = IOSurfaceGetBaseAddress(surf).load(fromByteOffset: (H / 2) * IOSurfaceGetBytesPerRow(surf) + 4 * (W / 2), as: UInt32.self)
    IOSurfaceUnlock(surf, .readOnly, nil)
    let want = UInt32(255) << 24 | UInt32((c * 255).rounded()) << 16 | UInt32(128) << 8 | UInt32(64)
    let pxOK = abs(Int(px & 0xff) - 64) <= 1 && abs(Int((px >> 8) & 0xff) - 128) <= 1 && abs(Int((px >> 16) & 0xff) - Int((c * 255).rounded())) <= 1
    let ok = p0 != 0 && p0 > last && d0 <= p0 && p1 == p0 && d1 == p0 && cb.status == .completed && pxOK
    if !ok || i < 3 { print("frame \(i): pending \(p0) done-at-commit \(d0) after-wait pending \(p1) done \(d1) pixel \(String(px, radix: 16)) want ~\(String(want, radix: 16)) \(ok ? "ok" : "BAD")") }
    if !ok { bad += 1 }
    last = p0
}
print("frames 40, bad \(bad), done behind pending at commit \(waitedAtCommit) times")
print(bad == 0 ? "CORRECT" : "WRONG")
