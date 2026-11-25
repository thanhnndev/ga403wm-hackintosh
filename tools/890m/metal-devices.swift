// SPDX-License-Identifier: BSD-3-Clause-Clear
// Lists the Metal devices this process gets (890M bring-up: does NVMTLDriver/RADV hand out a device?).
//   swiftc -O metal-devices.swift -o build/metal-devices && RADV_DEBUG=startup build/metal-devices
import Metal
let devs = MTLCopyAllDevices()
print("Metal devices: \(devs.count)")
for d in devs {
    print(" \(d.name) | lowPower \(d.isLowPower) | headless \(d.isHeadless) | unified \(d.hasUnifiedMemory)"
        + " | maxBuffer \(d.maxBufferLength >> 20) MB | registryID 0x\(String(d.registryID, radix: 16))")
}
