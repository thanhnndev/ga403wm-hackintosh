// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// RogControl: a small ROG Control Center for macOS on the GA403WM (ROG Zephyrus G14 2025): performance mode (Silent,
// Performance, Turbo, Manual power limits), battery charge limit, CPU temperature / package power / fan speeds, GPU MUX
// state. Settings are kept per power source (AC / battery) and applied again when the source changes and at login, as asusd
// does. Native app window and menu bar popover, SwiftUI, SF Symbols only.
//
// Inspired by asusctl / rog-control-center (asus-linux.org, Luke Jones and contributors, MPL-2.0); no code is taken from it.
// Talks to kexts/AsusWmi through its user client (ABI: kexts/AsusWmi/asuswmi_abi.h, no sudo) and reads the sysctl
// debug.amdcppc.sensors of kexts/AmdCppc.
//
// Command line (same binary):
//   RogControl --bench [seconds]   runs Silent, Performance and Turbo in turn under full load on every CPU and prints package
//                                  power, Tctl, fan speeds and clocks per mode; puts the previous mode back afterwards
// Build: scripts/build-rogcontrol.sh
import AppKit
import SwiftUI
import Charts
import IOKit
import IOKit.ps

// ---- driver access (asuswmi_abi.h) -----------------------------------------------------------------------------------------
struct AsusState {
    var present = false, ac = true, fanCustom = false
    var profile: Int? = nil, charge: Int? = nil
    var cpuFan = 0, gpuFan = 0
    var ppt = [0, 0, 0]
    var ranges = [(15, 80), (25, 80), (35, 80)]
    var gpuMux: UInt32 = ~0, dgpu: UInt32 = ~0, baseTgp = 0
    var backlight: Int? = nil, backlightMax = 0
    var batDesign = 0, batFull = 0, batNow = 0, batState = 0, batRate = 0   // mAh, mAh, mAh, _BST state, mA
    var kbd: Int? = nil, slash: Int? = nil, hid = false                   // ABI 3: keyboard light 0..3, Slash (packed), N-KEY seen
    var lighting = false                                                    // the kext has the keyboard / Slash settings
}

// Slash lighting (asuswmi_abi.h ASUS_SLASH_*): mode index, brightness 0..3 (0 = off), interval 0..5
struct Slash: Equatable {
    static let modes = ["Static", "Bounce", "Slash", "Loading", "Bit Stream", "Transmission", "Flow", "Flux",
                        "Phantom", "Spectrum", "Hazard", "Interfacing", "Ramp", "Game Over", "Start", "Buzzer"]
    var mode = 2, bright = 2, interval = 0
    var packed: Int { mode | (bright << 8) | (interval << 12) }
    init(mode: Int = 2, bright: Int = 2, interval: Int = 0) { self.mode = mode; self.bright = bright; self.interval = interval }
    init(packed v: Int) { mode = v & 0xff; bright = (v >> 8) & 0xf; interval = (v >> 12) & 0xf }
}

enum Asus {
    static let abi: UInt32 = 3
    enum Sel: UInt32 { case state = 0, set = 1, fanRead = 2, fanWrite = 3, fanReset = 4 }
    enum What: UInt64 { case profile = 1, spl = 2, sppt = 3, fppt = 4, charge = 5, backlight = 6, kbd = 7, slash = 8 }

    static func open() -> io_connect_t? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusWmi"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        return IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS ? conn : nil
    }

    static func call(_ sel: Sel, scalars: [UInt64] = [], input: [UInt8]? = nil, outCount: Int = 0) -> (kern_return_t, [UInt8]) {
        guard let c = open() else { return (kIOReturnNotFound, []) }
        defer { IOServiceClose(c) }
        var out = [UInt8](repeating: 0, count: outCount)
        var outSize = outCount
        var sc = scalars
        let inp = input ?? []
        let kr: kern_return_t = sc.withUnsafeMutableBufferPointer { sb in
            inp.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    IOConnectCallMethod(c, sel.rawValue, sb.baseAddress, UInt32(sb.count), inp.isEmpty ? nil : ib.baseAddress, ib.count,
                                        nil, nil, outCount > 0 ? ob.baseAddress : nil, &outSize)
                }
            }
        }
        return (kr, Array(out.prefix(outSize)))
    }

    static func state() -> AsusState {
        var s = AsusState()
        let (kr, b) = call(.state, outCount: 27 * 4)
        guard kr == KERN_SUCCESS, b.count >= 24 * 4 else { return s }
        func w(_ i: Int) -> UInt32 { b.withUnsafeBytes { $0.load(fromByteOffset: i * 4, as: UInt32.self) } }
        guard w(0) >= 1, w(0) <= abi else { return s }          // ABI 1 / 2 (fewer words) still work
        s.present = true
        s.ac = w(1) & 1 != 0; s.fanCustom = w(1) & 2 != 0
        s.profile = w(2) == ~0 ? nil : Int(w(2)); s.charge = w(3) == ~0 ? nil : Int(w(3))
        s.cpuFan = Int(w(4)); s.gpuFan = Int(w(5))
        s.ppt = [Int(w(6)), Int(w(7)), Int(w(8))]
        s.ranges = [(Int(w(9)), Int(w(10))), (Int(w(11)), Int(w(12))), (Int(w(13)), Int(w(14)))]
        s.gpuMux = w(15); s.dgpu = w(16); s.baseTgp = Int(w(17))
        guard w(0) >= 2 else { return s }
        s.backlight = w(18) == ~0 ? nil : Int(w(18)); s.backlightMax = Int(w(19))
        s.batDesign = Int(w(20)); s.batFull = Int(w(21)); s.batNow = Int(w(22))
        s.batState = Int(w(23) & 0xff); s.batRate = Int(w(23) >> 8)
        guard w(0) >= 3, b.count >= 27 * 4 else { return s }
        s.lighting = true
        s.kbd = w(24) == ~0 ? nil : Int(w(24)); s.slash = w(25) == ~0 ? nil : Int(w(25)); s.hid = w(26) != 0
        return s
    }

    @discardableResult static func set(_ what: What, _ v: Int) -> kern_return_t { call(.set, scalars: [what.rawValue, UInt64(v)]).0 }
    static func fanCurve(fan: Int, profile: Int) -> [UInt8]? {
        let (kr, b) = call(.fanRead, scalars: [UInt64(fan), UInt64(profile)], outCount: 16)
        return kr == KERN_SUCCESS && b.count == 16 ? b : nil
    }
    @discardableResult static func setFanCurve(fan: Int, _ c: [UInt8]) -> kern_return_t { call(.fanWrite, scalars: [UInt64(fan)], input: c).0 }
    @discardableResult static func fanReset() -> kern_return_t { call(.fanReset).0 }
}

