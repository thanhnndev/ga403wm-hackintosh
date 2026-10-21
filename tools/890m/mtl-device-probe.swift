// M3 gate: does a process get an AMD/RADV Metal device from NMXAccel, and does that device actually execute?
// Device enumeration alone is not enough (a device that cannot run a pass is worse than no device for a compositor),
// so this clears a 16x16 render target and reads the pixels back through a blit.
//   mtl-device-probe            -- report every device, run the clear on the first one
//   NVMTL_PREFER_VENDOR=1002 mtl-device-probe --require-amd
import Foundation
import Metal

let requireAMD = CommandLine.arguments.contains("--require-amd")
var failures = 0

func fail(_ s: String) { print("FAIL \(s)"); failures += 1 }

let devices = MTLCopyAllDevices()
print("devices: \(devices.count)")
for d in devices {
    print("  name=\(d.name) regID=\(d.registryID) lowPower=\(d.isLowPower) headless=\(d.isHeadless) unified=\(d.hasUnifiedMemory)")
}

func isAMD(_ d: MTLDevice) -> Bool {
    let n = d.name.lowercased()
    return n.contains("radeon") || n.contains("radv") || n.contains("amd") || n.contains("890m") || n.contains("strix")
}

if requireAMD && !devices.contains(where: isAMD) {
    fail("no AMD/RADV Metal device in this process (got: \(devices.map(\.name)))")
}

guard let dev = devices.first(where: requireAMD ? isAMD : { _ in true }) else {
    print(failures == 0 ? "SKIP no device to exercise" : "done with \(failures) failure(s)")
    exit(failures == 0 ? 0 : 1)
}

let W = 16, H = 16
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
td.usage = [.renderTarget]
td.storageMode = .private
guard let tex = dev.makeTexture(descriptor: td) else { fail("makeTexture"); exit(1) }
let bytes = W * H * 4
guard let buf = dev.makeBuffer(length: bytes, options: .storageModeShared) else { fail("makeBuffer"); exit(1) }
guard let q = dev.makeCommandQueue() else { fail("makeCommandQueue"); exit(1) }
guard let cb = q.makeCommandBuffer() else { fail("makeCommandBuffer"); exit(1) }

// 0.25 red / 0.50 green / 0.75 blue: three distinct byte values, so a swapped or zeroed channel is visible.
let rp = MTLRenderPassDescriptor()
rp.colorAttachments[0].texture = tex
rp.colorAttachments[0].loadAction = .clear
rp.colorAttachments[0].storeAction = .store
rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0)
guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { fail("makeRenderCommandEncoder"); exit(1) }
enc.endEncoding()
guard let blit = cb.makeBlitCommandEncoder() else { fail("makeBlitCommandEncoder"); exit(1) }
blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
          sourceSize: MTLSize(width: W, height: H, depth: 1),
          to: buf, destinationOffset: 0, destinationBytesPerRow: W * 4, destinationBytesPerImage: bytes)
blit.endEncoding()
cb.commit()
cb.waitUntilCompleted()

if let e = cb.error { fail("command buffer: \(e)") }
else {
    let p = buf.contents().bindMemory(to: UInt8.self, capacity: bytes)
    let b = Int(p[0]), g = Int(p[1]), r = Int(p[2]), a = Int(p[3])
    let want = (b: 191, g: 128, r: 64, a: 255)
    let close = abs(b - want.b) <= 2 && abs(g - want.g) <= 2 && abs(r - want.r) <= 2 && abs(a - want.a) <= 2
    print("clear+readback on \(dev.name): bgra=(\(b),\(g),\(r),\(a)) want=(\(want.b),\(want.g),\(want.r),\(want.a)) \(close ? "PASS" : "FAIL")")
    if !close { failures += 1 }
}

print(failures == 0 ? "RESULT OK" : "RESULT \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
