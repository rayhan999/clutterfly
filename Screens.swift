import SwiftUI
import AppKit

// Native screens for the mo tools that are TUIs in the terminal.
// Each reads mo's machine-readable output: status --json, analyze --json, uninstall --list.

func bytes(_ n: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }

struct Card<Content: View>: View {
    let title: String, icon: String, color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.35)))
    }
}

struct Ring: View {
    let value: Double, colors: [Color], label: String
    var size: CGFloat = 90
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: size / 9)
            Circle().trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: value)
            Text(label).font(.system(size: size * 0.22, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
    }
}

func pill(_ s: String, _ c: Color) -> some View {
    Text(s).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
        .background(c.opacity(0.2), in: Capsule()).foregroundStyle(c)
}

func Loading(_ text: String, _ colors: [Color]) -> some View {
    VStack(spacing: 14) { Orb(colors: colors, busy: true); Text(text).foregroundStyle(.secondary) }
        .frame(maxWidth: .infinity).padding(.top, 40)
}

// MARK: - Live Status

struct Snapshot: Decodable {
    let health_score: Double, health_score_msg: String, uptime: String
    let hardware: HW, cpu: CPU, memory: Mem, disks: [Disk]
    let batteries: [Battery]?, network: [Net]?, top_processes: [Proc]?
    struct HW: Decodable { let model, cpu_model, total_ram, os_version: String }
    struct CPU: Decodable { let usage: Double, per_core: [Double] }
    struct Mem: Decodable { let used, total, used_percent, swap_used: Double; let pressure: String }
    struct Disk: Decodable { let used, total: Double }
    struct Battery: Decodable { let percent: Double, status: String, health: String, cycle_count: Int }
    struct Net: Decodable { let rx_rate_mbs, tx_rate_mbs: Double, ip: String }
    struct Proc: Decodable { let name: String, cpu: Double, memory: Double }
}