// AmdCppc: "tctl=<m°C> pkg_mw=<mW>" (power averaged since the previous read) and the per-CPU clock report
enum Sensors {
    static func string(_ name: String) -> String? {
        var len = 0
        guard sysctlbyname(name, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: len + 1)
        guard sysctlbyname(name, &buf, &len, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    static func read() -> (tctl: Double?, watts: Double?) {
        guard let s = string("debug.amdcppc.sensors") else { return (nil, nil) }
        var t: Double?, w: Double?
        for kv in s.split(separator: " ") {
            let p = kv.split(separator: "="); guard p.count == 2, let v = Double(p[1]) else { continue }
            if p[0] == "tctl", v > -1 { t = v / 1000 }
            if p[0] == "pkg_mw", v > 0 { w = v / 1000 }
        }
        return (t, w)
    }
    // average effective MHz of the busy CPUs 0-7 (Zen 5) and 8-23 (Zen 5c) from debug.amdcppc.freq
    static func clocks() -> (big: Int, little: Int)? {
        guard let s = string("debug.amdcppc.freq") else { return nil }
        var big: [Int] = [], little: [Int] = []
        for part in s.split(separator: "|").dropFirst() {
            let f = part.split(separator: " ")
            guard f.count >= 2, let cpu = Int(f[0]) else { continue }
            let v = f[1].split(separator: "/")
            guard v.count >= 2, let mhz = Int(v[0]), let busy = Int(v[1].dropLast()), busy >= 50 else { continue }
            if cpu < 8 { big.append(mhz) } else { little.append(mhz) }
        }
        func avg(_ a: [Int]) -> Int { a.isEmpty ? 0 : a.reduce(0, +) / a.count }
        return (avg(big), avg(little))
    }
}

// ---- modes and settings ------------------------------------------------------------------------------------------------------
enum Mode: String, CaseIterable, Identifiable {
    case silent, performance, turbo, manual
    var id: String { rawValue }
    var title: String { ["silent": "Silent", "performance": "Performance", "turbo": "Turbo", "manual": "Manual"][rawValue]! }
    var symbol: String {
        ["silent": "leaf", "performance": "gauge.with.dots.needle.50percent", "turbo": "flame", "manual": "slider.horizontal.3"][rawValue]!
    }
    var firmwareProfile: Int { self == .silent ? 2 : self == .turbo ? 1 : 0 }   // asus-wmi: 0 balanced, 1 overboost, 2 silent
    static func from(profile: Int?) -> Mode? { profile == 2 ? .silent : profile == 1 ? .turbo : profile == 0 ? .performance : nil }
}

// One setting set per power source, in UserDefaults ("ac.mode", "battery.spl", ...)
struct SourceSettings {
    var mode: Mode
    var spl: Int, sppt: Int, fppt: Int
    var fanBase: Mode            // whose firmware fan curve Manual uses (silent / performance / turbo)
    static func load(ac: Bool) -> SourceSettings {
        let d = UserDefaults.standard, k = ac ? "ac." : "battery."
        func i(_ n: String, _ def: Int) -> Int { d.object(forKey: k + n) == nil ? def : d.integer(forKey: k + n) }
        return SourceSettings(mode: Mode(rawValue: d.string(forKey: k + "mode") ?? "") ?? .performance,
                              spl: i("spl", ac ? 45 : 30), sppt: i("sppt", ac ? 65 : 35), fppt: i("fppt", ac ? 80 : 50),
                              fanBase: Mode(rawValue: d.string(forKey: k + "fanBase") ?? "") ?? .performance)
    }
    func save(ac: Bool) {
        let d = UserDefaults.standard, k = ac ? "ac." : "battery."
        d.set(mode.rawValue, forKey: k + "mode"); d.set(spl, forKey: k + "spl"); d.set(sppt, forKey: k + "sppt")
        d.set(fppt, forKey: k + "fppt"); d.set(fanBase.rawValue, forKey: k + "fanBase")
    }
}

// ---- login item (a user LaunchAgent; no signing needed) ------------------------------------------------------------------
enum LoginItem {
    static let label = "com.itlmt7925.RogControl"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    static func set(_ on: Bool) {
        if !on { try? FileManager.default.removeItem(at: plist); return }
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let d: [String: Any] = ["Label": label, "ProgramArguments": [exe, "--background"], "RunAtLoad": true, "ProcessType": "Interactive",
                                "LimitLoadToSessionType": "Aqua"]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (d as NSDictionary).write(to: plist, atomically: true)
    }
}

// ---- apply ---------------------------------------------------------------------------------------------------------------
enum Apply {
    // Returns an error text or nil. Manual: profile first (fresh firmware state), then the chosen firmware fan curves as custom
    // curves (needed for power limits on this board), then the limits, kept in order SPL <= SPPT <= FPPT and in range.
    static func mode(_ s: SourceSettings, state st: AsusState) -> String? {
        var m = s.mode
        if m == .turbo && !st.ac { m = .performance }               // as Armoury Crate: no Turbo on battery
        if m != .manual {
            return Asus.set(.profile, m.firmwareProfile) == KERN_SUCCESS ? nil : "could not set the profile"
        }
        guard Asus.set(.profile, Mode.performance.firmwareProfile) == KERN_SUCCESS else { return "could not set the profile" }
        let base = s.fanBase == .turbo && !st.ac ? Mode.performance : s.fanBase
        for fan in 0..<2 {
            guard let c = Asus.fanCurve(fan: fan, profile: base.firmwareProfile) else { return "could not read the fan curve" }
            guard Asus.setFanCurve(fan: fan, c) == KERN_SUCCESS else { return "the fan curve was refused" }
        }
        let r = st.ranges
        let spl = min(max(s.spl, r[0].0), r[0].1)
        let sppt = min(max(max(s.sppt, spl), r[1].0), r[1].1)
        let fppt = min(max(max(s.fppt, sppt), r[2].0), r[2].1)
        for (w, v) in [(Asus.What.spl, spl), (.sppt, sppt), (.fppt, fppt)] where Asus.set(w, v) != KERN_SUCCESS {
            return "power limit \(v) W was refused"
        }
        return nil
    }
}

// ---- model -------------------------------------------------------------------------------------------------------------------
@MainActor
final class RogModel: ObservableObject {
    @Published var st = AsusState()
    @Published var tctl: Double?
    @Published var watts: Double?
    @Published var settings = SourceSettings.load(ac: true)
    @Published var charge = UserDefaults.standard.object(forKey: "charge") == nil ? 100 : UserDefaults.standard.integer(forKey: "charge")
    @Published var kbd = UserDefaults.standard.object(forKey: "kbd") == nil ? 2 : UserDefaults.standard.integer(forKey: "kbd")
    @Published var slash = UserDefaults.standard.object(forKey: "slash") == nil ? Slash() : Slash(packed: UserDefaults.standard.integer(forKey: "slash"))
    @Published var message = ""
    @Published var loginEnabled = LoginItem.enabled
    @Published var curve: [UInt8]? = nil
    @Published var gpuCurve: [UInt8]? = nil
    @Published var curveMode: Mode = .performance
    @Published var profileError = ""
    @Published var chargeError = ""
    @Published var lightingError = ""
    var activeMode: Mode? { st.present ? (st.fanCustom ? .manual : Mode.from(profile: st.profile)) : nil }
    var modeLabel: String { activeMode?.title ?? "Unavailable" }
    var currentSlash: Slash { st.slash.map { Slash(packed: $0) } ?? slash }
    var manualDirty: Bool {
        let saved = SourceSettings.load(ac: st.ac)
        return settings.spl != saved.spl || settings.sppt != saved.sppt || settings.fppt != saved.fppt || settings.fanBase != saved.fanBase
    }
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var lastAC: Bool?
    var visible = false { didSet { schedule() } }

    init() {
        refresh()
        // first run: keep what the firmware is doing now instead of imposing a default
        let d = UserDefaults.standard
        if st.present, d.string(forKey: st.ac ? "ac.mode" : "battery.mode") == nil, let m = Mode.from(profile: st.profile) {
            var s = SourceSettings.load(ac: st.ac); s.mode = m; s.save(ac: st.ac)
        }
        if st.present, d.object(forKey: "charge") == nil, let c = st.charge, (20...100).contains(c) { charge = c; d.set(c, forKey: "charge") }
        settings = SourceSettings.load(ac: st.ac)
        applyAll(reason: "start")
        applyLighting()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // the keyboard comes back from sleep with its own defaults: give it a moment, then send ours again
            // bind self once (a `self?` inside the delayed closure is a captured weak var, which older toolchains reject there)
            guard let model = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { model.applyLighting() } }
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let m = Unmanaged<RogModel>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { m.powerChanged() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        schedule()
    }

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: visible ? 2 : 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let previousMode = activeMode
        st = Asus.state()
        let s = Sensors.read()
        tctl = s.tctl; watts = s.watts
        if st.present, lastAC != nil, lastAC != st.ac { powerChanged() }
        lastAC = st.ac
        if previousMode != activeMode { loadCurve() }
        onChange?()
    }

    func powerChanged() {
        let now = Asus.state()
        guard now.present, now.ac != lastAC else { return }
        st = now; lastAC = now.ac
        settings = SourceSettings.load(ac: now.ac)
        applyAll(reason: now.ac ? "on AC" : "on battery")
    }

    func applyAll(reason: String) {
        guard st.present else { message = "AsusWmi is not loaded"; return }
        profileError = Apply.mode(settings, state: st) ?? ""
        chargeError = ""
        if st.charge != charge, Asus.set(.charge, charge) != KERN_SUCCESS { chargeError = "Charge limit was not applied." }
        st = Asus.state()
        loadCurve()
        let errs = [profileError, chargeError].filter { !$0.isEmpty }
        message = errs.isEmpty ? "\(settings.mode.title) applied (\(reason))" : errs.joined(separator: "; ")
        onChange?()
    }

    func choose(_ m: Mode) {
        settings.mode = m
        settings.save(ac: st.ac)
        applyAll(reason: st.ac ? "AC" : "battery")
    }
    func saveManual() { settings.save(ac: st.ac); applyAll(reason: "manual limits") }
    func setCharge(_ v: Int) {
        charge = v; UserDefaults.standard.set(v, forKey: "charge")
        chargeError = Asus.set(.charge, v) == KERN_SUCCESS ? "" : "Charge limit was not applied."
        message = chargeError.isEmpty ? "charge limit \(v) %" : chargeError
        st = Asus.state()
    }
    func applyLighting() {
        guard st.lighting else { return }
        var errs: [String] = []
        if Asus.set(.kbd, kbd) != KERN_SUCCESS { errs.append("keyboard light refused") }
        if Asus.set(.slash, slash.packed) != KERN_SUCCESS { errs.append("Slash refused") }
        st = Asus.state()
        lightingError = errs.joined(separator: "; ")
        if !errs.isEmpty { message = lightingError }
    }
    func setKbd(_ v: Int) {
        kbd = v; UserDefaults.standard.set(v, forKey: "kbd")
        lightingError = Asus.set(.kbd, v) == KERN_SUCCESS ? "" : "Keyboard light was not applied. Check the keyboard connection."
        message = lightingError.isEmpty ? "keyboard light \(v)" : lightingError
        st = Asus.state()
    }
    func setSlash(_ s: Slash) {
        slash = s; UserDefaults.standard.set(s.packed, forKey: "slash")
        lightingError = Asus.set(.slash, s.packed) == KERN_SUCCESS ? "" : "Slash lighting was not applied. Check the keyboard connection."
        message = lightingError.isEmpty ? (s.bright == 0 ? "Slash off" : "Slash \(Slash.modes[s.mode])") : lightingError
        st = Asus.state()
    }
    var batteryLine: String {
        guard st.batDesign > 5 else { return "battery data not available from the firmware" }
        var s = ""
        if st.batFull > 0 { s += String(format: "health %.0f %% (%d / %d mAh)", 100.0 * Double(st.batFull) / Double(st.batDesign), st.batFull, st.batDesign) }
        if st.batFull > 0, st.batNow > 0 { s += String(format: " · %.0f %%", 100.0 * Double(st.batNow) / Double(st.batFull)) }
        if st.batState & 2 != 0 { s += " · charging \(st.batRate) mA" } else if st.batState & 1 != 0 { s += " · \(st.batRate) mA" }
        return s
    }
    func loadCurve() {
        // Manual shows the selected firmware reference, not an editable or measured RPM curve.
        curveMode = settings.mode == .manual ? settings.fanBase : (Mode.from(profile: st.profile) ?? .performance)
        if curveMode == .turbo && !st.ac { curveMode = .performance }
        curve = st.present ? Asus.fanCurve(fan: 0, profile: curveMode.firmwareProfile) : nil
        gpuCurve = st.present ? Asus.fanCurve(fan: 1, profile: curveMode.firmwareProfile) : nil
    }
    func setLogin(_ on: Bool) { LoginItem.set(on); loginEnabled = LoginItem.enabled }
}

// ---- views ---------------------------------------------------------------------------------------------------------------------
struct Stat: View {
    let symbol: String, value: String, label: String
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// ABI: eight temperatures followed by eight fan duties. Raw firmware can contain
// 255 endpoints and repeated temperatures; never extrapolate or invent replacements.
struct FanCurvePoint: Identifiable {
    let id: Int
    let temperature: Int
    let duty: Int
    let segment: Int
}
struct FanCurveData {
    let points: [FanCurvePoint]
    let omitted: Int
    init(_ bytes: [UInt8]) {
        guard bytes.count == 16 else { points = []; omitted = bytes.count == 0 ? 0 : 8; return }
        var valid: [FanCurvePoint] = []
        var skipped = 0, segment = 0
        var previous: Int?
        for i in 0..<8 {
            let temperature = Int(bytes[i]), duty = Int(bytes[8 + i])
            guard (20...105).contains(temperature), (0...100).contains(duty),
                  previous == nil || temperature >= previous! else {
                skipped += 1; segment += 1; continue
            }
            valid.append(FanCurvePoint(id: i, temperature: temperature, duty: duty, segment: segment))
            previous = temperature
        }
        points = valid; omitted = skipped
    }
}

struct CurveChart: View {
    let c: [UInt8]
    let compact: Bool
    @State private var hovered: Int?
    private var data: FanCurveData { FanCurveData(c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fan duty (%)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let point = data.points.first(where: { $0.id == hovered }) {
                    Text("\(point.temperature)°C · \(point.duty)%").font(.caption).monospacedDigit()
                }
            }.frame(height: 16)
            if data.points.isEmpty {
                Text("No valid fan curve data.").font(.callout).foregroundStyle(.secondary).frame(height: 100)
            } else {
                Chart(data.points) { point in
                    LineMark(x: .value("Temperature", point.temperature), y: .value("Fan duty", point.duty),
                             series: .value("Segment", point.segment))
                        .interpolationMethod(.linear).lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Temperature", point.temperature), y: .value("Fan duty", point.duty))
                        .symbolSize(point.id == hovered ? 70 : 24).foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: 20...105).chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: [20, 40, 60, 80, 100]) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)°") } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%") } }
                    }
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let origin = geometry[proxy.plotAreaFrame].origin
                                    let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                                    hovered = data.points.min { a, b in
                                        distance(a, to: local, proxy: proxy) < distance(b, to: local, proxy: proxy)
                                    }?.id
                                case .ended: hovered = nil
                                }
                            }
                    }
                }
                .frame(height: compact ? 130 : 220)
                Text("Temperature (°C)").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            if data.omitted > 0 {
                Text("\(data.omitted) firmware point(s) outside the valid range or order are not plotted.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fan duty by temperature")
        .accessibilityValue(data.points.map { "\($0.temperature) degrees Celsius, \($0.duty) percent" }.joined(separator: "; "))
    }
    private func distance(_ point: FanCurvePoint, to position: CGPoint, proxy: ChartProxy) -> CGFloat {
        guard let x = proxy.position(forX: point.temperature), let y = proxy.position(forY: point.duty) else { return .infinity }
        return pow(x - position.x, 2) + pow(y - position.y, 2)
    }
}

