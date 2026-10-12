// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// ItlWiFi: menu bar Wi-Fi control for itlmt7925: a popover with the current network, scan list, join with a
// password (inline), disconnect / forget, open at login. SwiftUI in an NSPopover; SF Symbols only.
// Talks to the kext through its user client (ABI: kexts/itlmt7925/itl_uc_abi.h) and reads the wifi-* registry properties.
// Saved passwords live in ~/Library/Application Support/ItlWiFi/networks.json (mode 0600), never in the kext's Info.plist and
// not in the keychain: this app is ad-hoc signed, so every rebuild is a new code identity and the keychain asked the user
// ("ItlWiFi wants to use your confidential information ...") for each item again.
// Build: scripts/build-itlwifi.sh
import AppKit
import SwiftUI
import IOKit

// ---- driver access -------------------------------------------------------------------------------------------------------
struct WifiNet { let ssid: String; let channel: Int; let rssi: Int; let security: String
    var joinable: Bool { security == "wpa2" || security == "wpa2/wpa3" }
    var locked: Bool { security != "open" } }

struct WifiStatus {
    var present = false, state = "absent", error = "", ssid = "", channel = 0, rssi = 0, rate = 0, scanGen = 0
    var nets: [WifiNet] = []
    var events: [String] = []                   // wifi-events: "<seconds since boot>s <what happened>", oldest first
}

enum Driver {
    static let abi: UInt32 = 1
    enum Sel: UInt32 { case scan = 0, join = 1, disconnect = 2 }

    static func service() -> io_service_t { IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("itlmt7925")) }

    static func status() -> WifiStatus {
        var s = WifiStatus()
        let svc = service(); guard svc != 0 else { return s }
        defer { IOObjectRelease(svc) }
        func prop(_ k: String) -> Any? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
        func num(_ k: String) -> Int { (prop(k) as? NSNumber).map { Int(Int32(truncatingIfNeeded: $0.int64Value)) } ?? 0 }
        s.present = true
        s.state = prop("wifi-state") as? String ?? "off"
        s.error = prop("wifi-error") as? String ?? ""
        s.ssid = prop("wifi-ssid") as? String ?? ""
        s.events = (prop("wifi-events") as? String ?? "").split(separator: "\n").map(String.init)
        s.channel = num("wifi-channel"); s.rssi = num("wifi-rssi"); s.rate = num("wifi-rate"); s.scanGen = num("wifi-scan-gen")
        for d in prop("wifi-networks") as? [[String: Any]] ?? [] {
            guard let ssid = d["ssid"] as? String, !ssid.isEmpty else { continue }
            let rssi = (d["rssi"] as? NSNumber).map { Int(Int32(truncatingIfNeeded: $0.int64Value)) } ?? 0
            s.nets.append(WifiNet(ssid: ssid, channel: (d["channel"] as? NSNumber)?.intValue ?? 0, rssi: rssi,
                                  security: d["security"] as? String ?? "?"))
        }
        // one entry per SSID: the strongest BSS
        var best: [String: WifiNet] = [:]
        for n in s.nets { if let b = best[n.ssid], (b.rssi != 0 && b.rssi >= n.rssi) || n.rssi == 0 { continue }; best[n.ssid] = n }
        s.nets = best.values.sorted { ($0.rssi == 0 ? -200 : $0.rssi) > ($1.rssi == 0 ? -200 : $1.rssi) }
        return s
    }

    @discardableResult
    static func call(_ sel: Sel, input: UnsafeRawBufferPointer? = nil) -> kern_return_t {
        let svc = service(); guard svc != 0 else { return kIOReturnNotFound }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        var kr = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { return kr }
        defer { IOServiceClose(conn) }
        kr = IOConnectCallStructMethod(conn, sel.rawValue, input?.baseAddress, input?.count ?? 0, nil, nil)
        return kr
    }

    static func join(ssid: String, psk: String) -> kern_return_t {
        // struct itl_uc_join { uint32_t abi; char ssid[36]; char psk[68]; }
        var buf = [UInt8](repeating: 0, count: 4 + 36 + 68)
        withUnsafeBytes(of: abi.littleEndian) { buf.replaceSubrange(0..<4, with: $0) }
        let s = Array(ssid.utf8.prefix(32)), p = Array(psk.utf8.prefix(63))
        buf.replaceSubrange(4..<(4 + s.count), with: s)
        buf.replaceSubrange(40..<(40 + p.count), with: p)
        defer { for i in buf.indices { buf[i] = 0 } }
        return buf.withUnsafeBytes { call(.join, input: $0) }
    }
}

