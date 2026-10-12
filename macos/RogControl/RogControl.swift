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
    @Published var dim = UserDefaults.standard.object(forKey: "dim") as? Bool ?? true
    @Published var message = ""
    @Published var loginEnabled = LoginItem.enabled
    @Published var curve: [UInt8]? = nil       // CPU fan curve of the Manual fan base, for the small chart
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var lastAC: Bool?
    var visible = false { didSet { schedule() } }
    let dimmer = Dimmer()

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
        dimmer.enabled = dim
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // the keyboard comes back from sleep with its own defaults: give it a moment, then send ours again
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { self?.applyLighting() } }
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
        st = Asus.state()
        let s = Sensors.read()
        tctl = s.tctl; if s.watts != nil { watts = s.watts }
        if st.present, lastAC != nil, lastAC != st.ac { powerChanged() }
        lastAC = st.ac
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
        var errs: [String] = []
        if let e = Apply.mode(settings, state: st) { errs.append(e) }
        if st.charge != charge, Asus.set(.charge, charge) != KERN_SUCCESS { errs.append("charge limit refused") }
        loadCurve()
        st = Asus.state()
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
        message = Asus.set(.charge, v) == KERN_SUCCESS ? "charge limit \(v) %" : "charge limit refused"
        st = Asus.state()
    }
    func applyLighting() {
        guard st.lighting else { return }
        var errs: [String] = []
        if Asus.set(.kbd, kbd) != KERN_SUCCESS { errs.append("keyboard light refused") }
        if Asus.set(.slash, slash.packed) != KERN_SUCCESS { errs.append("Slash refused") }
        st = Asus.state()
        if !errs.isEmpty { message = errs.joined(separator: "; ") }
    }
    func setDim(_ on: Bool) {
        dim = on; UserDefaults.standard.set(on, forKey: "dim")
        dimmer.enabled = on
    }
    func setKbd(_ v: Int) {
        kbd = v; UserDefaults.standard.set(v, forKey: "kbd")
        message = Asus.set(.kbd, v) == KERN_SUCCESS ? "keyboard light \(v)" : "keyboard light refused (keyboard not found?)"
        st = Asus.state()
    }
    func setSlash(_ s: Slash) {
        slash = s; UserDefaults.standard.set(s.packed, forKey: "slash")
        message = Asus.set(.slash, s.packed) == KERN_SUCCESS ? (s.bright == 0 ? "Slash off" : "Slash \(Slash.modes[s.mode])")
                                                             : "Slash refused (keyboard not found?)"
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
    func loadCurve() { curve = Asus.fanCurve(fan: 0, profile: (settings.mode == .manual ? settings.fanBase : settings.mode).firmwareProfile) }
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

struct CurveChart: View {
    let c: [UInt8]
    var body: some View {
        GeometryReader { g in
            let pts = (0..<8).map { i -> CGPoint in
                let t = (Double(c[i]) - 20) / 85, d = Double(c[8 + i]) / 100
                return CGPoint(x: g.size.width * t, y: g.size.height * (1 - d))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                Path { p in p.addLines(pts) }.stroke(Color.accentColor, lineWidth: 1.5)
                ForEach(0..<8, id: \.self) { i in Circle().fill(Color.accentColor).frame(width: 4, height: 4).position(pts[i]) }
            }
        }
        .frame(height: 54)
        .help((0..<8).map { "\(c[$0])°C \(c[8 + $0])%" }.joined(separator: "  "))
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
                   in: Double(range.0)...Double(max(range.1, range.0 + 1)), step: 1).controlSize(.small)
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
    var subtitle: String {
        switch self {
        case .overview: return "Your G14, at a glance."
        case .performance: return "Find the balance between power and quiet."
        case .lighting: return "Make your keyboard and lid your own."
        case .battery: return "Care for your battery and OLED display."
        case .settings: return "Make ROG Control part of your routine."
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
                                    Spacer()
                                    Button("Apply") { m.saveManual() }.controlSize(.small)
                                }
                            }
                        }
                        if let c = m.curve { CurveChart(c: c) }

                        if m.settings.mode != .manual {
                            Text("Firmware manages power limits in this mode. Choose Manual to adjust them.").font(.callout).foregroundStyle(.secondary)
                        }
                    }.disabled(!m.st.present)
                }
            }
            if page == .lighting {
                RogSection(title: "Keyboard & Slash lighting") {
                    VStack(alignment: .leading, spacing: 12) {
                        if m.st.lighting {
                            HStack(spacing: 6) {
                                Image(systemName: "keyboard").font(.system(size: 11)).foregroundStyle(.secondary)
                                ForEach(0...3, id: \.self) { v in
                                    Button(v == 0 ? "Off" : "\(v)") { m.setKbd(v) }
                                        .controlSize(.small).buttonStyle(.bordered)
                                        .tint(m.kbd == v ? .accentColor : nil)
                                }
                                Spacer()
                            }
                            .help("Keyboard backlight (Fn+F2 / Fn+F3 step it)")
                            HStack(spacing: 6) {
                                Toggle("Slash", isOn: Binding(get: { m.slash.bright > 0 }, set: { on in
                                    var s = m.slash; s.bright = on ? (UserDefaults.standard.object(forKey: "slash.on.bright") as? Int ?? 2) : 0
                                    if !on { UserDefaults.standard.set(m.slash.bright, forKey: "slash.on.bright") }
                                    m.setSlash(s)
                                }))
                                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                                Picker("", selection: Binding(get: { m.slash.mode }, set: { v in var s = m.slash; s.mode = v; if s.bright == 0 { s.bright = 2 }; m.setSlash(s) })) {
                                    ForEach(0..<Slash.modes.count, id: \.self) { Text(Slash.modes[$0]).tag($0) }
                                }
                                .labelsHidden().controlSize(.small).frame(maxWidth: 130)
                                Spacer()
                            }
                            .help("Slash lighting on the lid (Fn+F4 switches it on / off)")
                            if m.slash.bright > 0 {
                                HStack(spacing: 6) {
                                    Text("brightness").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Picker("", selection: Binding(get: { m.slash.bright }, set: { v in var s = m.slash; s.bright = v; m.setSlash(s) })) {
                                        ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                                    }
                                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 90)
                                    Text("interval").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Picker("", selection: Binding(get: { m.slash.interval }, set: { v in var s = m.slash; s.interval = v; m.setSlash(s) })) {
                                        ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                                    }
                                    .labelsHidden().controlSize(.small).frame(width: 52)
                                    Spacer()
                                }
                            }
                        }

                        if !m.st.lighting { Text("Lighting is unavailable. AsusWmi ABI 3 and the N-KEY keyboard are required.").foregroundStyle(.secondary) }
                    }.disabled(!m.st.present)
                }
            }
            if page == .overview || page == .battery {
                RogSection(title: "Battery care") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            ForEach([60, 80, 100], id: \.self) { v in
                                Button("\(v) %") { m.setCharge(v) }
                                    .controlSize(.small).buttonStyle(.bordered)
                                    .tint(m.charge == v ? .accentColor : nil)
                            }
                            Spacer()
                            Text(m.st.charge.map { "limit \($0) %" } ?? "–").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(m.batteryLine).font(.system(size: 11)).foregroundStyle(.secondary)

                        Text("60% for desk use · 80% for everyday use · 100% for travel").font(.callout).foregroundStyle(.secondary)
                    }.disabled(!m.st.present)
                }
            }
            if page == .battery {
                RogSection(title: "OLED display") {
                    Toggle("Software dimming", isOn: Binding(get: { m.dim }, set: { m.setDim($0) })).toggleStyle(.switch)
                    Text("Follows the system brightness slider and Fn+F7 / Fn+F8 on the built-in OLED.").font(.callout).foregroundStyle(.secondary)
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
                    Link("Inspired by asusctl and the asus-linux community", destination: URL(string: "https://asus-linux.org")!)
                }
            }
            if !m.message.isEmpty {
                Label(m.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    var modes: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { mode in
                let selected = m.settings.mode == mode
                let unavailable = mode == .turbo && !m.st.ac
                Button { m.choose(mode) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: mode.symbol).font(.system(size: 20))
                        Text(mode.title).font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.clear))
                }
                .buttonStyle(.plain).disabled(unavailable).opacity(unavailable ? 0.4 : 1)
                .accessibilityLabel(mode.title + (selected ? ", selected" : ""))
                .help(unavailable ? "Turbo needs the AC adapter" : mode.title)
            }
        }
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


