// SPDX-License-Identifier: BSD-3-Clause-Clear
// SimBench: fps (CADisplayLink callbacks per second, plus frames slower than 1.5x the target) and
// time from process start to the first drawn frame. Output: one "SIMBENCH ..." line per second on stdout.
import SwiftUI
import UIKit
import QuartzCore

func processStartSeconds() -> Double {
    var kp = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &kp, &size, nil, 0)
    let tv = kp.kp_proc.p_un.__p_starttime
    return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
}
func now() -> Double { var tv = timeval(); gettimeofday(&tv, nil); return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6 }

final class Meter: NSObject {
    static let shared = Meter()
    var link: CADisplayLink?
    var frames = 0, slow = 0, last = 0.0, windowStart = 0.0, firstFrame = true, seconds = 0
    var worst = 0.0
    func start() {
        setvbuf(stdout, nil, _IOLBF, 0)
        link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link?.add(to: .main, forMode: .common)
    }
    @objc func tick(_ l: CADisplayLink) {
        let t = l.timestamp
        if firstFrame {
            firstFrame = false
            print(String(format: "SIMBENCH first-frame %.0f ms after process start", (now() - processStartSeconds()) * 1000))
            last = t; windowStart = t; return
        }
        let dt = t - last; last = t; frames += 1
        if dt > (l.targetTimestamp - l.timestamp) * 1.5 + 0.0005 { slow += 1 }
        worst = max(worst, dt)
        if t - windowStart >= 1.0 {
            seconds += 1
            print(String(format: "SIMBENCH t=%d fps=%.1f slow=%d worst=%.1fms", seconds, Double(frames) / (t - windowStart), slow, worst * 1000))
            frames = 0; slow = 0; worst = 0; windowStart = t
        }
    }
}

struct ContentView: View {
    @State private var spin = false
    var body: some View {
        VStack {
            Text("SimBench").font(.largeTitle)
            ZStack {
                ForEach(0..<24) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hue: Double(i) / 24, saturation: 0.8, brightness: 0.9).opacity(0.7))
                        .frame(width: 40, height: 140).offset(y: -90)
                        .rotationEffect(.degrees(Double(i) * 15 + (spin ? 360 : 0)))
                        .blur(radius: 1)
                }
            }.frame(height: 320)
            ScrollView { LazyVStack { ForEach(0..<200) { i in Text("Row \(i)").frame(maxWidth: .infinity).padding(6).background(.thinMaterial) } } }
        }
        .onAppear { withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spin = true } }
    }
}

@main struct SimBenchApp: App {
    init() { Meter.shared.start() }
    var body: some Scene { WindowGroup { ContentView() } }
}
