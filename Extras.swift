import SwiftUI
import AppKit
import Charts
import UserNotifications

// Extra screens: Docker, Dev Caches, Snapshots, History & Alerts, Protected Items,
// External Drives, Touch ID, Update Mole, plus the menu bar mini-app.

// MARK: - Helpers

/// Runs a command line in a login zsh so the user's own PATH (bun, cargo, go, docker…) applies.
func sh(_ cmd: String) async -> (out: String, status: Int32) {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            p.environment = Runner.env
            p.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            guard (try? p.run()) != nil else { return cont.resume(returning: ("", -1)) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: (Runner.strip(String(decoding: data, as: UTF8.self)), p.terminationStatus))
        }
    }
}

/// Single-quotes a value for the shell.
func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// "2.734GB", "938kB", "1.40GB+", "4.3 MB" → bytes (decimal units, like Docker and mo).
func parseSize(_ s: String) -> Double {
    guard let r = s.range(of: #"[0-9.]+\s*[kKMGT]?i?B"#, options: .regularExpression) else { return 0 }
    let t = s[r].replacingOccurrences(of: " ", with: "")
    let num = Double(t.prefix { "0123456789.".contains($0) }) ?? 0
    let unit = String(t.drop { "0123456789.".contains($0) }).uppercased()
    let mult: [String: Double] = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
                                  "KIB": 1024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776]
    return num * (mult[unit] ?? 1)
}