// ---- saved networks -------------------------------------------------------------------------------------------------------
// A small JSON file in the user's Application Support folder, readable only by the user (0600 in a 0700 folder). The keychain
// was used first and prompted on every rebuilt (new ad-hoc signature) app; see the header.
enum SavedStore {
    static var dir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ItlWiFi") }
    static var file: URL { dir.appendingPathComponent("networks.json") }
    static func load() -> [String: String] {
        guard let d = try? Data(contentsOf: file), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }
    static func save(_ m: [String: String]) {
        guard let d = try? JSONEncoder().encode(m) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir.appendingPathComponent("networks.json.tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: d, attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }
}

// ---- login item (a user LaunchAgent; no signing needed) ------------------------------------------------------------------
enum LoginItem {
    static let label = "com.itlmt7925.ItlWiFi"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    static func set(_ on: Bool) {
        if !on { try? FileManager.default.removeItem(at: plist); return }
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let d: [String: Any] = ["Label": label, "ProgramArguments": [exe], "RunAtLoad": true, "ProcessType": "Interactive",
                                "LimitLoadToSessionType": "Aqua"]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (d as NSDictionary).write(to: plist, atomically: true)
    }
}

// ---- model -----------------------------------------------------------------------------------------------------------------
enum JoinTarget: Equatable { case network(String), other }

@MainActor
final class WifiModel: ObservableObject {
    @Published var st = WifiStatus()
    @Published var speed: SpeedResult?
    @Published var speedRunning = false
    @Published var speedServer = "auto"
    @Published var speedPath = SpeedPath.internet
    @Published var joinTarget: JoinTarget?      // the join form is showing (instead of the list)
    @Published var message: String?
    @Published var loginEnabled = LoginItem.enabled
    @Published var saved = SavedStore.load()    // ssid -> passphrase
    @Published var order: [String] = []         // SSIDs in the order the list shows them (see updateOrder)
    var drafts: [String: String] = [:]          // what was typed in the join form, kept while the app runs ("" key: Other Network)
    var pending: (ssid: String, psk: String, remember: Bool)?
    var userOff = false
    var autoTried = Set<String>()
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var seen: [String: WifiNet] = [:]   // last sighting of each SSID in the list
    private var missing: [String: Int] = [:]    // consecutive refreshes an SSID was absent
    private var eventsAtJoin = Set<String>()
    private var failShown = false
    private var pendingSince = Date()
    private var reorderNext = false

    var known: Set<String> { Set(saved.keys) }

    init() {
        refresh()
        updateOrder(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.autoJoin() }
    }

    var connected: Bool { st.state == "connected" }
    var busy: Bool { st.state == "connecting" || st.state == "scanning" }
    var connectingSSID: String? { pending != nil && !connected ? pending?.ssid : nil }

    func refresh() {
        let old = st
        st = Driver.status()
        let rescanned = st.scanGen != old.scanGen
        updateOrder(force: reorderNext && rescanned)
        if reorderNext && rescanned { reorderNext = false }
        if let p = pending {
            let fresh = st.events.filter { !eventsAtJoin.contains($0) }
            if connected && st.ssid == p.ssid {
                if p.remember { saved[p.ssid] = p.psk; SavedStore.save(saved) }
                pending = nil; message = nil
                if joinTarget != nil { joinTarget = nil }
            } else if !failShown, let why = fresh.last(where: { Self.isFailure($0) }) {
                failShown = true
                message = "Could not join \(p.ssid): " + Self.friendly(why)
            } else if Date().timeIntervalSince(pendingSince) > 60 && !busy {
                pending = nil
                if !failShown { message = "Could not join \(p.ssid): no answer from the access point." }
            }
        }
        if (st.state == "idle" || st.state == "failed") && !userOff && pending == nil && rescanned { autoJoin() }
        onChange?()
    }

    // ---- list order -------------------------------------------------------------------------------------------------------
    // The driver's list is re-sorted by signal after every scan, so rows moved under the pointer: the click landed on another
    // network. The order here only changes when it must: new networks are inserted by (saved, signal band), vanished ones go
    // after three refreshes without them, and a full re-sort happens when the popover opens or after the user's own Scan.
    private func tier(_ n: WifiNet) -> Int {
        let band = n.rssi == 0 ? 1 : n.rssi >= -60 ? 3 : n.rssi >= -72 ? 2 : 1
        return (known.contains(n.ssid) ? 10 : 0) + band
    }

    func updateOrder(force: Bool) {
        let present = Dictionary(st.nets.map { ($0.ssid, $0) }, uniquingKeysWith: { a, _ in a })
        for (k, v) in present { seen[k] = v; missing[k] = 0 }
        for k in order where present[k] == nil { missing[k, default: 0] += 1 }
        if force {
            order = seen.values.filter { present[$0.ssid] != nil }.sorted {
                let (a, b) = (tier($0), tier($1))
                if a != b { return a > b }
                if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
                return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
            }.map { $0.ssid }
            seen = seen.filter { present[$0.key] != nil }
            return
        }
        order.removeAll { (missing[$0] ?? 0) >= 3 }
        for n in st.nets where !order.contains(n.ssid) {
            let t = tier(n)
            if let i = order.firstIndex(where: { seen[$0].map(tier) ?? 0 < t }) { order.insert(n.ssid, at: i) } else { order.append(n.ssid) }
        }
    }

    var rows: [WifiNet] { order.compactMap { seen[$0] }.filter { !(connected && $0.ssid == st.ssid) } }

    // ---- actions ----------------------------------------------------------------------------------------------------------
    func scan() {
        reorderNext = true
        let kr = Driver.call(.scan)
        if kr != KERN_SUCCESS && kr != kIOReturnBusy { message = "Scan failed: " + explain(kr) }
    }

    func select(_ n: WifiNet) {
        message = nil
        if connected && st.ssid == n.ssid { return }
        if let psk = saved[n.ssid] { join(n.ssid, psk, remember: false); return }
        joinTarget = .network(n.ssid)
    }

    func join(_ ssid: String, _ psk: String, remember: Bool) {
        guard (1...32).contains(ssid.utf8.count) else { message = "The network name must be 1-32 bytes."; return }
        guard (8...63).contains(psk.utf8.count) else { message = "The password must be 8-63 characters."; return }
        eventsAtJoin = Set(st.events)
        let kr = Driver.join(ssid: ssid, psk: psk)
        if kr != KERN_SUCCESS { message = "Could not join \(ssid): " + explain(kr); return }
        userOff = false; message = nil; failShown = false; pendingSince = Date()
        pending = (ssid, psk, remember)
        refresh()
    }

    func disconnect() {
        let kr = Driver.call(.disconnect)
        if kr != KERN_SUCCESS { message = "Disconnect failed: " + explain(kr); return }
        userOff = true; pending = nil
        refresh()
    }

    func forget(_ ssid: String) {
        saved[ssid] = nil; SavedStore.save(saved); drafts[ssid] = nil
        autoTried.insert(ssid)
        if st.ssid == ssid && (connected || busy) { disconnect() }
    }

    func setLogin(_ on: Bool) { LoginItem.set(on); loginEnabled = LoginItem.enabled }

    func runSpeedTest() {
        guard !speedRunning, connected else { return }
        speedRunning = true; message = nil
        let server = speedServer, path = speedPath
        Task.detached(priority: .userInitiated) {
            let r = SpeedTest.run(serverID: server, path: path)
            await MainActor.run { self.speed = r; self.speedRunning = false; self.onChange?() }
        }
    }

    // At start and after scans while not connected: join the strongest saved network in range, once per network.
    func autoJoin() {
        guard st.present, !userOff, pending == nil, st.state == "idle" || st.state == "failed" else { return }
        guard let n = st.nets.first(where: { saved[$0.ssid] != nil && $0.joinable && !autoTried.contains($0.ssid) }),
              let psk = saved[n.ssid] else { return }
        autoTried.insert(n.ssid)
        join(n.ssid, psk, remember: false)
    }

    func explain(_ kr: kern_return_t) -> String {
        switch kr {
        case kIOReturnNotPrivileged: return "only the user at the console (or root) can change Wi-Fi."
        case kIOReturnNotReady: return "the driver is still starting. Try again in a moment."
        case kIOReturnNotFound: return "itlmt7925 is not loaded."
        case kIOReturnUnsupported: return "this itlmt7925 build has no runtime control."
        default: return String(format: "IOKit error 0x%08x", kr)
        }
    }

    // wifi-events lines that mean the attempt failed, and what they mean in words
    static func isFailure(_ line: String) -> Bool {
        line.contains("connect failed") || line.contains("failed rc=") || line.contains("no configured network") || line.contains("lost after")
    }
    static func friendly(_ line: String) -> String {
        if line.contains("hw-prep-fail") { return "the driver could not set up the radio. Restart the Mac so the updated driver loads." }
        if line.contains("roc-fail") { return "the access point did not answer on its channel. Move closer and try again." }
        if line.contains("auth-fail") { return "the access point rejected the connection." }
        if line.contains("assoc-fail") { return "the access point refused the association." }
        if line.contains("hs-fail") || line.contains("handshake") { return "the password was not accepted (or the key exchange failed)." }
        if line.contains("no configured network") || line.contains("nocred") { return "the network is not in range." }
        if line.contains("lost after") { return "the connection dropped." }
        return line.drop(while: { $0.isNumber || $0 == "s" }).trimmingCharacters(in: .whitespaces)
    }
}

func bars(_ rssi: Int) -> Double { rssi == 0 ? 0.66 : rssi >= -60 ? 1 : rssi >= -70 ? 0.66 : rssi >= -80 ? 0.33 : 0.1 }

// ---- views -------------------------------------------------------------------------------------------------------------------
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }
}