struct ContentView: View {
    @ObservedObject var m: RogModel
    let openWindow: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROG Control").font(.headline)
                    Text("Zephyrus G14").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(m.st.ac ? "AC power" : "Battery", systemImage: m.st.ac ? "powerplug" : "battery.75").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Stat(symbol: "thermometer.medium", value: m.tctl.map { String(format: "%.0f°", $0) } ?? "–", label: "CPU")
                Stat(symbol: "bolt", value: m.watts.map { String(format: "%.1f W", $0) } ?? "–", label: "Power")
            }.padding(.vertical, 8)
            RogControls(m: m, page: .overview).modes.disabled(!m.st.present)
            if !m.st.present { Text("AsusWmi is not loaded.").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("Open ROG Control", action: openWindow).buttonStyle(.borderedProminent)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }.padding(20).frame(width: 340)
    }
}

struct RogWindowView: View {
    @ObservedObject var m: RogModel
    @State private var page: RogPage = .overview
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
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
                        Text(page.rawValue).font(.system(size: 30, weight: .semibold))
                        Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    RogControls(m: m, page: page)
                }.padding(32).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Color(nsColor: .underPageBackgroundColor))
        }.frame(minWidth: 800, minHeight: 600)
    }
}

// ---- software dimming of the built-in OLED -----------------------------------------------------------------------------------
// NullMoth sets the panel brightness through NVKMS (the BIOS reports an AUX backlight), which this Samsung OLED does not follow,
// and its framebuffer has no gamma table (setGammaTable is a stub), so the brightness slider and Fn+F7 / Fn+F8 would move
// without effect. Dimmer follows the built-in display's brightness (DisplayServices: the value the slider and the keys set)
// and darkens that screen with a black, click-through window above everything else. An OLED shows black as off pixels, so this
// lowers the light (and the power) as a backlight would; only the pointer stays at full brightness.
@MainActor
final class Dimmer {
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let get: GetBrightness? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let f = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(f, to: GetBrightness.self)
    }()
    static let floor: CGFloat = 0.15            // pixel scale at brightness 0 (about 2 % of the light), so the screen stays usable
    private var win: NSWindow?
    private var timer: Timer?
    var enabled = false {
        didSet {
            timer?.invalidate(); timer = nil
            if enabled {
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
                tick()
            } else { win?.orderOut(nil) }
        }
    }

    // brightness is perceptual (the slider), pixel values are gamma encoded: scaling them linearly by it is close to right
    func tick() {
        guard enabled, let get = Dimmer.get,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { win?.orderOut(nil); return }
        var b: Float = 1
        guard get(id, &b) == 0 else { win?.orderOut(nil); return }
        let alpha = 1 - (Dimmer.floor + (1 - Dimmer.floor) * CGFloat(min(max(b, 0), 1)))
        if alpha < 0.005 { win?.orderOut(nil); return }
        let w = win ?? make()
        if w.frame != screen.frame { w.setFrame(screen.frame, display: false) }
        if abs(w.alphaValue - alpha) > 0.001 { w.alphaValue = alpha }
        if !w.isVisible { w.orderFrontRegardless() }
    }

    private func make() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.sharingType = .none                   // not in screenshots and recordings
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))   // above the menu bar, Dock, menus
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win = w
        return w
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
    func setupMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About ROG Control", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
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
        let mode = model.settings.mode
        let img = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: "ROG: \(mode.title)")
        img?.isTemplate = true
        b.image = img
        var tip = "ROG: \(mode.title)"
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
