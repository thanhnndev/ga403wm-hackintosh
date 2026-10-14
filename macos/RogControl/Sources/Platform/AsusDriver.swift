// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AsusWmi user client (ABI: kexts/AsusWmi/asuswmi_abi.h, no sudo). Stateless: every call opens and closes the connection.
import Foundation
import IOKit

struct AsusState {
    var present = false, ac = true, fanCustom = false
    var profile: Int?, charge: Int?
    var cpuFan = 0, gpuFan = 0
    var ppt = [0, 0, 0]
    var ranges = [(15, 80), (25, 80), (35, 80)]
    var gpuMux: UInt32 = ~0, dgpu: UInt32 = ~0, baseTgp = 0
    var backlight: Int?, backlightMax = 0
    var batDesign = 0, batFull = 0, batNow = 0, batState = 0, batRate = 0   // mAh, mAh, mAh, _BST state, mA
    var kbd: Int?, slash: Int?, hid = false                                // ABI 3: keyboard light 0..3, packed Slash, N-KEY seen
    var lighting = false                                                    // the kext has the keyboard / Slash settings
}

enum Asus {
    static let abi: UInt32 = 3
    enum Selector: UInt32 { case state = 0, set = 1, fanRead = 2, fanWrite = 3, fanReset = 4 }
    enum Setting: UInt64 { case profile = 1, spl = 2, sppt = 3, fppt = 4, charge = 5, backlight = 6, kbd = 7, slash = 8 }

    private static func open() -> io_connect_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusWmi"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS ? connection : nil
    }

    private static func call(_ selector: Selector, scalars: [UInt64] = [], input: [UInt8] = [], outputCount: Int = 0) -> (kern_return_t, [UInt8]) {
        guard let connection = open() else { return (kIOReturnNotFound, []) }
        defer { IOServiceClose(connection) }
        var output = [UInt8](repeating: 0, count: outputCount)
        var outputSize = outputCount
        var scalars = scalars
        let status: kern_return_t = scalars.withUnsafeMutableBufferPointer { scalarBuffer in
            input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    IOConnectCallMethod(connection, selector.rawValue, scalarBuffer.baseAddress, UInt32(scalarBuffer.count),
                                        input.isEmpty ? nil : inputBuffer.baseAddress, inputBuffer.count,
                                        nil, nil, outputCount > 0 ? outputBuffer.baseAddress : nil, &outputSize)
                }
            }
        }
        return (status, Array(output.prefix(outputSize)))
    }

    static func state() -> AsusState {
        var state = AsusState()
        let (status, bytes) = call(.state, outputCount: 27 * 4)
        guard status == KERN_SUCCESS, bytes.count >= 24 * 4 else { return state }
        func word(_ index: Int) -> UInt32 { bytes.withUnsafeBytes { $0.load(fromByteOffset: index * 4, as: UInt32.self) } }
        func optional(_ index: Int) -> Int? { word(index) == ~0 ? nil : Int(word(index)) }
        guard word(0) >= 1, word(0) <= abi else { return state }      // ABI 1 and 2 (fewer words) still work
        state.present = true
        state.ac = word(1) & 1 != 0
        state.fanCustom = word(1) & 2 != 0
        state.profile = optional(2); state.charge = optional(3)
        state.cpuFan = Int(word(4)); state.gpuFan = Int(word(5))
        state.ppt = [Int(word(6)), Int(word(7)), Int(word(8))]
        state.ranges = [(Int(word(9)), Int(word(10))), (Int(word(11)), Int(word(12))), (Int(word(13)), Int(word(14)))]
        state.gpuMux = word(15); state.dgpu = word(16); state.baseTgp = Int(word(17))
        guard word(0) >= 2 else { return state }
        state.backlight = optional(18); state.backlightMax = Int(word(19))
        state.batDesign = Int(word(20)); state.batFull = Int(word(21)); state.batNow = Int(word(22))
        state.batState = Int(word(23) & 0xff); state.batRate = Int(word(23) >> 8)
        guard word(0) >= 3, bytes.count >= 27 * 4 else { return state }
        state.lighting = true
        state.kbd = optional(24); state.slash = optional(25); state.hid = word(26) != 0
        return state
    }

    @discardableResult
    static func set(_ setting: Setting, _ value: Int) -> kern_return_t {
        call(.set, scalars: [setting.rawValue, UInt64(value)]).0
    }

    static func fanCurve(fan: Int, profile: Int) -> [UInt8]? {
        let (status, bytes) = call(.fanRead, scalars: [UInt64(fan), UInt64(profile)], outputCount: 16)
        return status == KERN_SUCCESS && bytes.count == 16 ? bytes : nil
    }

    @discardableResult
    static func setFanCurve(fan: Int, _ curve: [UInt8]) -> kern_return_t {
        call(.fanWrite, scalars: [UInt64(fan)], input: curve).0
    }
}