struct HoverRow<Content: View>: View {
    let action: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hover = false
    var body: some View {
        content
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover && action != nil ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
            .padding(.horizontal, 6)
    }
}

struct SignalIcon: View {
    let rssi: Int
    var active = false
    var body: some View {
        ZStack {
            Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.1)).frame(width: 26, height: 26)
            Image(systemName: "wifi", variableValue: bars(rssi))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(active ? .white : .primary)
        }
    }
}

// The join form replaces the list while it is open: nothing in it moves when a scan finishes, and what was typed is kept
// (WifiModel.drafts) when the user goes back or the popover closes.
struct JoinView: View {
    @ObservedObject var m: WifiModel
    let target: JoinTarget
    @State private var name = ""
    @State private var psk = ""
    @State private var remember = true
    @State private var reveal = false
    @FocusState private var focus: Field?
    enum Field { case name, psk }

    var ssid: String { if case .network(let s) = target { return s } else { return name } }
    var key: String { if case .network(let s) = target { return s } else { return "" } }
    var attempting: Bool { m.pending != nil && m.pending?.ssid == ssid && !m.connected && m.message == nil }
    var valid: Bool { (1...32).contains(ssid.utf8.count) && (8...63).contains(psk.utf8.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { m.joinTarget = nil } label: { Label("Wi-Fi", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).font(.system(size: 12))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(target == .other ? "Join a Hidden Network" : "Join “\(ssid)”").font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text("Enter the Wi-Fi password.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if target == .other {
                TextField("Network name", text: $name).textFieldStyle(.roundedBorder).focused($focus, equals: .name)
            }
            HStack(spacing: 6) {
                Group {
                    if reveal { TextField("Password", text: $psk) } else { SecureField("Password", text: $psk) }
                }
                .textFieldStyle(.roundedBorder).focused($focus, equals: .psk).onSubmit(go)
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless).help(reveal ? "Hide password" : "Show password")
            }
            Toggle("Remember this network", isOn: $remember).toggleStyle(.checkbox).font(.system(size: 12))

            if let msg = m.message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(msg).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
            }
            HStack {
                if attempting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { m.message = nil; m.joinTarget = nil }.controlSize(.regular)
                Button(attempting ? "Connecting…" : "Join", action: go).controlSize(.regular)
                    .keyboardShortcut(.defaultAction).disabled(!valid || attempting)
            }
        }
        .padding(14)
        .frame(width: 330)
        .onAppear {
            psk = m.drafts[key] ?? ""
            if case .other = target { name = m.drafts["\u{0}name"] ?? "" }
            focus = (target == .other && name.isEmpty) ? .name : .psk
        }
        .onChange(of: psk) { m.drafts[key] = $0 }
        .onChange(of: name) { m.drafts["\u{0}name"] = $0 }
    }
    func go() { if valid && !attempting { m.join(ssid, psk, remember: remember) } }
}

