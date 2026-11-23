// inctl [UID]: input data sources, volume/mute elements and controls of an input device (default Built-in Input)
import CoreAudio
import Foundation
let uidS = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppleHDAEngineInput:0,6,0,1,0:1"
func fcc(_ x: UInt32) -> String { String(bytes: withUnsafeBytes(of: x.bigEndian, Array.init), encoding: .ascii) ?? "?" }
func get<T>(_ d: AudioObjectID, _ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope, _ el: UInt32, _ v: T) -> (OSStatus, T) {
    var a = AudioObjectPropertyAddress(mSelector: s, mScope: sc, mElement: el); var x = v; var n = UInt32(MemoryLayout<T>.size)
    return (AudioObjectGetPropertyData(d, &a, 0, nil, &n, &x), x) }
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var uid = uidS as CFString; var d = AudioObjectID(0); var n = UInt32(4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), &uid, &n, &d)
let sc = kAudioObjectPropertyScopeInput
for el in UInt32(1)...4 { let v = get(d, kAudioDevicePropertyVolumeDecibels, sc, el, Float32(0)); if v.0 == 0 { print("el \(el): \(v.1) dB mute \(get(d, kAudioDevicePropertyMute, sc, el, UInt32(0)).1)") } }
print("datasource now:", fcc(get(d, kAudioDevicePropertyDataSource, sc, 0, UInt32(0)).1))
var dl = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSources, mScope: sc, mElement: 0)
var sz = UInt32(0); AudioObjectGetPropertyDataSize(d, &dl, 0, nil, &sz); var ids = [UInt32](repeating: 0, count: Int(sz)/4); AudioObjectGetPropertyData(d, &dl, 0, nil, &sz, &ids)
for i in ids {
    var nm: Unmanaged<CFString>?; var tr = AudioValueTranslation(mInputData: withUnsafeMutablePointer(to: &ids[ids.firstIndex(of: i)!]) { UnsafeMutableRawPointer($0) }, mInputDataSize: 4,
        mOutputData: withUnsafeMutablePointer(to: &nm) { UnsafeMutableRawPointer($0) }, mOutputDataSize: UInt32(MemoryLayout<CFString?>.size))
    var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSourceNameForIDCFString, mScope: sc, mElement: 0); var tsz = UInt32(MemoryLayout<AudioValueTranslation>.size)
    AudioObjectGetPropertyData(d, &ta, 0, nil, &tsz, &tr)
    print("source \(fcc(i)) \(nm?.takeRetainedValue() as String? ?? "")") }
if CommandLine.arguments.count > 2 { var v = UInt32(CommandLine.arguments[2].utf8.reduce(0) { $0 << 8 | UInt32($1) })
    var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: sc, mElement: 0)
    print("set source \(CommandLine.arguments[2]):", AudioObjectSetPropertyData(d, &sa, 0, nil, 4, &v)) }