struct ScreenHeader: View {
    let title: String, subtitle: String, icon: String, colors: [Color]
    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, colors: colors, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct BigNumber: View {
    let value: String, caption: String, colors: [Color]
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            Text(caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

func outputBox(_ text: String) -> some View {
    Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
}

// MARK: - Docker

@MainActor final class DockerModel: ObservableObject {
    @Published var rows: [[String: String]] = []
    @Published var state = "loading"     // loading | missing | stopped | ok
    @Published var busy = false
    @Published var output = ""
    @Published var allImages = false
    @Published var volumes = false
    @Published var confirm = false

    var reclaimable: Double { rows.map { parseSize($0["Reclaimable"] ?? "") }.reduce(0, +) }

    func load() async {
        let r = await sh("command -v docker >/dev/null || exit 127; docker system df --format '{{json .}}'")
        if r.status == 127 { state = "missing"; return }
        rows = r.out.split(separator: "\n").compactMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) }
        state = rows.isEmpty ? "stopped" : "ok"
    }

    func prune() async {
        busy = true
        let r = await sh("docker system prune -f" + (allImages ? " -a" : "") + (volumes ? " --volumes" : ""))
        output = r.out.split(separator: "\n").last { $0.contains("reclaimed") }.map(String.init) ?? r.out
        busy = false
        await load()
    }
}

struct DockerView: View {
    @StateObject var m = DockerModel()
    let colors: [Color] = [.blue, .cyan]
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "Docker", subtitle: "Unused images, containers, volumes and build cache.", icon: "shippingbox.circle.fill", colors: colors)
                switch m.state {
                case "loading": Loading("Asking Docker…", colors)
                case "missing": Text("Docker isn't installed on this Mac.").foregroundStyle(.secondary).padding(.top, 40)
                case "stopped":
                    VStack(spacing: 14) {
                        Text("Docker isn't running.").font(.title2.bold())
                        HStack {
                            BigButton(title: "Start Docker", icon: "play.fill", colors: colors) { Task { _ = await sh("open -a Docker") } }
                            BigButton(title: "Check Again", icon: "arrow.clockwise", colors: [.indigo, .purple]) { Task { await m.load() } }
                        }
                    }
                    .padding(.top, 30)
                default: content
                }
            }
            .padding(28)
        }
        .task { await m.load() }
        .confirmationDialog("Free up Docker space?", isPresented: $m.confirm) {
            Button("Free Up Space", role: .destructive) { Task { await m.prune() } }
        } message: {
            Text(m.volumes ? "Unused volumes will be deleted, including the data inside them." : "Running containers and the images they use are kept.")
        }
    }

    var content: some View {
        VStack(spacing: 18) {
            if m.busy { Loading("Cleaning Docker…", colors) }
            else { BigNumber(value: bytes(m.reclaimable), caption: "can be freed", colors: colors) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(m.rows, id: \.self) { row in
                    Card(title: row["Type"] ?? "", icon: "cube.box.fill", color: .cyan) {
                        Text(row["Size"] ?? "").font(.title2.bold())
                        Text("\(row["Reclaimable"] ?? "") unused").foregroundStyle(.secondary)
                        Text("\(row["TotalCount"] ?? "") total · \(row["Active"] ?? "") in use").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Always removes stopped containers, unused networks, dangling images and build cache.").foregroundStyle(.secondary)
                Toggle("Also remove images no container uses", isOn: $m.allImages)
                Toggle("Also remove unused volumes (deletes the data inside them)", isOn: $m.volumes)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BigButton(title: "Free Up Space", icon: "sparkles", colors: [.red, .pink]) { m.confirm = true }.disabled(m.busy)
            if !m.output.isEmpty { Text(m.output).font(.headline).foregroundStyle(.green) }
        }
    }
}

// MARK: - Developer caches

struct DevCache: Identifiable {
    let id: String, name: String, path: String
    let command: String?      // the tool's own clean command; falls back to Trash if the tool is missing
    var fullPath: String { (path as NSString).expandingTildeInPath }
}

let devCaches: [DevCache] = [
    DevCache(id: "npm", name: "npm", path: "~/.npm/_cacache", command: "npm cache clean --force"),
    DevCache(id: "pnpm", name: "pnpm store", path: "~/Library/pnpm/store", command: "pnpm store prune"),
    DevCache(id: "bun", name: "Bun", path: "~/.bun/install/cache", command: "bun pm cache rm"),
    DevCache(id: "yarn", name: "Yarn", path: "~/Library/Caches/Yarn", command: "yarn cache clean"),
    DevCache(id: "brew", name: "Homebrew downloads & old versions", path: "~/Library/Caches/Homebrew", command: "brew cleanup --prune=all"),
    DevCache(id: "pip", name: "pip", path: "~/Library/Caches/pip", command: "pip3 cache purge"),
    DevCache(id: "xcode", name: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData", command: nil),
    DevCache(id: "sim", name: "iOS simulators (removes unavailable ones only)", path: "~/Library/Developer/CoreSimulator/Devices", command: "xcrun simctl delete unavailable"),
    DevCache(id: "gradle", name: "Gradle caches", path: "~/.gradle/caches", command: nil),
    DevCache(id: "cargo", name: "Cargo registry", path: "~/.cargo/registry/cache", command: nil),
    DevCache(id: "go", name: "Go modules", path: "~/go/pkg/mod", command: "go clean -modcache"),
    DevCache(id: "pods", name: "CocoaPods", path: "~/Library/Caches/CocoaPods", command: "pod cache clean --all"),
]

@MainActor final class DevCacheModel: ObservableObject {
    @Published var sizes: [String: Double] = [:]
    @Published var loading = false
    @Published var cleaning: String?
    @Published var target: DevCache?
    @Published var confirm = false

    var present: [DevCache] { devCaches.filter { FileManager.default.fileExists(atPath: $0.fullPath) } }
    var total: Double { sizes.values.reduce(0, +) }

    func load() async {
        loading = true
        let items = present
        let results = await withTaskGroup(of: (String, Double).self) { group in
            for c in items { group.addTask { (c.id, await Self.size(c.fullPath)) } }
            return await group.reduce(into: [String: Double]()) { $0[$1.0] = $1.1 }
        }
        sizes = results
        loading = false
    }

    nonisolated static func size(_ path: String) async -> Double {
        Double(await sh("du -sk \(q(path)) 2>/dev/null").out.split(separator: "\t").first ?? "0").map { $0 * 1024 } ?? 0
    }

    func clean(_ c: DevCache) async {
        cleaning = c.id
        var done = false
        if let cmd = c.command { done = await sh(cmd).status == 0 }
        if !done && c.id != "sim" {   // never trash the simulator devices folder itself
            // No clean command, or the tool isn't installed: move the cache folder to the Trash instead.
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: c.fullPath), resultingItemURL: nil)
        }
        sizes[c.id] = await Self.size(c.fullPath)
        cleaning = nil
    }
}

struct DevCachesView: View {
    @StateObject var m = DevCacheModel()
    let colors: [Color] = [.green, .teal]
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "Dev Caches", subtitle: "Package-manager and build caches. Tools download again what they need.", icon: "chevron.left.forwardslash.chevron.right", colors: colors)
                if m.loading && m.sizes.isEmpty { Loading("Measuring caches…", colors) }
                else {
                    BigNumber(value: bytes(m.total), caption: "in developer caches", colors: colors)
                    let biggest = max(m.sizes.values.max() ?? 1, 1)
                    ForEach(m.present.sorted { (m.sizes[$0.id] ?? 0) > (m.sizes[$1.id] ?? 0) }) { c in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: c.fullPath)).resizable().frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(c.name).font(.headline)
                                Text(c.path).font(.caption).foregroundStyle(.secondary)
                                GeometryReader { g in
                                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(4, g.size.width * (m.sizes[c.id] ?? 0) / biggest))
                                }
                                .frame(height: 6)
                            }
                            Text(bytes(m.sizes[c.id] ?? 0)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            if m.cleaning == c.id { ProgressView().controlSize(.small).frame(width: 70) }
                            else {
                                Button("Clean") { m.target = c; m.confirm = true }
                                    .disabled(m.cleaning != nil || (m.sizes[c.id] ?? 0) < 1)
                                    .frame(width: 70)
                            }
                        }
                        .padding(10)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
        .confirmationDialog("Clean this cache?", isPresented: $m.confirm, presenting: m.target) { c in
            Button("Clean \(c.name)", role: .destructive) { Task { await m.clean(c) } }
        } message: { c in
            Text(c.command.map { "Runs: \($0)" } ?? "Moves \(c.path) to the Trash.")
        }
    }
}

