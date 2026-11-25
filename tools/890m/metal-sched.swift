// Step96: how long waitUntilScheduled blocks for a small command buffer committed behind a heavy one, and whether the
// queue order still holds (B's fill must land after A's). NVMTL_COMMIT_AHEAD=0 gives the old behaviour.
// Run as /tmp/nvd/bin/nvmtltest (allow-listed name), one run at a time.
import Metal
import Foundation

let dev = MTLCreateSystemDefaultDevice()!
let q = dev.makeCommandQueue()!
let w = 2880, h = 1800
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
td.usage = [.renderTarget]; td.storageMode = .private
let rt = dev.makeTexture(descriptor: td)!
let out = dev.makeBuffer(length: 4096, options: .storageModeShared)!
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
var sched: [Double] = [], aGpu: [Double] = []
var bad = 0
for i in 0..<30 {
    let a = q.makeCommandBuffer()!
    for _ in 0..<12 {   // ~4 ms of clears at 2880x1800
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = rt; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: Double(i % 7) / 7, green: 0.5, blue: 0.25, alpha: 1)
        a.makeRenderCommandEncoder(descriptor: rp)!.endEncoding()
    }
    let ba = a.makeBlitCommandEncoder()!; ba.fill(buffer: out, range: 0..<4096, value: 0x11); ba.endEncoding()
    a.commit()
    let b = q.makeCommandBuffer()!
    let bb = b.makeBlitCommandEncoder()!; bb.fill(buffer: out, range: 0..<4096, value: 0x22); bb.endEncoding()
    b.commit()
    let t0 = now(); b.waitUntilScheduled(); sched.append(now() - t0)
    b.waitUntilCompleted()
    aGpu.append((a.gpuEndTime - a.gpuStartTime) * 1000)
    if out.contents().load(as: UInt8.self) != 0x22 || a.status != .completed || b.status != .completed { bad += 1 }
}
func p(_ v: [Double], _ f: Double) -> Double { let s = v.sorted(); return s[min(s.count - 1, Int(Double(s.count) * f))] }
print(String(format: "B waitUntilScheduled ms p50 %.2f p90 %.2f max %.2f; A gpu ms p50 %.2f (n=%d)",
             p(sched, 0.5), p(sched, 0.9), sched.max()!, p(aGpu, 0.5), sched.count))
print(bad == 0 ? "ORDER OK" : "ORDER BAD \(bad)")
