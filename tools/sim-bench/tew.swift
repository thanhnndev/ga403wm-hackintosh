// SPDX-License-Identifier: BSD-3-Clause-Clear
// Prints the compute pipeline numbers MTLSimDriver divides by (threadExecutionWidth = 0 -> SIGFPE in the sim).
import Metal
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void k(device uint *o [[buffer(0)]], uint i [[thread_position_in_grid]]) { o[i] = i; }
"""
guard let d = MTLCreateSystemDefaultDevice() else { print("no device"); exit(1) }
print("device: \(d.name) registryID 0x\(String(d.registryID, radix: 16))")
let lib = try! d.makeLibrary(source: src, options: nil)
let p = try! d.makeComputePipelineState(function: lib.makeFunction(name: "k")!)
print("threadExecutionWidth \(p.threadExecutionWidth) maxTotalThreadsPerThreadgroup \(p.maxTotalThreadsPerThreadgroup) staticTG \(p.staticThreadgroupMemoryLength)")
print("maxThreadsPerThreadgroup \(d.maxThreadsPerThreadgroup)")
