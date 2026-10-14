// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// CoreAudio lookups: the built-in output, the ROG Speakers device, and whether the headphone jack is the active data source.
import CoreAudio
import Foundation

enum AudioDevices {
    static let rogSpeakersUID = "com.itlmt7925.rogaudio.speakers"
    private static let headphoneDataSource: UInt32 = 0x6864706E     // 'hdpn'

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: 0)
    }

    private static var allDevices: [AudioObjectID] {
        var size: UInt32 = 0
        var devices = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &devices, 0, nil, &size) == 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devices, 0, nil, &size, &ids) == 0 else { return [] }
        return ids
    }

    private static func uid(of device: AudioObjectID) -> String? {
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var property = address(kAudioDevicePropertyDeviceUID)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &reference) == 0 else { return nil }
        return reference?.takeRetainedValue() as String?
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var size: UInt32 = 0
        var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == 0 && size > 0
    }

    private static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var property = address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &transport) == 0 else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    /// The UID of the machine's own speaker and headphone output, below the ROG DSP device.
    static func builtInOutputUID() -> String? {
        allDevices.first { isBuiltIn($0) && hasOutput($0) }.flatMap(uid(of:))
    }

    static func rogSpeakersAvailable() -> Bool {
        allDevices.contains { uid(of: $0) == rogSpeakersUID }
    }

    static func outputUID(for target: PlaybackTarget) -> String? {
        switch target {
        case .direct: builtInOutputUID()
        case .dsp: rogSpeakersAvailable() ? rogSpeakersUID : nil
        }
    }

    /// True when the built-in output currently routes to the headphone jack.
    static func headphonesPlugged() -> Bool {
        guard let device = allDevices.first(where: { isBuiltIn($0) && hasOutput($0) }) else { return false }
        var source: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var property = address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &source) == 0 else { return false }
        return source == headphoneDataSource
    }
}
