// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// The laptop itself: performance mode and limits, live telemetry, battery charge limit, keyboard and Slash lighting.
import AppKit
import IOKit.ps
import Observation

@MainActor
@Observable
final class LaptopModel {
    private(set) var state = AsusState()
    private(set) var temperature: Double?
    private(set) var watts: Double?
    private(set) var temperatureHistory: [TelemetrySample] = []
    private(set) var powerHistory: [TelemetrySample] = []
    private(set) var cpuCurve: [UInt8]?
    private(set) var gpuCurve: [UInt8]?
    private(set) var curveBase: PerformanceMode = .performance
    private(set) var modeError = ""
    private(set) var chargeError = ""
    private(set) var lightingError = ""

    var plan = PowerPlan.load(onAC: true)
    private(set) var loginItemEnabled = LoginItem.isEnabled

    @ObservationIgnored private var chargeLimit = LaptopModel.stored("charge", default: 100)
    @ObservationIgnored private var keyboardLevel = LaptopModel.stored("kbd", default: 2)
    @ObservationIgnored private var slashSetting = LaptopModel.storedSlash()
    @ObservationIgnored private var lastAC: Bool?
    @ObservationIgnored private var sampleCounter = 0

    // ---- derived state ------------------------------------------------------------------------------------------------------
    var isAvailable: Bool { state.present }
    var activeMode: PerformanceMode? {
        guard state.present else { return nil }
        return state.fanCustom ? .manual : PerformanceMode.from(profile: state.profile)
    }
    var batteryPercent: Int? { state.batFull > 0 ? min(100, max(0, state.batNow * 100 / state.batFull)) : nil }
    var batteryHealth: Int? {
        state.batDesign > 5 && state.batFull > 0 ? Int((100.0 * Double(state.batFull) / Double(state.batDesign)).rounded()) : nil
    }
    var isCharging: Bool { state.batState & 2 != 0 }
    var powerSourceTitle: String { state.ac ? "Plugged in" : "On battery" }
    var batteryTitle: String { isCharging ? "Charging" : state.ac ? "On AC" : "Discharging" }
    var graphicsTitle: String {
        var text = state.gpuMux == ~0 ? "MUX unknown" : (state.gpuMux & 1 == 0 ? "Discrete GPU only" : "Hybrid graphics")
        if state.dgpu != ~0 && state.dgpu & 1 != 0 { text += ", discrete GPU disabled" }
        return text
    }
    var currentSlash: Slash { state.slash.map { Slash(packed: $0) } ?? slashSetting }
    var hasUnappliedLimits: Bool {
        let saved = PowerPlan.load(onAC: state.ac)
        return plan != saved || activeMode != .manual || !modeError.isEmpty
    }
    var limitRanges: [ClosedRange<Double>] {
        state.ranges.map { Double($0.0)...Double(max($0.1, $0.0 + 1)) }
    }
    var statusLine: String {
        guard state.present else { return "Driver not loaded" }
        let parts = [powerSourceTitle, batteryPercent.map { "\($0)%" }].compactMap { $0 }
        return parts.joined(separator: ", ")
    }

    // ---- bindable settings --------------------------------------------------------------------------------------------------
    var splWatts: Double {
        get { Double(plan.spl) }
        set { plan.spl = Int(newValue.rounded()) }
    }
    var spptWatts: Double {
        get { Double(plan.sppt) }
        set { plan.sppt = Int(newValue.rounded()) }
    }
    var fpptWatts: Double {
        get { Double(plan.fppt) }
        set { plan.fppt = Int(newValue.rounded()) }
    }
    var fanBase: PerformanceMode {
        get { plan.fanBase }
        set { plan.fanBase = newValue; loadCurves() }
    }
    var startsAtLogin: Bool {
        get { loginItemEnabled }
        set { LoginItem.set(newValue); loginItemEnabled = LoginItem.isEnabled }
    }
    var chargeLimitSetting: Int {
        get { state.charge ?? chargeLimit }
        set { setChargeLimit(newValue) }
    }
    var keyboardLight: Int {
        get { state.kbd ?? keyboardLevel }
        set { setKeyboardLight(newValue) }
    }
    var slashEnabled: Bool {
        get { currentSlash.brightness > 0 }
        set { setSlashEnabled(newValue) }
    }
    var slashAnimation: Int {
        get { currentSlash.animation }
        set { var slash = currentSlash; slash.animation = newValue; setSlash(slash) }
    }
    var slashBrightness: Int {
        get { max(1, currentSlash.brightness) }
        set { var slash = currentSlash; slash.brightness = newValue; setSlash(slash) }
    }
    var slashInterval: Int {
        get { currentSlash.interval }
        set { var slash = currentSlash; slash.interval = newValue; setSlash(slash) }
    }

