// setgain dB [UID]: sets the input gain (dB) on elements 1..4 of an input device (default Built-in Input)
import CoreAudio
import Foundation
var db = Float32(CommandLine.arguments[1])!
var uid = (CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppleHDAEngineInput:0,6,0,1,0:1") as CFString
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var d = AudioObjectID(0); var n = UInt32(4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &uid, &n, &d)
for el in UInt32(1)...4 { var va = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeDecibels, mScope: kAudioObjectPropertyScopeInput, mElement: el)
    if AudioObjectHasProperty(d, &va) { print("el\(el):", AudioObjectSetPropertyData(d, &va, 0, nil, 4, &db)) } }