struct FanCurveView: View {
    @ObservedObject var m: RogModel
    var compact = false
    @State private var fan = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(m.curveMode.title) firmware curve").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("Fan", selection: $fan) { Text("CPU").tag(0); Text("GPU").tag(1) }
                    .pickerStyle(.segmented).frame(width: 105).controlSize(.small)
            }
            if let bytes = fan == 0 ? m.curve : m.gpuCurve { CurveChart(c: bytes, compact: compact) }
            else { Text("Fan curve unavailable from firmware.").font(.caption).foregroundStyle(.secondary) }
            if !compact {
                Text("Firmware reference, not live RPM. Hover a point to read its temperature and duty.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LimitSlider: View {
    let name: String, help: String
    @Binding var value: Int
    let range: (Int, Int)
    var body: some View {
        HStack {
            Text(name).font(.system(size: 12)).frame(width: 44, alignment: .leading).help(help)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.0)...Double(max(range.1, range.0 + 1))).controlSize(.small)
            Text("\(value) W").font(.system(size: 12)).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }
}

enum RogPage: String, CaseIterable, Identifiable {
    case overview = "Overview", performance = "Performance", lighting = "Lighting", battery = "Battery & Display", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .performance: return "gauge.with.dots.needle.50percent"
        case .lighting: return "keyboard"
        case .battery: return "battery.75"
        case .settings: return "gearshape"
        }
    }
}