struct SpeedCard: View {
    @ObservedObject var m: WifiModel
    func cell(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text(SpeedTest.fmt(value)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("\(title) · \(unit)").font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Path", selection: $m.speedPath) {
                ForEach(SpeedPath.allCases, id: \.self) { Text($0.label).tag($0) }
            }.disabled(m.speedRunning)
            Picker("Server", selection: $m.speedServer) {
                Text("Auto · fallback servers").tag("auto")
                ForEach(SpeedTest.servers) { Text($0.name).tag($0.id) }
            }.disabled(m.speedRunning)
            if let r = m.speed {
                if r.downMbps != nil || r.upMbps != nil {
                    HStack { cell("Down", r.downMbps, "Mb/s"); cell("Up", r.upMbps, "Mb/s"); cell("TCP", r.pingMs, "ms") }
                }
                if let e = r.error {
                    Text(e).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !r.server.isEmpty {
                    Text(r.server + (r.remoteIP.isEmpty ? "" : " · " + r.remoteIP))
                        .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let note = r.note { Text(note).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            HStack {
                if m.speedRunning {
                    ProgressView().controlSize(.small)
                    Text("Testing…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if let r = m.speed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((r.downMbps == nil && r.upMbps == nil ? "Attempted " : "Measured ") + r.at.formatted(date: .omitted, time: .shortened))
                        Text(r.path)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(m.speed == nil ? "Run Speed Test" : "Run Again") { m.runSpeedTest() }
                    .controlSize(.small).disabled(m.speedRunning || !m.connected)
            }
        }
        .font(.system(size: 11))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 14)
    }
}

struct NetworkRow: View {
    @ObservedObject var m: WifiModel
    let n: WifiNet
    var saved: Bool { m.known.contains(n.ssid) }
    var connecting: Bool { m.connectingSSID == n.ssid }

    var body: some View {
        HoverRow(action: n.joinable ? { m.select(n) } : nil) {
            HStack(spacing: 10) {
                SignalIcon(rssi: n.rssi)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.ssid).font(.system(size: 13)).lineLimit(1).foregroundStyle(n.joinable ? .primary : .secondary)
                    Text(sub).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if connecting { ProgressView().controlSize(.small) }
                else if n.locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .contextMenu {
            Text("\(n.channel > 14 ? "5 GHz" : "2.4 GHz") · channel \(n.channel)" + (n.rssi == 0 ? "" : " · \(n.rssi) dBm") + " · " + n.security.uppercased())
            Divider()
            if n.joinable {
                Button(saved ? "Connect" : "Connect…") { m.select(n) }
                if saved { Button("Connect with a Different Password…") { m.message = nil; m.joinTarget = .network(n.ssid) } }
            }
            if saved { Button("Forget This Network") { m.forget(n.ssid) } }
            Divider()
            Button("Copy Network Name") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.ssid, forType: .string)
            }
        }
    }
    var sub: String {
        var s = n.channel > 14 ? "5 GHz" : "2.4 GHz"
        if n.rssi != 0 { s += " · \(n.rssi) dBm" }
        s += n.locked ? " · " + n.security.uppercased() : " · Open"
        if saved { s += " · Saved" }
        if !n.joinable { s += " · not supported yet" }
        return s
    }
}

struct ContentView: View {
    @ObservedObject var m: WifiModel
    let showSpeedTest: () -> Void
    var statusLine: String {
        switch m.st.state {
        case "connected": return m.st.ssid
        case "connecting": return m.st.ssid.isEmpty ? "Connecting…" : "Connecting to \(m.st.ssid)…"
        case "scanning": return "Scanning…"
        case "failed": return "Not connected"
        case "off": return "Off (boot-arg itlmt_m3=1 missing)"
        case "absent": return "Driver not loaded"
        default: return "Not connected"
        }
    }
    var body: some View {
        if let t = m.joinTarget { JoinView(m: m, target: t) } else { list }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wi-Fi").font(.system(size: 13, weight: .semibold))
                    Text("MediaTek MT7925 · itlmt7925").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                Button { m.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Scan now").disabled(!m.st.present)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            if m.st.present && m.st.state != "absent" {
                HoverRow(action: nil) {
                    HStack(spacing: 10) {
                        SignalIcon(rssi: m.st.rssi, active: m.connected)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(statusLine).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            if m.connected {
                                Text("Channel \(m.st.channel)" + (m.st.rssi == 0 ? "" : " · \(m.st.rssi) dBm") + " · \(m.st.rate) Mb/s")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            } else if !m.st.error.isEmpty {
                                Text(m.st.error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        if m.connected || m.busy {
                            Menu { currentActions } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }
                    }
                }
                .contextMenu { if m.connected || m.busy { currentActions } }
            } else {
                Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 6)
            }

            if let msg = m.message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(msg).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { m.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                .padding(.horizontal, 14).padding(.vertical, 4)
            }

            SectionTitle(text: "Networks")
            ScrollView {
                VStack(spacing: 0) {
                    if m.rows.isEmpty {
                        Text("No networks found yet").font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(m.rows.prefix(30), id: \.ssid) { n in NetworkRow(m: m, n: n) }
                    HoverRow(action: { m.message = nil; m.joinTarget = .other }) {
                        HStack(spacing: 10) {
                            ZStack { Circle().fill(Color.primary.opacity(0.1)).frame(width: 26, height: 26)
                                     Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)) }
                            Text("Other Network…").font(.system(size: 13))
                            Spacer()
                        }
                    }
                }
            }
            .frame(height: 300)          // fixed: a list that grows or shrinks would move rows under the pointer

            Divider().padding(.top, 6)
            HStack {
                Toggle("Open at Login", isOn: Binding(get: { m.loginEnabled }, set: { m.setLogin($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.system(size: 12))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 330)
    }

    @ViewBuilder var currentActions: some View {
        Button("Disconnect") { m.disconnect() }
        if m.known.contains(m.st.ssid) { Button("Forget This Network") { m.forget(m.st.ssid) } }
        if !m.st.ssid.isEmpty {
            Divider()
            Button("Copy Network Name") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.st.ssid, forType: .string)
            }
        }
        Divider()
        Button("Speed Test…", action: showSpeedTest).disabled(!m.connected && m.speed == nil)
    }
}

// Auxiliary tool: only shown in its own window from the existing network actions menu.
struct SpeedTestView: View {
    @ObservedObject var m: WifiModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(m.connected ? m.st.ssid : "Wi-Fi is not connected")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                SpeedCard(m: m)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 220)
    }
}

// ---- status item -------------------------------------------------------------------------------------------------------------
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    let model = WifiModel()
    private var speedWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: ContentView(m: model, showSpeedTest: { [weak self] in self?.showSpeedTest() }))
        item.button?.target = self
        item.button?.action = #selector(toggle)
        model.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    @objc func toggle() {
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refresh()
        model.updateOrder(force: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showSpeedTest() {
        popover.performClose(nil)
        if speedWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Speed Test"
            window.contentMinSize = NSSize(width: 400, height: 220)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SpeedTestView(m: model))
            window.center()
            speedWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        speedWindow?.makeKeyAndOrderFront(nil)
    }

    func updateIcon() {
        guard let b = item.button else { return }
        let s = model.st
        var name = "wifi.slash", value = 1.0, alpha: CGFloat = 1
        switch s.state {
        case "connected": name = "wifi"; value = bars(s.rssi)
        case "connecting", "scanning": name = "wifi"; alpha = 0.45
        case "failed": name = "wifi.exclamationmark"
        default: break
        }
        let img = NSImage(systemSymbolName: name, variableValue: value, accessibilityDescription: "Wi-Fi")
        img?.isTemplate = true
        b.image = img
        b.alphaValue = alpha
        let tip = s.state == "connected" ? "\(s.ssid) · channel \(s.channel)" + (s.rssi == 0 ? "" : " · \(s.rssi) dBm") : s.state
        b.toolTip = tip
    }
}

@main
struct ItlWiFiMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