@MainActor final class StatusModel: ObservableObject {
    @Published var snap: Snapshot?
    @Published var failed = false
    func poll() async {
        while !Task.isCancelled {
            let s = try? JSONDecoder().decode(Snapshot.self, from: await Runner.capture(["status", "--json"]))
            if let s { snap = s }
            failed = snap == nil
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

struct StatusView: View {
    @StateObject var m = StatusModel()
    var body: some View {
        ScrollView {
            if let s = m.snap { content(s) }
            else if m.failed { Text("Couldn't read status from mo.").padding(.top, 80) }
            else { Loading("Checking your Mac…", [.green, .mint]) }
        }
        .task { await m.poll() }   // stops automatically when you leave this screen
    }

    func healthColors(_ v: Double) -> [Color] { v >= 80 ? [.green, .mint] : v >= 60 ? [.yellow, .orange] : [.red, .pink] }

    func content(_ s: Snapshot) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 24) {
                Ring(value: s.health_score / 100, colors: healthColors(s.health_score), label: "\(Int(s.health_score))", size: 130)
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEALTH SCORE").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(s.health_score_msg).font(.title2.bold())
                    Text("\(s.hardware.model) · \(s.hardware.cpu_model) · \(s.hardware.total_ram) RAM").foregroundStyle(.secondary)
                    Text("\(s.hardware.os_version) · up \(s.uptime)").foregroundStyle(.secondary)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                Card(title: "CPU", icon: "cpu", color: .cyan) {
                    HStack(spacing: 18) {
                        Ring(value: s.cpu.usage / 100, colors: [.cyan, .blue], label: "\(Int(s.cpu.usage))%")
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(s.cpu.per_core.enumerated()), id: \.offset) { _, v in
                                Capsule().fill(LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top))
                                    .frame(width: 7, height: max(4, 70 * v / 100))
                            }
                        }
                        .frame(height: 70, alignment: .bottom)
                    }
                }
                Card(title: "Memory", icon: "memorychip", color: .purple) {
                    HStack(spacing: 18) {
                        Ring(value: s.memory.used_percent / 100, colors: [.purple, .pink], label: "\(Int(s.memory.used_percent))%")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(bytes(s.memory.used)) of \(bytes(s.memory.total))")
                            Text("Swap \(bytes(s.memory.swap_used))").foregroundStyle(.secondary)
                            if s.memory.pressure != "normal" { pill("Pressure: \(s.memory.pressure)", .yellow) }
                        }
                    }
                }
                if let d = s.disks.first {
                    Card(title: "Disk", icon: "internaldrive", color: .orange) {
                        HStack(spacing: 18) {
                            Ring(value: d.used / d.total, colors: [.orange, .pink], label: "\(Int(100 * d.used / d.total))%")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(bytes(d.total - d.used)) free").font(.title3.bold())
                                Text("of \(bytes(d.total))").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let b = s.batteries?.first {
                    Card(title: "Battery", icon: "battery.75percent", color: .green) {
                        HStack(spacing: 18) {
                            Ring(value: b.percent / 100, colors: [.green, .mint], label: "\(Int(b.percent))%")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.status.capitalized)
                                Text("Health \(b.health) · \(b.cycle_count) cycles").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let n = s.network {
                    Card(title: "Network", icon: "network", color: .teal) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("↓ \(String(format: "%.2f", n.map(\.rx_rate_mbs).reduce(0, +))) MB/s   ↑ \(String(format: "%.2f", n.map(\.tx_rate_mbs).reduce(0, +))) MB/s")
                                .font(.title3.bold()).monospacedDigit()
                            if let ip = n.first(where: { !$0.ip.isEmpty })?.ip { Text("IP \(ip)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let procs = s.top_processes, !procs.isEmpty {
                Card(title: "Busiest right now", icon: "flame.fill", color: .pink) {
                    ForEach(Array(procs.enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(p.name).lineLimit(1).frame(width: 200, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, g.size.width * min(p.cpu, 100) / 100))
                            }
                            .frame(height: 8)
                            Text("\(String(format: "%.0f", p.cpu))% CPU").monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(28)
    }
}

// MARK: - Disk Explorer

struct Entry: Decodable, Identifiable {
    var id: String { path }
    let name: String, path: String, size: Double
    let is_dir: Bool?, insight: Bool?
}
struct Analysis: Decodable { let total_size: Double?; let entries: [Entry]? }

@MainActor final class ExplorerModel: ObservableObject {
    @Published var stack: [String] = []      // empty = machine overview
    @Published var result: Analysis?
    @Published var loading = false
    @Published var error = ""
    @Published var trashTarget: Entry?
    @Published var confirmTrash = false

    func load() async {
        let at = stack
        loading = true; error = ""
        let data = await Runner.capture(["analyze", "--json"] + at.suffix(1))
        guard at == stack else { return }    // user navigated away meanwhile
        result = try? JSONDecoder().decode(Analysis.self, from: data)
        if result == nil { error = "Couldn't scan this folder." }
        loading = false
    }
    func open(_ e: Entry) { stack.append(e.path); Task { await load() } }
    func back() { stack.removeLast(); Task { await load() } }
    func trash(_ e: Entry) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: e.path)]) { _, err in
            Task { @MainActor in
                if let err { self.error = err.localizedDescription }
                await self.load()
            }
        }
    }

    /// Only things inside your home folder, and never top-level folders like ~/Documents or ~/Library/Containers.
    static func canTrash(_ e: Entry) -> Bool {
        let home = NSHomeDirectory() + "/"
        guard e.path.hasPrefix(home) else { return false }
        let parts = e.path.dropFirst(home.count).split(separator: "/")
        return parts.count >= (parts.first == "Library" ? 3 : 2)
    }
}

struct ExplorerView: View {
    @StateObject var m = ExplorerModel()
    let colors: [Color] = [.blue, .cyan]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if !m.stack.isEmpty {
                    Button { m.back() } label: { Image(systemName: "chevron.left").font(.title2) }
                        .buttonStyle(.plain).disabled(m.loading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.stack.last.map { ($0 as NSString).lastPathComponent } ?? "Your Mac").font(.largeTitle.bold())
                    Text(m.stack.last.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Biggest places, plus quick wins")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let t = m.result?.total_size, !m.loading {
                    Text(bytes(t)).font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                }
                Button { Task { await m.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(m.loading)
            }
            if m.loading { Loading("Measuring folders… big ones can take half a minute.", colors) }
            else if !m.error.isEmpty { Text(m.error).foregroundStyle(.red) }
            if !m.loading, let entries = m.result?.entries { list(entries.sorted { $0.size > $1.size }) }
            Spacer(minLength: 0)
        }
        .padding(24)
        .task {
            if let start = Runner.shared.explorerStart {   // opened from External Drives
                Runner.shared.explorerStart = nil
                m.stack = [start]
                await m.load()
            } else if m.result == nil { await m.load() }
        }
        .confirmationDialog("Move to Trash?", isPresented: $m.confirmTrash, presenting: m.trashTarget) { e in
            Button("Move \(e.name) to Trash", role: .destructive) { m.trash(e) }
        } message: { e in Text("\(bytes(e.size)) · \((e.path as NSString).abbreviatingWithTildeInPath)\nYou can restore it from the Trash.") }
    }

    func list(_ entries: [Entry]) -> some View {
        let biggest = max(entries.first?.size ?? 1, 1)
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(entries) { e in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: e.path)).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(e.name).font(.headline).lineLimit(1)
                                if e.insight == true { pill("Quick win", .yellow) }
                            }
                            GeometryReader { g in
                                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, g.size.width * e.size / biggest))
                            }
                            .frame(height: 6)
                        }
                        Text(bytes(e.size)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        Menu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)]) }
                            if ExplorerModel.canTrash(e) {
                                Button("Move to Trash…", role: .destructive) { m.trashTarget = e; m.confirmTrash = true }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).opacity(e.is_dir == true ? 1 : 0)
                    }
                    .padding(10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture { if e.is_dir == true { m.open(e) } }
                }
            }
        }
    }
}