struct RogSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct RogControls: View {
    @ObservedObject var m: RogModel
    let page: RogPage
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !m.st.present {
                Label("Hardware controls unavailable. Load AsusWmi through OpenCore to connect your G14.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if page == .overview {
                RogSection(title: "Live telemetry") {
                    HStack(spacing: 16) {
                        Stat(symbol: "thermometer.medium", value: m.tctl.map { String(format: "%.0f°", $0) } ?? "–", label: "CPU temperature")
                        Stat(symbol: "bolt", value: m.watts.map { String(format: "%.1f W", $0) } ?? "–", label: "Package power")
                        Stat(symbol: "fan", value: m.st.present ? "\(m.st.cpuFan)" : "–", label: "CPU fan · RPM")
                        Stat(symbol: "fan", value: m.st.present ? "\(m.st.gpuFan)" : "–", label: "GPU fan · RPM")
                    }
                }
            }
            if page == .overview || page == .performance {
                RogSection(title: "Performance mode") { modes.disabled(!m.st.present) }
            }
            if page == .performance {
                RogSection(title: "Power & cooling") {
                    VStack(alignment: .leading, spacing: 12) {
                        manualControls
                        FanCurveView(m: m)
                        if m.settings.mode != .manual {
                            Text("Firmware manages power limits in this mode. Choose Manual to adjust them.").font(.callout).foregroundStyle(.secondary)
                        }
                    }.disabled(!m.st.present)
                }
            }
            if page == .lighting {
                RogSection(title: "Keyboard & Slash lighting") {
                    VStack(alignment: .leading, spacing: 12) {
                        lightingControls
                        if !m.st.lighting { Text("Lighting is unavailable. AsusWmi ABI 3 and the N-KEY keyboard are required.").foregroundStyle(.secondary) }
                    }.disabled(!m.st.present)
                }
            }
            if page == .overview || page == .battery {
                RogSection(title: "Battery care") {
                    VStack(alignment: .leading, spacing: 12) {
                        batteryControls
                        Text("60% for desk use · 80% for everyday use · 100% for travel").font(.callout).foregroundStyle(.secondary)
                    }.disabled(!m.st.present)
                }
            }
            if page == .overview {
                RogSection(title: "Graphics") { Text(gpuLine).font(.callout).foregroundStyle(.secondary) }
            }
            if page == .settings {
                RogSection(title: "Startup") {
                    Toggle("Open at Login", isOn: Binding(get: { m.loginEnabled }, set: { m.setLogin($0) })).toggleStyle(.switch)
                    Text("Runs quietly in the menu bar at login. Closing the window keeps hardware control active.").font(.callout).foregroundStyle(.secondary)
                }
                RogSection(title: "About ROG Control") {
                    Text("ROG Zephyrus G14 · GA403WM").font(.headline)
                    Text("Settings are saved independently for AC and battery, then restored when your power source changes.").foregroundStyle(.secondary)
                    Link("Created by thanhnndev · github.com/thanhnndev", destination: URL(string: "https://github.com/thanhnndev")!)
                    Link("Inspired by asusctl and the asus-linux community", destination: URL(string: "https://asus-linux.org")!)
                }
            }
            if !m.message.isEmpty {
                Label(m.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    var manualControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if m.settings.mode == .manual {
                VStack(alignment: .leading, spacing: 4) {
                    LimitSlider(name: "SPL", help: "PL1, sustained power", value: $m.settings.spl, range: m.st.ranges[0])
                    LimitSlider(name: "SPPT", help: "PL2, slow boost (minutes)", value: $m.settings.sppt, range: m.st.ranges[1])
                    LimitSlider(name: "FPPT", help: "PL3, fast boost (seconds)", value: $m.settings.fppt, range: m.st.ranges[2])
                    HStack {
                        Text("Fans").font(.system(size: 12))
                        Picker("", selection: $m.settings.fanBase) {
                            ForEach([Mode.silent, .performance, .turbo]) { Text($0.title + " curve").tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 150)
                        .onChange(of: m.settings.fanBase) { _ in m.loadCurve() }
                        Spacer()
                        Button("Apply") { m.saveManual() }.controlSize(.small)
                    }
                    HStack {
                        Text((m.manualDirty || m.activeMode != .manual || !m.profileError.isEmpty) ? "Changes not applied" : "Applied limits: " + m.st.ppt.map { "\($0) W" }.joined(separator: " / "))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

        }
    }
    var lightingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if m.st.lighting {
                KeyboardRow(level: m.st.kbd) { m.setKbd($0) }
                slashControls
            }
        }
    }
    var slashControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if m.st.lighting {
                HStack(spacing: 6) {
                    Toggle("Slash", isOn: Binding(get: { (m.st.slash.map { Slash(packed: $0).bright } ?? 0) > 0 }, set: { on in
                        var s = m.currentSlash; s.bright = on ? (UserDefaults.standard.object(forKey: "slash.on.bright") as? Int ?? 2) : 0
                        if !on { UserDefaults.standard.set(m.currentSlash.bright, forKey: "slash.on.bright") }
                        m.setSlash(s)
                    }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                    Picker("", selection: Binding(get: { m.currentSlash.mode }, set: { v in var s = m.currentSlash; s.mode = v; if s.bright == 0 { s.bright = 2 }; m.setSlash(s) })) {
                        ForEach(0..<Slash.modes.count, id: \.self) { Text(Slash.modes[$0]).tag($0) }
                    }
                    .labelsHidden().controlSize(.small).frame(maxWidth: 130)
                    Spacer()
                }
                .help("Slash lighting on the lid (Fn+F4 switches it on / off)")
                if m.currentSlash.bright > 0 {
                    HStack(spacing: 6) {
                        Text("brightness").font(.system(size: 11)).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { m.currentSlash.bright }, set: { v in var s = m.currentSlash; s.bright = v; m.setSlash(s) })) {
                            ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 90)
                        Text("interval").font(.system(size: 11)).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { m.currentSlash.interval }, set: { v in var s = m.currentSlash; s.interval = v; m.setSlash(s) })) {
                            ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 52)
                        Spacer()
                    }
                }
            }

        }
    }
    var batteryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach([60, 80, 100], id: \.self) { v in
                    ChoiceButton(title: "\(v)%", selected: m.st.charge == v) { m.setCharge(v) }
                }
                Spacer()
                Text(m.st.charge.map { "limit \($0) %" } ?? "–").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(m.batteryLine).font(.system(size: 11)).foregroundStyle(.secondary)

        }
    }
    var modes: some View {
        ModeRow(active: m.activeMode, ac: m.st.ac, compact: compact) { m.choose($0) }
    }
    var gpuLine: String {
        var s = "GPU: "
        let mux = m.st.gpuMux
        s += mux == ~0 ? "MUX unknown" : (mux & 1 == 0 ? "dGPU only (MUX)" : "Hybrid")
        if m.st.dgpu != ~0 && m.st.dgpu & 1 != 0 { s += ", dGPU disabled" }
        if m.st.baseTgp > 0 { s += ", base TGP \(m.st.baseTgp) W" }
        return s
    }
}


