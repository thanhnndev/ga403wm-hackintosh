// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// webgl-probe: one-shot WebGL check through WKWebView, i.e. the same WebKit GPU process Safari uses
// (com.apple.WebKit.GPU). Prints one JSON line: GPU process mode, masked + unmasked renderer, a readPixels result.
// Draws exactly one frame (clear + one triangle) and exits; never loops on the GPU. Hard timeout 25 s.
//
//   swiftc -O -o build/webgl-probe tools/890m/webgl-probe.swift
//   build/webgl-probe [--gpu-process on|off] [--mask on|off] [--webgl2]
//
// --gpu-process sets the WebKit feature UseGPUProcessForWebGLEnabled (default on, like Safari); --mask off clears
// MaskWebGLStringsEnabled so WEBGL_debug_renderer_info returns ANGLE's real renderer string. Both go through the private
// +[WKPreferences _features] / -[WKPreferences _setEnabled:forFeature:] (test harness only).
import AppKit
import WebKit

var gpuProcess = true, mask = false, webgl2 = false
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--gpu-process": gpuProcess = (it.next() ?? "on") != "off"
    case "--mask": mask = (it.next() ?? "off") == "on"
    case "--webgl2": webgl2 = true
    default: FileHandle.standardError.write("unknown argument \(a)\n".data(using: .utf8)!); exit(2)
    }
}

func emit(_ obj: [String: Any]) {
    var o = obj
    o["gpu_process"] = gpuProcess; o["mask"] = mask
    let d = try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    print(String(data: d, encoding: .utf8)!)
    fflush(stdout)
}

// Sets a WebKit feature by key; returns false when this WebKit has no such feature.
func setFeature(_ prefs: WKPreferences, _ key: String, _ on: Bool) -> Bool {
    let featuresSel = NSSelectorFromString("_features")
    let setSel = NSSelectorFromString("_setEnabled:forFeature:")
    guard let cls = WKPreferences.self as AnyObject as? NSObjectProtocol, cls.responds(to: featuresSel),
          prefs.responds(to: setSel),
          let list = cls.perform(featuresSel)?.takeUnretainedValue() as? [NSObject],
          let feature = list.first(where: { ($0.value(forKey: "key") as? String) == key }) else { return false }
    typealias SetFn = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
    let imp = prefs.method(for: setSel)
    unsafeBitCast(imp, to: SetFn.self)(prefs, setSel, on, feature)
    return true
}

let page = """
<!doctype html><html><body><canvas id=c width=64 height=64></canvas><script>
function run() {
  const r = { ok: false };
  try {
    const c = document.getElementById('c');
    const gl = c.getContext('\(webgl2 ? "webgl2" : "webgl")', { preserveDrawingBuffer: true });
    if (!gl) { r.error = 'no context'; return r; }
    r.version = gl.getParameter(gl.VERSION);
    r.renderer = gl.getParameter(gl.RENDERER);
    r.vendor = gl.getParameter(gl.VENDOR);
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    if (ext) {
      r.unmasked_renderer = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL);
      r.unmasked_vendor = gl.getParameter(ext.UNMASKED_VENDOR_WEBGL);
    }
    const vs = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vs, 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }');
    gl.compileShader(vs);
    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fs, 'precision mediump float; void main(){ gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0); }');
    gl.compileShader(fs);
    const pr = gl.createProgram();
    gl.attachShader(pr, vs); gl.attachShader(pr, fs); gl.linkProgram(pr);
    r.link_ok = !!gl.getProgramParameter(pr, gl.LINK_STATUS);
    if (!r.link_ok) r.link_log = gl.getProgramInfoLog(pr) + ' | ' + gl.getShaderInfoLog(vs) + ' | ' + gl.getShaderInfoLog(fs);
    gl.clearColor(1, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
    const b = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, b);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    gl.useProgram(pr);
    const loc = gl.getAttribLocation(pr, 'p');
    gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    const px = new Uint8Array(4);
    gl.readPixels(32, 32, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
    r.pixel = Array.from(px);
    r.gl_error = gl.getError();
    r.lost = gl.isContextLost();
    r.ok = r.link_ok && px[0] === 0 && px[1] === 255 && px[2] === 0;
  } catch (e) { r.error = String(e); }
  return r;
}
window.webkit.messageHandlers.probe.postMessage(JSON.stringify(run()));
</script></body></html>
"""

final class Probe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var view: WKWebView!
    var window: NSWindow!
    var features: [String: Bool] = [:]

    func start() {
        let cfg = WKWebViewConfiguration()
        features["UseGPUProcessForWebGLEnabled"] = setFeature(cfg.preferences, "UseGPUProcessForWebGLEnabled", gpuProcess)
        features["MaskWebGLStringsEnabled"] = setFeature(cfg.preferences, "MaskWebGLStringsEnabled", mask)
        features["WebGLEnabled"] = setFeature(cfg.preferences, "WebGLEnabled", true)
        cfg.userContentController.add(self, name: "probe")
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), configuration: cfg)
        view.navigationDelegate = self
        // A real (off-screen) window, so the page is not throttled as hidden.
        window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 64, height: 64), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        view.loadHTMLString(page, baseURL: nil)
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        var out: [String: Any] = ["features_set": features]
        if let s = m.body as? String, let d = s.data(using: .utf8),
           let r = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            out.merge(r) { a, _ in a }
        } else { out["error"] = "bad message" }
        emit(out)
        exit((out["ok"] as? Bool) == true ? 0 : 1)
    }

    func webViewWebContentProcessDidTerminate(_ v: WKWebView) {
        emit(["ok": false, "error": "web content process terminated", "features_set": features]); exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let probe = Probe()
probe.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
    emit(["ok": false, "error": "timeout (25 s)", "features_set": probe.features]); exit(3)
}
app.run()