    // ---- lifecycle ----------------------------------------------------------------------------------------------------------
    init() {
        refresh()
        let defaults = UserDefaults.standard
        // First run: keep what the firmware is doing now instead of imposing a default.
        if state.present, defaults.string(forKey: state.ac ? "ac.mode" : "battery.mode") == nil,
           let mode = PerformanceMode.from(profile: state.profile) {
            var first = PowerPlan.load(onAC: state.ac)
            first.mode = mode
            first.save(onAC: state.ac)
        }
        if state.present, defaults.object(forKey: "charge") == nil, let charge = state.charge, (20...100).contains(charge) {
            chargeLimit = charge
            defaults.set(charge, forKey: "charge")
        }
        plan = PowerPlan.load(onAC: state.ac)
        applyPlan(reason: "start")
        applyLighting()
        observeWake()
        observePowerSource()
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The keyboard comes back from sleep with its own defaults: give it a moment, then send ours again.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.applyLighting()
            }
        }
    }

    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<LaptopModel>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { model.powerSourceChanged() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func refresh() {
        let previous = activeMode
        state = Asus.state()
        let reading = Sensors.read()
        temperature = reading.temperature
        watts = reading.watts
        record(reading.temperature, into: \.temperatureHistory)
        record(reading.watts, into: \.powerHistory)
        if state.present, let lastAC, lastAC != state.ac { powerSourceChanged() }
        lastAC = state.ac
        if previous != activeMode || cpuCurve == nil { loadCurves() }
    }

    private func record(_ value: Double?, into path: ReferenceWritableKeyPath<LaptopModel, [TelemetrySample]>) {
        guard let value else { return }
        sampleCounter += 1
        var samples = self[keyPath: path]
        samples.append(TelemetrySample(id: sampleCounter, value: value))
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }
        self[keyPath: path] = samples
    }

    private func powerSourceChanged() {
        let now = Asus.state()
        guard now.present, now.ac != lastAC else { return }
        state = now
        lastAC = now.ac
        plan = PowerPlan.load(onAC: now.ac)
        applyPlan(reason: now.ac ? "on AC" : "on battery")
    }

    // ---- performance --------------------------------------------------------------------------------------------------------
    func select(_ mode: PerformanceMode) {
        plan.mode = mode
        plan.save(onAC: state.ac)
        applyPlan(reason: state.ac ? "AC" : "battery")
    }

    func applyLimits() {
        plan.save(onAC: state.ac)
        applyPlan(reason: "manual limits")
    }

    private func applyPlan(reason: String) {
        guard state.present else { return }
        modeError = ModeApplier.apply(plan, state: state) ?? ""
        chargeError = ""
        if state.charge != chargeLimit, Asus.set(.charge, chargeLimit) != KERN_SUCCESS { chargeError = "The charge limit was not applied." }
        state = Asus.state()
        loadCurves()
    }

    private func loadCurves() {
        // Manual shows the selected firmware reference, not an editable or measured RPM curve.
        var base = plan.mode == .manual ? plan.fanBase : (PerformanceMode.from(profile: state.profile) ?? .performance)
        if base == .turbo && !state.ac { base = .performance }
        curveBase = base
        cpuCurve = state.present ? Asus.fanCurve(fan: 0, profile: base.firmwareProfile) : nil
        gpuCurve = state.present ? Asus.fanCurve(fan: 1, profile: base.firmwareProfile) : nil
    }

    // ---- battery ------------------------------------------------------------------------------------------------------------
    private func setChargeLimit(_ value: Int) {
        chargeLimit = value
        UserDefaults.standard.set(value, forKey: "charge")
        chargeError = Asus.set(.charge, value) == KERN_SUCCESS ? "" : "The charge limit was not applied."
        state = Asus.state()
    }

    // ---- lighting -----------------------------------------------------------------------------------------------------------
    func applyLighting() {
        guard state.lighting else { return }
        var failures: [String] = []
        if Asus.set(.kbd, keyboardLevel) != KERN_SUCCESS { failures.append("keyboard light") }
        if Asus.set(.slash, slashSetting.packed) != KERN_SUCCESS { failures.append("Slash lighting") }
        state = Asus.state()
        lightingError = failures.isEmpty ? "" : "The keyboard refused: " + failures.joined(separator: ", ") + "."
    }

    private func setKeyboardLight(_ value: Int) {
        keyboardLevel = value
        UserDefaults.standard.set(value, forKey: "kbd")
        lightingError = Asus.set(.kbd, value) == KERN_SUCCESS ? "" : "The keyboard light was not applied. Check the keyboard connection."
        state = Asus.state()
    }

    private func setSlash(_ slash: Slash) {
        slashSetting = slash
        UserDefaults.standard.set(slash.packed, forKey: "slash")
        lightingError = Asus.set(.slash, slash.packed) == KERN_SUCCESS ? "" : "Slash lighting was not applied. Check the keyboard connection."
        state = Asus.state()
    }

    private func setSlashEnabled(_ enabled: Bool) {
        var slash = currentSlash
        let defaults = UserDefaults.standard
        if enabled {
            let remembered = defaults.object(forKey: "slash.on.bright") as? Int ?? 2
            slash.brightness = remembered == 0 ? 2 : remembered
        } else {
            if slash.brightness > 0 { defaults.set(slash.brightness, forKey: "slash.on.bright") }
            slash.brightness = 0
        }
        setSlash(slash)
    }

    // ---- persisted defaults -------------------------------------------------------------------------------------------------
    private static func stored(_ key: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.integer(forKey: key)
    }

    private static func storedSlash() -> Slash {
        UserDefaults.standard.object(forKey: "slash") == nil ? Slash() : Slash(packed: UserDefaults.standard.integer(forKey: "slash"))
    }
}