// The mode row and the keyboard-light row take plain values (what is active, which level) instead of reading the model:
// the popover showed "Active: Silent" next to a Performance highlight that never moved. Their identity follows the value, so a
// change always rebuilds them, whatever the observation path above them does.
struct ModeRow: View {
    let active: Mode?
    let ac: Bool
    let compact: Bool
    let choose: (Mode) -> Void
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(Mode.allCases) { mode in
                let selected = active == mode
                let unavailable = mode == .turbo && !ac
                Button { choose(mode) } label: {
                    VStack(spacing: compact ? 5 : 8) {
                        Image(systemName: mode.symbol).font(.system(size: compact ? 16 : 20))
                        Text(mode.title).font(.system(size: compact ? 11 : 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, compact ? 6 : 16)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.clear))
                }
                .buttonStyle(.plain).disabled(unavailable).opacity(unavailable ? 0.4 : 1)
                .accessibilityLabel(mode.title + (selected ? ", selected" : ""))
                .help(unavailable ? "Turbo needs the AC adapter" : mode.title)
            }
        }
        .id("mode-\(active?.rawValue ?? "none")-\(ac)")
    }
}

struct KeyboardRow: View {
    let level: Int?
    let set: (Int) -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text("Keyboard").font(.system(size: 12))
            ForEach(0...3, id: \.self) { v in
                ChoiceButton(title: ["Off", "Low", "Med", "High"][v], selected: level == v) { set(v) }.disabled(level == nil)
            }
            Spacer()
        }
        .id("kbd-\(level ?? -1)")
        .help("Keyboard backlight (Fn+F2 / Fn+F3 step it)")
    }
}

