// SPDX-License-Identifier: BSD-3-Clause-Clear
// The sim's ASTC upload path: library "astc" kernel with function constants -> threadExecutionWidth.
import Metal
setvbuf(stdout, nil, _IOLBF, 0)
guard let d = MTLCreateSystemDefaultDevice() else { exit(1) }
print("device: \(d.name)")
let lib = try! d.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "simdriver.metallib"))
do { _ = try lib.makeFunction(name: "astc", constantValues: MTLFunctionConstantValues()) } catch { print("empty consts: \(error)") }
let fd = MTLFunctionDescriptor(); fd.name = "astc"
for bits in 0..<4 {
    let cv = MTLFunctionConstantValues()
    var b0 = (bits & 1) != 0, b1 = (bits & 2) != 0
    for i in 0..<8 { var u: UInt32 = 4; cv.setConstantValue(&u, type: .uint, index: i) }
    cv.setConstantValue(&b0, type: .bool, index: 0); cv.setConstantValue(&b1, type: .bool, index: 1)
    do {
        let f = try lib.makeFunction(name: "astc", constantValues: cv)
        let p = try d.makeComputePipelineState(function: f)
        print("bits \(bits): tew \(p.threadExecutionWidth) maxTotal \(p.maxTotalThreadsPerThreadgroup)")
    } catch { print("bits \(bits): \(error)") }
}