// MARK: - Uninstall Apps

struct AppInfo: Decodable, Identifiable {
    var id: String { path }
    let name: String, source: String, uninstall_name: String, path: String, size: String
}

@MainActor final class UninstallModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var search = ""
    @Published var selected: String?
    @Published var preview = ""
    @Published var previewing = false

    var filtered: [AppInfo] { search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) } }
    var app: AppInfo? { apps.first { $0.path == selected } }

    func load() async {
        loading = true
        let list = (try? JSONDecoder().decode([AppInfo].self, from: await Runner.capture(["uninstall", "--list"]))) ?? []
        apps = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if app == nil { selected = nil; preview = "" }
        loading = false
    }

    func runPreview() async {
        guard let a = app else { return }
        previewing = true; preview = ""
        let out = await Runner.capture(["uninstall", "--dry-run", a.uninstall_name], withErrors: true)
        if a.path == selected {
            preview = Runner.strip(String(decoding: out, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        previewing = false
    }

    /// Mole refuses to confirm an uninstall without a real terminal (a safety guard), so the last step opens Terminal.
    func uninstallInTerminal() {
        guard let a = app else { return }
        let quoted = a.uninstall_name.replacingOccurrences(of: "'", with: "'\\''")
        Runner.openInTerminal(name: "uninstall", script: "mo uninstall '\(quoted)'")
    }
}

struct UninstallView: View {
    @StateObject var m = UninstallModel()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search apps", text: $m.search).textFieldStyle(.roundedBorder)
                    Button { Task { await m.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(m.loading)
                }
                .padding(10)
                if m.loading && m.apps.isEmpty { ProgressView().padding() }
                List(m.filtered, selection: $m.selected) { a in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).lineLimit(1)
                            Text(a.size == "--" ? a.source : "\(a.size) · \(a.source)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(a.path)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(width: 290)
            .background(.black.opacity(0.25))

            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { if m.apps.isEmpty { await m.load() } }
        .onChange(of: m.selected) { m.preview = "" }
        // Refresh after coming back from the Terminal uninstall.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await m.load() }
        }
    }

    @ViewBuilder var detail: some View {
        if let a = m.app {
            ScrollView {
                VStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 110, height: 110)
                        .shadow(color: .pink.opacity(0.5), radius: 20)
                    Text(a.name).font(.largeTitle.bold())
                    Text((a.path as NSString).abbreviatingWithTildeInPath + (a.size == "--" ? "" : " · \(a.size)"))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        BigButton(title: m.previewing ? "Looking…" : "Preview", icon: "magnifyingglass", colors: [.purple, .blue]) {
                            Task { await m.runPreview() }
                        }
                        .disabled(m.previewing)
                        BigButton(title: "Uninstall…", icon: "trash.fill", colors: [.red, .pink]) { m.uninstallInTerminal() }
                    }
                    Text("Preview shows what will be removed. Uninstall opens Terminal, where you press Enter to confirm; Mole insists on that for safety. Files go to the Trash.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    if !m.preview.isEmpty {
                        Text(m.preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(28)
            }
        } else {
            VStack(spacing: 10) {
                Orb(colors: [.red, .pink], busy: m.loading, icon: "trash.fill")
                Text(m.loading ? "Finding your apps…" : "Pick an app on the left").font(.title2.bold())
                Text("\(m.apps.count) apps installed").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Caffeinate (macOS built-in, not mo)

/// Shared so it keeps running while you switch screens.
@MainActor final class Caffeine: ObservableObject {
    static let shared = Caffeine()
    @Published var active = false
    @Published var keepDisplayOn = true
    @Published var minutes = 0          // 0 = until stopped
    @Published var endsAt: Date?
    private var proc: Process?

    func start() {
        stop()
        // -i: no idle sleep, -d: screen stays on, -w: ends automatically when Clutterfly quits.
        var args = ["-i", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        if keepDisplayOn { args.append("-d") }
        if minutes > 0 { args += ["-t", "\(minutes * 60)"] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = args
        p.terminationHandler = { ended in
            Task { @MainActor in
                let c = Caffeine.shared
                if c.proc === ended { c.proc = nil; c.active = false; c.endsAt = nil }
            }
        }
        guard (try? p.run()) != nil else { return }
        proc = p; active = true
        endsAt = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil
    }

    func stop() { proc?.terminate(); proc = nil; active = false; endsAt = nil }
}

struct CaffeinateView: View {
    @ObservedObject var c = Caffeine.shared
    let colors: [Color] = [.orange, .brown]

    var body: some View {
        VStack(spacing: 20) {
            Orb(colors: colors, busy: c.active, icon: "cup.and.saucer.fill")
            Text(c.active ? "Staying awake ☕️" : "Caffeinate").font(.largeTitle.bold())
            if let end = c.endsAt {
                (Text("Your Mac can sleep again in ") + Text(end, style: .timer)).font(.title3).monospacedDigit()
            } else if c.active {
                Text("Until you stop it or quit Clutterfly.").foregroundStyle(.secondary)
            } else {
                Text("Stop your Mac from falling asleep during downloads, builds or presentations.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if c.active {
                BigButton(title: "Let It Sleep", icon: "moon.zzz.fill", colors: [.indigo, .purple]) { c.stop() }
            } else {
                Picker("Keep awake", selection: $c.minutes) {
                    Text("Until I stop").tag(0); Text("30 min").tag(30); Text("1 hour").tag(60)
                    Text("2 hours").tag(120); Text("4 hours").tag(240)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)
                Toggle("Keep the screen on too", isOn: $c.keepDisplayOn)
                BigButton(title: "Keep Awake", icon: "bolt.fill", colors: colors) { c.start() }
            }
            Text("Uses macOS's built-in caffeinate command.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