struct ChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .fixedSize().padding(.horizontal, 8).padding(.vertical, 5)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.accentColor : Color.clear))
        }.buttonStyle(.plain).accessibilityLabel(title + (selected ? ", active" : ""))
    }
}

// The popover's manual limits and Slash rows are RogControls sections wrapped in their own View with its own @ObservedObject
// (calling `RogControls(...).x` straight from ContentView.body leaves them without an observer). The mode row and the keyboard
// light row are ModeRow / KeyboardRow, built in ContentView.body from plain values.
struct PopoverPart: View {
    enum Part { case manual, slash }
    @ObservedObject var m: RogModel
    let part: Part
    @ViewBuilder var body: some View {
        let c = RogControls(m: m, page: .overview, compact: true)
        switch part {
        case .manual: c.manualControls
        case .slash: c.slashControls
        }
    }
}

// Primary surface: stable compact rows, immediate controls, optional details.
struct ContentView: View {
    @ObservedObject var m: RogModel
    let openWindow: () -> Void
    @State private var showCurves = false
    private var controls: RogControls { RogControls(m: m, page: .overview, compact: true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROG Control").font(.system(size: 13, weight: .semibold))
                Spacer()
                Label(m.st.present ? (m.st.ac ? "AC" : "Battery") : "Disconnected",
                      systemImage: m.st.ac ? "powerplug" : "battery.75")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                quickStat(m.tctl.map { String(format: "%.0f°C", $0) } ?? "–", "CPU")
                quickStat(m.watts.map { String(format: "%.1f W", $0) } ?? "–", "Power")
                quickStat(m.st.present ? "\(m.st.cpuFan)" : "–", "CPU RPM")
                quickStat(m.st.present ? "\(m.st.gpuFan)" : "–", "GPU RPM")
            }
            ModeRow(active: m.activeMode, ac: m.st.ac, compact: true) { m.choose($0) }.disabled(!m.st.present)
            HStack {
                Text("Active: \(m.modeLabel)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Editing \(m.st.ac ? "AC" : "battery") settings").font(.caption).foregroundStyle(.secondary)
            }
            inlineError(m.profileError)
            // Optional curve content scrolls; daily controls and footer stay in place.
            if m.settings.mode == .manual {
                PopoverPart(m: m, part: .manual).disabled(!m.st.present)
            }
            Divider()
            HStack(spacing: 8) {
                Text("Charge limit").font(.system(size: 12)).frame(width: 76, alignment: .leading)
                ForEach([60, 80, 100], id: \.self) { value in
                    ChoiceButton(title: "\(value)%", selected: m.st.charge == value) { m.setCharge(value) }
                }
                Spacer(minLength: 0)
            }.disabled(!m.st.present || m.st.charge == nil)
            inlineError(m.chargeError)
            if m.st.batFull > 0 {
                HStack {
                    Text("Battery \(min(100, max(0, m.st.batNow * 100 / m.st.batFull)))%")
                    Spacer()
                    Text(m.st.batState & 2 != 0 ? "Charging" : m.st.ac ? "On AC" : "Discharging")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if m.st.lighting {
                KeyboardRow(level: m.st.kbd) { m.setKbd($0) }.disabled(!m.st.present)
                PopoverPart(m: m, part: .slash).disabled(!m.st.present)
                inlineError(m.lightingError)
            } else {
                Text("Keyboard / Slash unavailable").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Fan curves", isExpanded: $showCurves) {
                ScrollView { FanCurveView(m: m, compact: true).padding(.top, 8) }.frame(height: curveDetailHeight)
            }.font(.caption)
            if !m.st.present { Text("AsusWmi is not loaded. Hardware controls are unavailable.").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Menu("Settings") {
                    Toggle("Open at Login", isOn: Binding(get: { m.loginEnabled }, set: { m.setLogin($0) }))
                    Text(m.batteryLine)
                    Text(controls.gpuLine)
                    Button("Created by thanhnndev (GitHub)") { NSWorkspace.shared.open(URL(string: "https://github.com/thanhnndev")!) }
                    Button("Quit ROG Control") { NSApp.terminate(nil) }
                }.menuStyle(.borderlessButton).fixedSize().font(.caption)
                Spacer()
                Button("Open app", action: openWindow).buttonStyle(.borderless).font(.caption)
            }
        }.padding(14).frame(width: 350)
    }
    private var curveDetailHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 800) - (m.settings.mode == .manual ? 590 : 490)
        return min(210, max(95, available))
    }
    private func inlineError(_ text: String) -> some View {
        Group {
            if !text.isEmpty {
                Label(text, systemImage: "exclamationmark.triangle").font(.caption)
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func quickStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RogWindowView: View {
    @ObservedObject var m: RogModel
    @State private var page: RogPage = .overview
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ROG Control").font(.system(size: 21, weight: .semibold))
                    Text("ZEPHYRUS G14").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.top, 20)
                VStack(spacing: 4) {
                    ForEach(RogPage.allCases) { destination in
                        Button { page = destination } label: {
                            Label(destination.rawValue, systemImage: destination.symbol)
                                .font(.system(size: 13, weight: page == destination ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .foregroundStyle(page == destination ? Color.accentColor : Color.primary)
                                .background(page == destination ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Label(m.st.ac ? "Connected to AC" : "On battery", systemImage: m.st.ac ? "powerplug" : "battery.75")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }.padding(12).frame(width: 210).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(page.rawValue).font(.system(size: 24, weight: .semibold))
                        Text("\(m.st.ac ? "AC" : "Battery") settings · Active mode: \(m.modeLabel)").font(.callout).foregroundStyle(.secondary)
                    }
                    RogControls(m: m, page: page)
                }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .underPageBackgroundColor))
        }.frame(minWidth: 800, minHeight: 600)
    }
}

// ---- status item -------------------------------------------------------------------------------------------------------------
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    var model: RogModel!
    var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        model = RogModel()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ContentView(m: model, openWindow: { [weak self] in self?.showWindow() }))
        item.button?.target = self
        item.button?.action = #selector(toggle)
        model.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        setupMenus()
        if !CommandLine.arguments.contains("--background") { showWindow() }
    }

    @objc func toggle() {
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refresh()
        model.loadCurve()
        model.visible = true
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ n: Notification) { updateVisibility() }
    func updateVisibility() { model.visible = popover.isShown || window?.isVisible == true }
    func windowWillClose(_ n: Notification) {
        model.visible = popover.isShown
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    @objc func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "ROG Control"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 800, height: 640)
            w.contentViewController = NSHostingController(rootView: RogWindowView(m: model))
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("RogControl.MainWindow")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refresh(); model.loadCurve(); updateVisibility()
    }
    @objc func refreshNow() { model.refresh(); model.loadCurve() }
    @objc func showAbout() {
        let credits = NSMutableAttributedString(string: "Created by thanhnndev\ngithub.com/thanhnndev\n\nInspired by asusctl and the asus-linux community.",
                                                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.addAttribute(.link, value: URL(string: "https://github.com/thanhnndev")!, range: (credits.string as NSString).range(of: "github.com/thanhnndev"))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
    func setupMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About ROG Control", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ROG Control", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ROG Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem(); menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        let open = windowMenu.addItem(withTitle: "Open ROG Control", action: #selector(showWindow), keyEquivalent: "0"); open.target = self
        let refresh = windowMenu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r"); refresh.target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    func updateIcon() {
        guard let b = item.button else { return }
        let mode = model.activeMode ?? .performance
        let img = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: "ROG: \(mode.title)")
        img?.isTemplate = true
        b.image = img
        var tip = "ROG: \(model.modeLabel)"
        if let t = model.tctl { tip += String(format: " · CPU %.0f°C", t) }
        if let w = model.watts { tip += String(format: " · %.1f W", w) }
        b.toolTip = tip
    }
}