// MARK: - Time Machine snapshots

@MainActor final class SnapshotModel: ObservableObject {
    @Published var snaps: [String] = []
    @Published var loading = true
    @Published var message = ""
    @Published var needsPassword: String?

    func load() async {
        let r = await sh("tmutil listlocalsnapshots /")
        snaps = r.out.split(separator: "\n").map(String.init).filter { $0.hasPrefix("com.apple.") }
        loading = false
    }

    static func date(_ s: String) -> String? {
        s.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression).map { String(s[$0]) }
    }

    func delete(_ s: String) async {
        guard let d = Self.date(s) else { return }
        let r = await sh("tmutil deletelocalsnapshots \(d)")
        if r.status != 0 { needsPassword = d; message = "macOS wants your password to delete this one." }
        else { message = "Deleted the snapshot from \(d)." }
        await load()
    }
}

struct SnapshotsView: View {
    @StateObject var m = SnapshotModel()
    let colors: [Color] = [.indigo, .purple]
    var tm: [String] { m.snaps.filter { $0.contains("TimeMachine") } }
    var other: [String] { m.snaps.filter { !$0.contains("TimeMachine") } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Snapshots", subtitle: "Local Time Machine copies that can hold several GB.", icon: "clock.arrow.circlepath", colors: colors)
                if m.loading { Loading("Looking for snapshots…", colors) }
                else {
                    Card(title: "Time Machine", icon: "clock.fill", color: .purple) {
                        if tm.isEmpty { Text("No Time Machine snapshots on this Mac 🎉").foregroundStyle(.secondary) }
                        ForEach(tm, id: \.self) { s in
                            HStack {
                                Text(SnapshotModel.date(s) ?? s).monospacedDigit()
                                Spacer()
                                Button("Delete") { Task { await m.delete(s) } }
                            }
                        }
                    }
                    if !other.isEmpty {
                        Card(title: "macOS update snapshots", icon: "apple.logo", color: .gray) {
                            Text("Managed by macOS and removed after the update finishes. Leave these alone.").foregroundStyle(.secondary)
                            ForEach(other, id: \.self) { s in Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        }
                    }
                    if !m.message.isEmpty { Text(m.message).foregroundStyle(.yellow) }
                    if let d = m.needsPassword {
                        Button("Delete in Terminal (asks for password)") {
                            Runner.openInTerminal(name: "snapshot", script: "sudo tmutil deletelocalsnapshots \(d)")
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Disk watcher, low-disk alert, menu bar

@MainActor final class DiskWatcher: ObservableObject {
    static let shared = DiskWatcher()
    @Published var free: Double = 0
    @Published var total: Double = 0
    private var alerted = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in DiskWatcher.shared.refresh() }
        }
    }

    /// 0 = alerts off.
    var thresholdGB: Int {
        get { UserDefaults.standard.integer(forKey: "lowDiskGB") }
        set {
            UserDefaults.standard.set(newValue, forKey: "lowDiskGB")
            objectWillChange.send()
            alerted = false
            if newValue > 0 { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            refresh()
        }
    }

    func refresh() {
        let v = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        free = Double(v?.volumeAvailableCapacityForImportantUsage ?? 0)
        total = Double(v?.volumeTotalCapacity ?? 0)
        let limit = Double(thresholdGB) * 1e9
        if limit > 0, free > 0, free < limit {
            if !alerted { alerted = true; notify() }     // once per drop, not every minute
        } else { alerted = false }
    }

    private func notify() {
        let c = UNMutableNotificationContent()
        c.title = "Your Mac is running low on space"
        c.body = "Only \(bytes(free)) left. Open Clutterfly to clean up."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowdisk", content: c, trigger: nil))
    }
}

struct MenuBarLabel: View {
    @ObservedObject var disk = DiskWatcher.shared
    @ObservedObject var caffeine = Caffeine.shared
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: caffeine.active ? "cup.and.saucer.fill" : "sparkles")
            Text(String(format: "%.0f GB", disk.free / 1e9))
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var disk = DiskWatcher.shared
    @ObservedObject var caffeine = Caffeine.shared
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Text("\(bytes(disk.free)) free of \(bytes(disk.total))")
        Divider()
        Toggle("Keep Mac Awake", isOn: Binding(get: { caffeine.active }, set: { $0 ? caffeine.start() : caffeine.stop() }))
        Button("Scan for Junk…") { show("clean"); Runner.shared.run(["clean", "--dry-run"]) }
        Button("Live Status…") { show("status") }
        Button("Open Clutterfly") { show(nil) }
        Divider()
        Button("Quit Clutterfly") { NSApp.terminate(nil) }
    }

    func show(_ id: String?) {
        if let id { Runner.shared.selection = id }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - History & alerts

struct HistorySession: Decodable { let command: String, started_at: String, items: Int, size: String }
struct HistoryFile: Decodable { let sessions: [HistorySession] }

@MainActor final class HistoryModel: ObservableObject {
    @Published var sessions: [HistorySession] = []
    @Published var loading = true
    var freed: [HistorySession] { sessions.filter { parseSize($0.size) > 0 } }
    var total: Double { freed.map { parseSize($0.size) }.reduce(0, +) }
    /// Bytes freed per day, oldest first.
    var days: [(day: String, gb: Double)] {
        Dictionary(grouping: freed) { String($0.started_at.prefix(10)) }
            .map { (day: $0.key, gb: $0.value.map { parseSize($0.size) }.reduce(0, +) / 1e9) }
            .sorted { $0.day < $1.day }
    }

    func load() async {
        let data = await Runner.capture(["history", "--json", "--limit", "200"])
        sessions = (try? JSONDecoder().decode(HistoryFile.self, from: data))?.sessions ?? []
        loading = false
    }
}

struct HistoryView: View {
    @StateObject var m = HistoryModel()
    @ObservedObject var disk = DiskWatcher.shared
    let colors: [Color] = [.mint, .green]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "History & Alerts", subtitle: "What Mole has cleaned, and a warning before your disk fills up.", icon: "chart.bar.xaxis", colors: colors)
                if m.loading { Loading("Reading history…", colors) }
                else {
                    BigNumber(value: bytes(m.total), caption: "freed so far · \(m.freed.count) cleanups", colors: colors)
                    if !m.days.isEmpty {
                        Card(title: "Freed per day", icon: "chart.bar.fill", color: .mint) {
                            Chart(m.days, id: \.day) { d in
                                BarMark(x: .value("Day", d.day), y: .value("GB", d.gb))
                                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                                    .cornerRadius(4)
                            }
                            .chartYAxisLabel("GB")
                            .frame(height: 180)
                        }
                    }
                }
                Card(title: "Low-disk alert", icon: "bell.badge.fill", color: .yellow) {
                    Text("Right now: \(bytes(disk.free)) free.").foregroundStyle(.secondary)
                    Picker("Warn me when free space drops below", selection: Binding(get: { disk.thresholdGB }, set: { disk.thresholdGB = $0 })) {
                        Text("Off").tag(0); Text("10 GB").tag(10); Text("20 GB").tag(20); Text("30 GB").tag(30); Text("50 GB").tag(50)
                    }
                    Text("Checked every minute while Clutterfly runs. It also sits in your menu bar.").font(.caption).foregroundStyle(.secondary)
                }
                if !m.sessions.isEmpty {
                    Card(title: "Recent activity", icon: "list.bullet", color: .teal) {
                        ForEach(Array(m.sessions.prefix(25).enumerated()), id: \.offset) { _, s in
                            HStack {
                                Text(s.command.capitalized).frame(width: 100, alignment: .leading)
                                Text(s.started_at).foregroundStyle(.secondary).monospacedDigit()
                                Spacer()
                                Text("\(s.items) items").foregroundStyle(.secondary)
                                Text(s.size).monospacedDigit().frame(width: 80, alignment: .trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Protected items (mo's clean whitelist)

@MainActor final class ProtectModel: ObservableObject {
    static let file = NSHomeDirectory() + "/.config/mole/whitelist"
    @Published var patterns: [String] = []
    @Published var custom = false     // false = Mole's built-in defaults are in effect

    func load() {
        if let text = try? String(contentsOfFile: Self.file, encoding: .utf8) {
            custom = true
            patterns = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        } else {
            custom = false
            patterns = Self.moleDefaults()
        }
    }

    /// Once this file exists Mole stops using its built-in optional defaults, so we seed it with them.
    nonisolated static func moleDefaults() -> [String] {
        guard let mo = Runner.find("mo") else { return [] }
        let base = URL(fileURLWithPath: mo).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("libexec/lib/core/base.sh")
        guard let text = try? String(contentsOf: base, encoding: .utf8),
              let start = text.range(of: "DEFAULT_WHITELIST_PATTERNS=("),
              let end = text.range(of: "\n)", range: start.upperBound..<text.endIndex) else { return [] }
        return text[start.upperBound..<end.lowerBound].split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
                     .replacingOccurrences(of: "$FINDER_METADATA_SENTINEL", with: "FINDER_METADATA") }  // value from base.sh
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: (Self.file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let header = "# Mole Whitelist - Protected paths won't be deleted\n# Edited by Clutterfly. One pattern per line.\n"
        try? (header + patterns.joined(separator: "\n") + "\n").write(toFile: Self.file, atomically: true, encoding: .utf8)
        load()
    }

    func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.prompt = "Protect"
        guard panel.runModal() == .OK else { return }
        patterns += panel.urls.map(\.path).filter { !patterns.contains($0) }
        save()
    }

    func remove(_ p: String) { patterns.removeAll { $0 == p }; save() }
}

struct ProtectView: View {
    @StateObject var m = ProtectModel()
    let colors: [Color] = [.yellow, .green]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Protected Items", subtitle: "Folders Smart Clean will never touch, including everything inside them.", icon: "lock.shield.fill", colors: colors)
                HStack {
                    BigButton(title: "Protect a Folder…", icon: "plus", colors: colors) { m.add() }
                    BigButton(title: "Built-in Categories", icon: "checklist", colors: [.indigo, .purple]) {
                        Runner.openInTerminal(name: "whitelist", script: "mo clean --whitelist")
                    }
                }
                if !m.custom { Text("Showing Mole's built-in defaults. Your first change saves them together with yours.").font(.caption).foregroundStyle(.secondary) }
                Card(title: "\(m.patterns.count) protected", icon: "lock.fill", color: .yellow) {
                    ForEach(m.patterns, id: \.self) { p in
                        HStack {
                            Text(p == "FINDER_METADATA" ? "Finder metadata files (.DS_Store)" : (p as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { m.remove(p) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
                        }
                    }
                }
                Text("Mole always keeps its own safety protections (system files, keychains and so on), whatever is listed here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .onAppear { m.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in m.load() }
    }
}

// MARK: - External drives

struct Volume: Identifiable {
    var id: String { url.path }
    let url: URL, name: String, free: Double, total: Double, ejectable: Bool
}

@MainActor final class DrivesModel: ObservableObject {
    @Published var volumes: [Volume] = []
    @Published var output = ""
    @Published var busy: String?
    @Published var target: Volume?
    @Published var confirm = false

    func load() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeIsEjectableKey]
        volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { $0.path.hasPrefix("/Volumes/") }
            .map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return Volume(url: u, name: v?.volumeName ?? u.lastPathComponent,
                              free: Double(v?.volumeAvailableCapacity ?? 0), total: Double(v?.volumeTotalCapacity ?? 0),
                              ejectable: v?.volumeIsEjectable ?? false)
            }
    }

    func clean(_ v: Volume, dryRun: Bool) async {
        busy = v.id
        let out = await Runner.capture(["clean", "--external", v.url.path] + (dryRun ? ["--dry-run"] : []), withErrors: true)
        output = Runner.strip(String(decoding: out, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines)
        busy = nil
        load()
    }

    func eject(_ v: Volume) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: v.url) } catch { output = error.localizedDescription }
        load()
    }
}

struct DrivesView: View {
    @StateObject var m = DrivesModel()
    let colors: [Color] = [.orange, .yellow]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "External Drives", subtitle: "Explore USB and SSD drives, and clear the hidden Mac junk files on them.", icon: "externaldrive.fill", colors: colors)
                if m.volumes.isEmpty {
                    Text("No external drives connected. Plug one in and it shows up here.").foregroundStyle(.secondary).padding(.top, 30)
                }
                ForEach(m.volumes) { v in
                    Card(title: v.name, icon: "externaldrive.fill", color: .orange) {
                        HStack(spacing: 18) {
                            Ring(value: v.total > 0 ? (v.total - v.free) / v.total : 0, colors: colors,
                                 label: v.total > 0 ? "\(Int(100 * (v.total - v.free) / v.total))%" : "–", size: 70)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(bytes(v.free)) free of \(bytes(v.total))").font(.headline)
                                Text(v.url.path).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack {
                            Button("Explore") { Runner.shared.explorerStart = v.url.path; Runner.shared.selection = "analyze" }
                            Button("Preview Junk") { Task { await m.clean(v, dryRun: true) } }
                            Button("Clean Junk…") { m.target = v; m.confirm = true }
                            if v.ejectable { Button("Eject") { m.eject(v) } }
                            if m.busy == v.id { ProgressView().controlSize(.small) }
                        }
                        .disabled(m.busy != nil)
                    }
                }
                if !m.output.isEmpty { outputBox(m.output) }
            }
            .padding(28)
        }
        .onAppear { m.load() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in m.load() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in m.load() }
        .confirmationDialog("Clean Mac junk files from this drive?", isPresented: $m.confirm, presenting: m.target) { v in
            Button("Clean \(v.name)", role: .destructive) { Task { await m.clean(v, dryRun: false) } }
        } message: { _ in Text("Removes hidden macOS files like .DS_Store and ._ files. Your own files are not touched.") }
    }
}

// MARK: - Touch ID for sudo

@MainActor final class TouchIDModel: ObservableObject {
    @Published var status = ""
    @Published var enabled = false
    func load() async {
        status = Runner.strip(String(decoding: await Runner.capture(["touchid", "status"], withErrors: true), as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "◎✓○●")))
        enabled = !status.lowercased().contains("not")
    }
}

struct TouchIDView: View {
    @StateObject var m = TouchIDModel()
    let colors: [Color] = [.pink, .red]
    var body: some View {
        VStack(spacing: 20) {
            ScreenHeader(title: "Touch ID for Admin", subtitle: "Use your fingerprint instead of typing your password in Terminal.", icon: "touchid", colors: colors)
            Spacer()
            Image(systemName: "touchid").font(.system(size: 110)).foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            Text(m.status.isEmpty ? "Checking…" : m.status).font(.title2.bold())
            if m.enabled {
                BigButton(title: "Turn Off", icon: "xmark", colors: [.gray, .secondary]) {
                    Runner.openInTerminal(name: "touchid", script: "mo touchid disable")
                }
            } else {
                BigButton(title: "Turn On", icon: "touchid", colors: colors) {
                    Runner.openInTerminal(name: "touchid", script: "mo touchid enable")
                }
            }
            Text("Changing this edits the macOS sudo settings, so Terminal asks for your password one last time.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
        .task { await m.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await m.load() } }
    }
}

// MARK: - Update Mole

@MainActor final class UpdateModel: ObservableObject {
    @Published var version = ""
    @Published var output = ""
    @Published var busy = false
    func load() async {
        version = String(decoding: await Runner.capture(["--version"]), as: UTF8.self)
            .split(separator: "\n").first.map(String.init) ?? "Unknown"
    }
    func update() async {
        busy = true; output = ""
        output = Runner.strip(String(decoding: await Runner.capture(["update"], withErrors: true), as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        busy = false
        await load()
    }
}

struct UpdateView: View {
    @StateObject var m = UpdateModel()
    let colors: [Color] = [.cyan, .purple]
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "Update Mole", subtitle: "Clutterfly uses whatever Mole version is installed.", icon: "arrow.triangle.2.circlepath", colors: colors)
                Orb(colors: colors, busy: m.busy, icon: "arrow.down.circle.fill")
                Text(m.version).font(.title2.bold())
                BigButton(title: m.busy ? "Updating…" : "Update Now", icon: "arrow.down.circle.fill", colors: colors) {
                    Task { await m.update() }
                }
                .disabled(m.busy)
                if !m.output.isEmpty { outputBox(m.output) }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}
