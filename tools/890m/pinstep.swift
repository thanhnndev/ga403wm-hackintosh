// pinstep.swift: what a fresh Metal process puts in GTT, step by step (FRAME-PATH 12.16, S2b step 1). Prints this
// process's line of debug.nmx_gtt (cpu gtt vram evicted evicted bos) after each step. Run bounded: perl -e 'alarm 90; exec @ARGV' ./pinstep
import Metal
let me = getpid()
func line() -> String {
    var len = 0
    guard sysctlbyname("debug.nmx_gtt", nil, &len, nil, 0) == 0, len > 0 else { return "unreadable" }
    var buf = [CChar](repeating: 0, count: len + 1)
    guard sysctlbyname("debug.nmx_gtt", &buf, &len, nil, 0) == 0 else { return "unreadable" }
    for l in String(cString: buf).split(separator: "\n") { let f = l.split(separator: " "); if f.first == Substring(String(me)) { return String(l) } }
    return "not listed"
}
func step(_ s: String) { print(String(format: "%-28@ %@", s as NSString, line() as NSString)); fflush(stdout) }
var hdr = 0; var b = [CChar](repeating: 0, count: 4096); var n = 4095
if sysctlbyname("debug.nmx_gtt", &b, &n, nil, 0) == 0 || n > 0 { print(String(cString: b).split(separator: "\n").prefix(3).joined(separator: "\n")) }
step("start")
guard let dev = MTLCreateSystemDefaultDevice() else { print("no device"); exit(2) }
step("device \(dev.name)")
let q = dev.makeCommandQueue()!
step("queue")
let buf = dev.makeBuffer(length: 4096, options: .storageModeShared)!
step("shared 4 KB buffer")
let cb = q.makeCommandBuffer()!; let bl = cb.makeBlitCommandEncoder()!; bl.fill(buffer: buf, range: 0..<4096, value: 1); bl.endEncoding()
cb.commit(); cb.waitUntilCompleted()
step("one blit committed")
let tex = dev.makeTexture(descriptor: { let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false); d.usage = [.renderTarget, .shaderRead]; return d }())!
let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
let cb2 = q.makeCommandBuffer()!; cb2.makeRenderCommandEncoder(descriptor: rp)!.endEncoding(); cb2.commit(); cb2.waitUntilCompleted()
step("one clear render pass")
let q2 = dev.makeCommandQueue()!; let cb3 = q2.makeCommandBuffer()!; cb3.commit(); cb3.waitUntilCompleted()
step("second queue + empty cb")
let src = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 p [[position]]; };
vertex V vs(uint i [[vertex_id]]) { V o; o.p = float4(float(i&1)*2-1, float(i>>1)*2-1, 0, 1); return o; }
fragment float4 fs(V i [[stage_in]]) { return float4(1,0,0,1); }
kernel void k(device uint *b [[buffer(0)]], uint t [[thread_position_in_grid]]) { b[t] = t; }
"""
let lib = try! dev.makeLibrary(source: src, options: nil)
step("library compiled")
let pd = MTLRenderPipelineDescriptor(); pd.vertexFunction = lib.makeFunction(name: "vs"); pd.fragmentFunction = lib.makeFunction(name: "fs"); pd.colorAttachments[0].pixelFormat = .bgra8Unorm
let rps = try! dev.makeRenderPipelineState(descriptor: pd)
step("render pipeline")
let cps = try! dev.makeComputePipelineState(function: lib.makeFunction(name: "k")!)
step("compute pipeline")
let cb4 = q.makeCommandBuffer()!
let re = cb4.makeRenderCommandEncoder(descriptor: rp)!; re.setRenderPipelineState(rps); re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4); re.endEncoding()
let ce = cb4.makeComputeCommandEncoder()!; ce.setComputePipelineState(cps); ce.setBuffer(buf, offset: 0, index: 0); ce.dispatchThreads(MTLSize(width: 1024, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)); ce.endEncoding()
cb4.commit(); cb4.waitUntilCompleted()
step("draw + dispatch")
var cbs: [MTLCommandBuffer] = []
for _ in 0..<64 { let c = q.makeCommandBuffer()!; let e = c.makeRenderCommandEncoder(descriptor: rp)!; e.setRenderPipelineState(rps); for _ in 0..<200 { e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4) }; e.endEncoding(); c.commit(); cbs.append(c) }
cbs.last!.waitUntilCompleted()
step("64 cbs x 200 draws")
let up = dev.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1024, height: 1024, mipmapped: false))!
let px = [UInt8](repeating: 7, count: 1024*1024*4); up.replace(region: MTLRegionMake2D(0, 0, 1024, 1024), mipmapLevel: 0, withBytes: px, bytesPerRow: 4096)
step("4 MB texture replace")