// ---- command line: profile bench -------------------------------------------------------------------------------------------------
final class Load {
    private var running = true
    private let lock = NSLock()
    func start(_ n: Int) {
        for _ in 0..<n {
            Thread.detachNewThread { [self] in
                var x: UInt64 = 88172645463325252
                while lock.withLock({ running }) {
                    for _ in 0..<200_000 { x ^= x << 13; x ^= x >> 7; x ^= x << 17 }
                }
                if x == 42 { print("") }
            }
        }
    }
    func stop() { lock.withLock { running = false } }
}

func bench(seconds: Int) -> Int32 {
    let st0 = Asus.state()
    guard st0.present else { print("AsusWmi is not loaded"); return 1 }
    let ncpu = ProcessInfo.processInfo.activeProcessorCount
    print("RogControl bench: \(ncpu) busy threads, \(seconds) s per mode, \(st0.ac ? "on AC" : "on battery"); previous profile \(st0.profile.map(String.init) ?? "?")")
    print("mode         avg W   max W   Tctl max   CPU fan   GPU fan   Zen5 MHz   Zen5c MHz")
    var modes: [Mode] = [.silent, .performance]
    if st0.ac { modes.append(.turbo) }
    for mode in modes {
        guard Asus.set(.profile, mode.firmwareProfile) == KERN_SUCCESS else { print("\(mode.title): profile refused"); continue }
        Thread.sleep(forTimeInterval: 3)                       // let the firmware settle, fans spin down/up a little
        let load = Load(); load.start(ncpu)
        _ = Sensors.read()
        var ws: [Double] = [], tmax = 0.0, cf = 0, gf = 0
        for i in 0..<seconds {
            Thread.sleep(forTimeInterval: 1)
            let s = Sensors.read()
            if i >= 2, let w = s.watts { ws.append(w) }       // skip the first seconds of the fast boost
            tmax = max(tmax, s.tctl ?? 0)
            let st = Asus.state(); cf = max(cf, st.cpuFan); gf = max(gf, st.gpuFan)
        }
        let clk = Sensors.clocks()
        load.stop()
        let avg = ws.isEmpty ? 0 : ws.reduce(0, +) / Double(ws.count)
        print(String(format: "%-11@ %6.1f  %6.1f   %6.1f°C   %7d   %7d   %8d   %9d", mode.title as NSString, avg, ws.max() ?? 0, tmax, cf, gf,
                     clk?.big ?? 0, clk?.little ?? 0))
        Thread.sleep(forTimeInterval: 5)                       // cool down between modes
    }
    if let p = st0.profile { Asus.set(.profile, p) }
    print("previous profile restored (custom fan curves and power limits, if any, are reset; RogControl re-applies its mode at the next power change or start)")
    return 0
}

let args = CommandLine.arguments
if args.count >= 2 && args[1] == "--bench" {
    exit(bench(seconds: args.count >= 3 ? max(5, Int(args[2]) ?? 20) : 20))
}

MainActor.assumeIsolated {                     // top-level code runs on the main thread
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
