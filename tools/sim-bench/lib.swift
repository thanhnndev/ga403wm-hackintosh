// SPDX-License-Identifier: BSD-3-Clause-Clear
// Loads MTLSimDriver's default.metallib on the host device and prints every compute pipeline's
// threadExecutionWidth (0 = the MercuryPosterExtension SIGFPE). Function constants get their defaults or 0.
import Metal
setvbuf(stdout, nil, _IOLBF, 0)
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "simdriver.metallib"
guard let d = MTLCreateSystemDefaultDevice() else { print("no device"); exit(1) }
print("device: \(d.name)")
let lib = try! d.makeLibrary(URL: URL(fileURLWithPath: path))
for n in lib.functionNames.sorted() {
    let cv = MTLFunctionConstantValues()
    print("try \(n)")
    guard let f0 = lib.makeFunction(name: n) else { print("NIL  \(n)"); continue }
    if f0.functionType != .kernel { continue }
    for (name, c) in f0.functionConstantsDictionary {
        var z = [UInt64](repeating: 0, count: 4)
        cv.setConstantValue(&z, type: c.type, withName: name)
        _ = name
    }
    do {
        let f = try lib.makeFunction(name: n, constantValues: cv)
        let p = try d.makeComputePipelineState(function: f)
        print("\(p.threadExecutionWidth == 0 ? "ZERO" : "ok  ") \(n) tew \(p.threadExecutionWidth) maxTotal \(p.maxTotalThreadsPerThreadgroup) consts \(f0.functionConstantsDictionary.count)")
    } catch { print("ERR  \(n): \(error)") }
}
