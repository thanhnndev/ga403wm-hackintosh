// Lists the VideoToolbox encoders on this machine (codec, encoder ID, hardware flag).
// build: swiftc -O vtlist.swift -o /tmp/vtlist
import VideoToolbox
var l: CFArray?
VTCopyVideoEncoderList(nil, &l)
for e in (l as! [[String: Any]]) { print(e[kVTVideoEncoderList_CodecName as String] ?? "", "|", e[kVTVideoEncoderList_EncoderID as String] ?? "", "| hw:", e["IsHardwareAccelerated"] ?? "-") }
