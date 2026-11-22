import SwiftUI
import AppKit

// Screens built on macOS's own command-line tools (no mo):
// Running Apps, Startup Items, Ports, Large Files, Speed Test, Network Info, Battery,
// Sleep Blockers, Security Check, Disk First Aid, Updates, Quick Fixes, Tweaks, Shortcuts.

// MARK: - Parsers (pure, covered by systemSelfTest)

/// First match's capture groups.
func capture(_ pattern: String, _ s: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
}

/// The first `n` whitespace-separated fields, then the rest of the line (which may contain spaces).
func fields(_ line: Substring, _ n: Int) -> [String]? {
    var out: [String] = []
    var rest = line[...]
    for _ in 0..<n {
        rest = rest.drop { $0 == " " || $0 == "\t" }
        guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        out.append(String(rest[..<end]))
        rest = rest[end...]
    }
    out.append(String(rest.drop { $0 == " " || $0 == "\t" }))
    return out
}

/// JSON object inside output that may have warnings around it.
func jsonSlice(_ s: String) -> Data {
    guard let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") else { return Data() }
    return Data(s[a...b].utf8)
}

struct ProcInfo: Identifiable { var id: Int32 { pid }; let pid: Int32, cpu: Double, memKB: Double, user: String, path: String }
struct Listener: Identifiable { var id: String { "\(pid):\(port)" }; let pid: Int32, command: String, address: String, port: Int }
struct NetApp: Identifiable { var id: Int32 { pid }; let pid: Int32, command: String, connections: Int, remotes: [String] }
struct Blocker: Identifiable { let id = UUID(); let pid: Int32, process: String, duration: String, type: String, reason: String }
struct MacUpdate: Identifiable { var id: String { label }; let label: String, title: String, version: String, size: String, restart: Bool }

enum Parse {
    /// `ps -axo pid=,ppid=,pcpu=,rss=,user=,comm=`
    static func ps(_ out: String) -> [ProcInfo] {
        out.split(separator: "\n").compactMap { line in
            guard let f = fields(line, 5), let pid = Int32(f[0]) else { return nil }
            return ProcInfo(pid: pid, cpu: Double(f[2]) ?? 0, memKB: Double(f[3]) ?? 0, user: f[4], path: f[5])
        }
    }

    /// `lsof -F pcn` output: p<pid> / c<command> / n<name> records.
    static func lsof(_ out: String) -> [(pid: Int32, command: String, name: String)] {
        var pid: Int32 = 0, cmd = ""
        var rows: [(Int32, String, String)] = []
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": cmd = value
            case "n": rows.append((pid, cmd, value))
            default: break
            }
        }
        return rows
    }

    static func listeners(_ out: String) -> [Listener] {
        var seen = Set<String>()
        return lsof(out).compactMap { r in
            guard let colon = r.name.lastIndex(of: ":"), let port = Int(r.name[r.name.index(after: colon)...]) else { return nil }
            guard seen.insert("\(r.pid):\(port)").inserted else { return nil }
            return Listener(pid: r.pid, command: r.command, address: String(r.name[..<colon]), port: port)
        }
        .sorted { $0.port < $1.port }
    }

    static func netApps(_ out: String) -> [NetApp] {
        let rows = lsof(out).filter { $0.name.contains("->") }
        return Dictionary(grouping: rows) { $0.pid }.map { pid, conns in
            let remotes = conns.compactMap { c -> String? in
                let remote = c.name.components(separatedBy: "->").last ?? ""
                return remote.lastIndex(of: ":").map { String(remote[..<$0]) }
            }
            return NetApp(pid: pid, command: conns[0].command, connections: conns.count,
                          remotes: Array(NSOrderedSet(array: remotes).array as? [String] ?? []).prefix(3).map { $0 })
        }
        .sorted { $0.connections > $1.connections }
    }

    /// `pmset -g assertions`, the "Listed by owning process" part.
    static func blockers(_ out: String) -> [Blocker] {
        out.split(separator: "\n").compactMap { line in
            guard let c = capture(#"pid (\d+)\((.+?)\): \[[^\]]*\] (\d+:\d+:\d+) (\w+) named: "(.*?)""#, String(line)) else { return nil }
            return Blocker(pid: Int32(c[0]) ?? 0, process: c[1], duration: c[2], type: c[3], reason: c[4])
        }
    }

    /// `softwareupdate -l`
    static func macUpdates(_ out: String) -> [MacUpdate] {
        let lines = out.components(separatedBy: "\n")
        return lines.indices.compactMap { i in
            guard let label = capture(#"^\* Label: (.+)$"#, lines[i])?[0], i + 1 < lines.count else { return nil }
            let d = lines[i + 1]
            return MacUpdate(label: label,
                             title: capture(#"Title: ([^,]+)"#, d)?[0] ?? label,
                             version: capture(#"Version: ([^,]+)"#, d)?[0] ?? "",
                             size: capture(#"Size: (\d+)KiB"#, d).map { bytes((Double($0[0]) ?? 0) * 1024) } ?? "",
                             restart: d.contains("Action: restart"))
        }
    }

    /// `ioreg` "Key" = value lines.
    static func keyValues(_ out: String) -> [String: String] {
        var d: [String: String] = [:]
        for line in out.split(separator: "\n") {
            if let c = capture(#"^\s*"(\w+)" = (.+)$"#, String(line)) { d[c[0]] = c[1] }
        }
        return d
    }
}

func systemSelfTest() {
    let p = Parse.ps("  678     1   2.5  51200 sadek  /System/Library/CoreServices/Control Center.app/Contents/MacOS/ControlCenter\n")
    precondition(p.count == 1 && p[0].pid == 678 && p[0].cpu == 2.5 && p[0].user == "sadek" && p[0].path.hasSuffix("Control Center.app/Contents/MacOS/ControlCenter"))
    let l = Parse.listeners("p635\ncrapportd\nf10\nn*:51775\nf11\nn*:51775\np900\ncnode\nf3\nn127.0.0.1:3000\n")
    precondition(l.map(\.port) == [3000, 51775] && l[0].command == "node" && l[0].address == "127.0.0.1")
    let n = Parse.netApps("p10\ncChrome\nf1\nn192.168.1.2:5000->17.1.2.3:443\nf2\nn192.168.1.2:5001->17.1.2.3:443\nf3\nn*:*\n")
    precondition(n.count == 1 && n[0].connections == 2 && n[0].remotes == ["17.1.2.3"])
    let b = Parse.blockers(#"   pid 13727(caffeinate): [0x000b67a1000189a5] 00:00:28 PreventUserIdleSystemSleep named: "caffeinate command-line tool"  "#)
    precondition(b.count == 1 && b[0].process == "caffeinate" && b[0].type == "PreventUserIdleSystemSleep" && b[0].duration == "00:00:28")
    let u = Parse.macUpdates("* Label: macOS Tahoe 26.7.3-25G342\n\tTitle: macOS Tahoe 26.7.3, Version: 26.7.3, Size: 3107325KiB, Recommended: YES, Action: restart, \n")
    precondition(u.count == 1 && u[0].title == "macOS Tahoe 26.7.3" && u[0].version == "26.7.3" && u[0].restart)
    let kv = Parse.keyValues("      \"CycleCount\" = 200\n      \"IsCharging\" = No\n")
    precondition(kv["CycleCount"] == "200" && kv["IsCharging"] == "No")
}

// MARK: - Shared bits

func appIcon(pid: Int32, path: String) -> NSImage {
    NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(forFile: path)
}

/// Icon of the .app bundle a path lives in, if any.
func bundleIcon(_ path: String) -> NSImage? {
    guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) else { return nil }
    return NSWorkspace.shared.icon(forFile: String(path[..<r.upperBound]).replacingOccurrences(of: ".app/", with: ".app"))
}

func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 12) { content() }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
}

func openSettings(_ url: String) { NSWorkspace.shared.open(URL(string: url)!) }

// MARK: - Running Apps

@MainActor final class ProcessModel: ObservableObject {
    @Published var procs: [ProcInfo] = []
    @Published var filter = 0            // 0 apps, 1 background (mine), 2 everything
    @Published var sortByMemory = false
    @Published var search = ""
    @Published var message = ""
    @Published var forceTarget: ProcInfo?
    @Published var confirmForce = false
    private var apps: [Int32: NSRunningApplication] = [:]
    private var icons: [String: NSImage] = [:]

    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    func refresh() async {
        let out = await sh("ps -axo pid=,ppid=,pcpu=,rss=,user=,comm=").out
        apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }) { a, _ in a }
        procs = Parse.ps(out)
    }

    func isApp(_ p: ProcInfo) -> Bool { apps[p.pid]?.activationPolicy == .regular }
    func name(_ p: ProcInfo) -> String { apps[p.pid]?.localizedName ?? (p.path as NSString).lastPathComponent }
    func icon(_ p: ProcInfo) -> NSImage {
        if let i = apps[p.pid]?.icon { return i }
        if let i = icons[p.path] { return i }
        let i = bundleIcon(p.path) ?? NSWorkspace.shared.icon(forFile: p.path)
        icons[p.path] = i
        return i
    }
    func canStop(_ p: ProcInfo) -> Bool { p.user == NSUserName() && p.pid > 1 && p.pid != getpid() }

    var visible: [ProcInfo] {
        let me = NSUserName()
        var list = procs.filter { p in
            switch filter {
            case 0: return isApp(p)
            case 1: return !isApp(p) && p.user == me
            default: return true
            }
        }
        if !search.isEmpty { list = list.filter { name($0).localizedCaseInsensitiveContains(search) } }
        return list.sorted { sortByMemory ? $0.memKB > $1.memKB : $0.cpu > $1.cpu }
    }

    func quit(_ p: ProcInfo) {
        if let a = apps[p.pid] { a.terminate() } else { kill(p.pid, SIGTERM) }
        message = "Asked \(name(p)) to quit."
        Task { try? await Task.sleep(nanoseconds: 800_000_000); await refresh() }
    }

    func forceQuit(_ p: ProcInfo) {
        if let a = apps[p.pid] { a.forceTerminate() } else { kill(p.pid, SIGKILL) }
        message = "Force quit \(name(p)). Background helpers may be restarted by macOS."
        Task { try? await Task.sleep(nanoseconds: 800_000_000); await refresh() }
    }
}

struct ProcessesView: View {
    @StateObject var m = ProcessModel()
    let colors: [Color] = [.blue, .purple]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Running Apps", subtitle: "Everything running now, including hidden background processes.", icon: "square.stack.3d.up.fill", colors: colors)
            HStack {
                Picker("", selection: $m.filter) { Text("Apps").tag(0); Text("Background").tag(1); Text("Everything").tag(2) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                Picker("", selection: $m.sortByMemory) { Text("By CPU").tag(false); Text("By Memory").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                TextField("Search", text: $m.search).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("\(m.visible.count) shown · \(m.procs.count) processes in total").foregroundStyle(.secondary)
                Spacer()
                if !m.message.isEmpty { Text(m.message).foregroundStyle(.green) }
            }
            ScrollView {
                LazyVStack(spacing: 6) { ForEach(m.visible) { p in procRow(p) } }
            }
        }
        .padding(24)
        .task { await m.poll() }
        .confirmationDialog("Force quit?", isPresented: $m.confirmForce, presenting: m.forceTarget) { p in
            Button("Force Quit \(m.name(p))", role: .destructive) { m.forceQuit(p) }
        } message: { _ in Text("Unsaved work in it will be lost.") }
    }

    func procRow(_ p: ProcInfo) -> some View {
        row {
            Image(nsImage: m.icon(p)).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name(p)).font(.headline).lineLimit(1)
                Text("PID \(p.pid) · \(p.user)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().frame(width: 60, alignment: .trailing)
                .foregroundStyle(p.cpu > 50 ? .orange : .primary)
            Text(bytes(p.memKB * 1024)).monospacedDigit().frame(width: 80, alignment: .trailing)
            if m.canStop(p) {
                Button("Quit") { m.quit(p) }
                Button { m.forceTarget = p; m.confirmForce = true } label: { Image(systemName: "xmark.octagon.fill").foregroundStyle(.red) }
                    .buttonStyle(.plain).help("Force Quit")
            } else {
                pill("System", .gray).frame(width: 84)
            }
        }
    }
}

// MARK: - Startup Items

struct LaunchItem: Identifiable {
    var id: String { plist }
    let label: String, plist: String, program: String
    let scope: Int          // 0 = you, 1 = all users (agent), 2 = system daemon
    let disabled: Bool, running: Bool
}

@MainActor final class StartupModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var loading = true
    @Published var message = ""

    func load() async {
        let uid = getuid()
        let list = await sh("launchctl list").out
        let offUser = await sh("launchctl print-disabled gui/\(uid)").out
        let offSys = await sh("launchctl print-disabled system").out
        let dirs = [(NSHomeDirectory() + "/Library/LaunchAgents", 0), ("/Library/LaunchAgents", 1), ("/Library/LaunchDaemons", 2)]
        var result: [LaunchItem] = []
        for (dir, scope) in dirs {
            for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".plist") {
                let path = dir + "/" + f
                let d = NSDictionary(contentsOfFile: path) as? [String: Any] ?? [:]
                let label = d["Label"] as? String ?? String(f.dropLast(6))
                let program = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? ""
                let off = scope == 2 ? offSys : offUser
                let disabled = off.contains("\"\(label)\" => disabled") || off.contains("\"\(label)\" => true")
                let running = list.split(separator: "\n").contains { $0.hasSuffix("\t" + label) && !$0.hasPrefix("-") }
                result.append(LaunchItem(label: label, plist: path, program: program, scope: scope, disabled: disabled, running: running))
            }
        }
        items = result
        loading = false
    }

    func set(_ i: LaunchItem, on: Bool) async {
        let uid = getuid()
        if i.scope == 2 {
            // System daemons need an admin password.
            let cmd = on ? "sudo launchctl enable system/\(q(i.label)) && sudo launchctl bootstrap system \(q(i.plist))"
                         : "sudo launchctl bootout system/\(q(i.label)); sudo launchctl disable system/\(q(i.label))"
            Runner.openInTerminal(name: "startup", script: cmd)
            message = "Finish in Terminal (it asks for your password)."
            return
        }
        let target = "gui/\(uid)/\(i.label)"
        _ = await sh(on ? "launchctl enable \(q(target)); launchctl bootstrap gui/\(uid) \(q(i.plist))"
                        : "launchctl bootout \(q(target)); launchctl disable \(q(target))")
        message = on ? "Turned on \(i.label)." : "Turned off \(i.label). It stays off after restart."
        await load()
    }
}

struct StartupView: View {
    @StateObject var m = StartupModel()
    let colors: [Color] = [.orange, .red]
    let scopes = ["Just you", "All users", "System (needs password)"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Startup Items", subtitle: "Things that start on their own and keep running in the background.", icon: "power", colors: colors)
                HStack {
                    Button("Open Login Items in Settings") { openSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension") }
                    Text("Apps that open at login are managed there.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !m.message.isEmpty { Text(m.message).foregroundStyle(.green) }
                }
                if m.loading { Loading("Looking for startup items…", colors) }
                ForEach(0..<3) { s in
                    let group = m.items.filter { $0.scope == s }
                    if !group.isEmpty {
                        Text(scopes[s]).font(.title3.bold()).padding(.top, 6)
                        ForEach(group) { i in itemRow(i) }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }

    func itemRow(_ i: LaunchItem) -> some View {
        row {
            Image(nsImage: bundleIcon(i.program) ?? NSWorkspace.shared.icon(forFile: i.program.isEmpty ? i.plist : i.program))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(i.label).font(.headline).lineLimit(1)
                    if i.running { pill("Running", .green) }
                }
                Text(i.program.isEmpty ? i.plist : i.program).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: i.plist)]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder")
            Toggle("", isOn: Binding(get: { !i.disabled }, set: { on in Task { await m.set(i, on: on) } }))
                .toggleStyle(.switch).labelsHidden()
        }
    }
}

// MARK: - Ports in use

@MainActor final class PortsModel: ObservableObject {
    @Published var listeners: [Listener] = []
    @Published var loading = true
    @Published var message = ""
    func poll() async {
        while !Task.isCancelled {
            listeners = Parse.listeners(await sh("lsof -nP -iTCP -sTCP:LISTEN -Fpcn").out)
            loading = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }
    func stop(_ l: Listener, force: Bool) {
        let r = kill(l.pid, force ? SIGKILL : SIGTERM)
        message = r == 0 ? "Stopped \(l.command) on port \(l.port)." : "Couldn't stop \(l.command) (it may belong to the system)."
    }
}

struct PortsView: View {
    @StateObject var m = PortsModel()
    let colors: [Color] = [.teal, .blue]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Ports in Use", subtitle: "Which app is listening on which port. Handy when a dev server says \"address in use\".", icon: "point.3.connected.trianglepath.dotted", colors: colors)
                if !m.message.isEmpty { Text(m.message).foregroundStyle(.green) }
                if m.loading { Loading("Checking ports…", colors) }
                else if m.listeners.isEmpty { Text("Nothing of yours is listening on a port.").foregroundStyle(.secondary) }
                ForEach(m.listeners) { l in
                    row {
                        Text(":\(l.port)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 90, alignment: .leading)
                        Image(nsImage: appIcon(pid: l.pid, path: "")).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(NSRunningApplication(processIdentifier: l.pid)?.localizedName ?? l.command).font(.headline)
                            Text("PID \(l.pid)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        pill(["127.0.0.1", "[::1]", "localhost"].contains(l.address) ? "This Mac only" : "Open to network",
                             ["127.0.0.1", "[::1]", "localhost"].contains(l.address) ? .green : .yellow)
                        Button("Open") { NSWorkspace.shared.open(URL(string: "http://localhost:\(l.port)")!) }
                        Button("Stop") { m.stop(l, force: false) }
                        Button { m.stop(l, force: true) } label: { Image(systemName: "xmark.octagon.fill").foregroundStyle(.red) }
                            .buttonStyle(.plain).help("Force stop")
                    }
                }
                Text("Only your own apps are listed. System services need admin access to see.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .task { await m.poll() }
    }
}

// MARK: - Large files

struct BigFile: Identifiable { var id: String { path }; let path: String, size: Double, modified: Date? }

@MainActor final class LargeFilesModel: ObservableObject {
    @Published var mode = 0            // 0 large files, 1 old downloads
    @Published var minMB = 500
    @Published var files: [BigFile] = []
    @Published var loading = false
    @Published var target: BigFile?
    @Published var confirm = false

    func load() async {
        loading = true
        let paths: [String]
        if mode == 0 {
            // Spotlight already knows every file's size, so this is near-instant.
            paths = await sh("mdfind -onlyin \(q(NSHomeDirectory())) 'kMDItemFSSize > \(minMB * 1_000_000)'").out
                .split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }
        } else {
            let dl = NSHomeDirectory() + "/Downloads"
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            paths = ((try? FileManager.default.contentsOfDirectory(atPath: dl)) ?? []).map { dl + "/" + $0 }.filter {
                let d = (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
                return !($0 as NSString).lastPathComponent.hasPrefix(".") && (d ?? Date()) < cutoff
            }
        }
        var result: [BigFile] = []
        for p in paths {
            let a = try? FileManager.default.attributesOfItem(atPath: p)
            var size = (a?[.size] as? NSNumber)?.doubleValue ?? 0
            if a?[.type] as? FileAttributeType == .typeDirectory { size = await DevCacheModel.size(p) }
            result.append(BigFile(path: p, size: size, modified: a?[.modificationDate] as? Date))
        }
        files = result.sorted { $0.size > $1.size }
        loading = false
    }

    /// Never offer to trash app data; warn for cloud-synced files.
    static func rule(_ path: String) -> (canTrash: Bool, note: String?) {
        let lib = NSHomeDirectory() + "/Library/"
        if path.hasPrefix(lib + "CloudStorage/") || path.hasPrefix(lib + "Mobile Documents/") { return (true, "Cloud file") }
        if path.hasPrefix(lib) { return (false, "App data") }
        return (true, nil)
    }

    func trash(_ f: BigFile) {
        if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: f.path), resultingItemURL: nil)) != nil {
            files.removeAll { $0.path == f.path }
        }
    }
}

struct LargeFilesView: View {
    @StateObject var m = LargeFilesModel()
    let colors: [Color] = [.pink, .purple]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Large Files", subtitle: "Your biggest files, plus old stuff sitting in Downloads.", icon: "doc.badge.ellipsis", colors: colors)
            HStack {
                Picker("", selection: $m.mode) { Text("Large files").tag(0); Text("Downloads older than 90 days").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                if m.mode == 0 {
                    Picker("Bigger than", selection: $m.minMB) { Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1000); Text("5 GB").tag(5000) }
                        .frame(width: 200)
                }
                Spacer()
                Text("\(m.files.count) files · \(bytes(m.files.map(\.size).reduce(0, +)))").foregroundStyle(.secondary)
            }
            if m.loading { Loading("Searching…", colors) }
            else {
                ScrollView { LazyVStack(spacing: 6) { ForEach(m.files) { f in fileRow(f) } } }
            }
        }
        .padding(24)
        .task { await m.load() }
        .onChange(of: m.mode) { Task { await m.load() } }
        .onChange(of: m.minMB) { Task { await m.load() } }
        .confirmationDialog("Move to Trash?", isPresented: $m.confirm, presenting: m.target) { f in
            Button("Move to Trash", role: .destructive) { m.trash(f) }
        } message: { f in
            Text(LargeFilesModel.rule(f.path).note == "Cloud file"
                 ? "This file is synced, so it will also disappear from your cloud storage."
                 : "\((f.path as NSString).lastPathComponent) · \(bytes(f.size)). You can restore it from the Trash.")
        }
    }

    func fileRow(_ f: BigFile) -> some View {
        let rule = LargeFilesModel.rule(f.path)
        return row {
            Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text((f.path as NSString).lastPathComponent).font(.headline).lineLimit(1)
                    if let note = rule.note { pill(note, note == "App data" ? .gray : .cyan) }
                }
                Text(((f.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let d = f.modified { Text(d, style: .date).font(.caption).foregroundStyle(.secondary) }
            Text(bytes(f.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder")
            Button { m.target = f; m.confirm = true } label: { Image(systemName: "trash").foregroundStyle(rule.canTrash ? .red : .gray) }
                .buttonStyle(.plain).disabled(!rule.canTrash).help(rule.canTrash ? "Move to Trash" : "Remove it from inside the app that made it")
        }
    }
}

// MARK: - Speed test

struct SpeedResult: Decodable {
    let dl_throughput: Double?, ul_throughput: Double?, responsiveness: Double?, dl_responsiveness: Double?, base_rtt: Double?
    var rpm: Double { responsiveness ?? dl_responsiveness ?? 0 }
}

@MainActor final class SpeedModel: ObservableObject {
    @Published var result: SpeedResult?
    @Published var running = false
    @Published var error = ""
    func run() async {
        running = true; error = ""; result = nil
        let out = await sh("networkQuality -c -s").out
        result = try? JSONDecoder().decode(SpeedResult.self, from: jsonSlice(out))
        if result == nil { error = "The test didn't finish. Are you online?" }
        running = false
    }
}

struct SpeedTestView: View {
    @StateObject var m = SpeedModel()
    let colors: [Color] = [.cyan, .green]
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(title: "Speed Test", subtitle: "Apple's built-in test (networkQuality), against Apple's servers.", icon: "speedometer", colors: colors)
                Orb(colors: colors, busy: m.running, icon: "wifi")
                if m.running { Text("Testing download, then upload… about 30 seconds.").foregroundStyle(.secondary) }
                if let r = m.result {
                    HStack(spacing: 28) {
                        gauge("Download", (r.dl_throughput ?? 0) / 1e6, "arrow.down.circle.fill", [.cyan, .blue])
                        gauge("Upload", (r.ul_throughput ?? 0) / 1e6, "arrow.up.circle.fill", [.green, .mint])
                    }
                    HStack(spacing: 14) {
                        Card(title: "Latency", icon: "timer", color: .orange) {
                            Text("\(Int(r.base_rtt ?? 0)) ms").font(.title.bold())
                            Text("Time for a round trip when the line is idle.").font(.caption).foregroundStyle(.secondary)
                        }
                        Card(title: "Responsiveness", icon: "bolt.horizontal.fill", color: .purple) {
                            Text("\(Int(r.rpm)) RPM · \(r.rpm >= 1000 ? "High" : r.rpm >= 200 ? "Medium" : "Low")").font(.title.bold())
                            Text("How snappy things feel while the connection is busy.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !m.error.isEmpty { Text(m.error).foregroundStyle(.red) }
                BigButton(title: m.running ? "Testing…" : (m.result == nil ? "Start Test" : "Test Again"), icon: "play.fill", colors: colors) {
                    Task { await m.run() }
                }
                .disabled(m.running)
            }
            .padding(28)
        }
    }

    func gauge(_ title: String, _ mbps: Double, _ icon: String, _ c: [Color]) -> some View {
        VStack(spacing: 8) {
            Ring(value: min(mbps / 500, 1), colors: c, label: String(format: "%.0f", mbps), size: 150)
            Label("\(title) · Mbps", systemImage: icon).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Network info

@MainActor final class NetInfoModel: ObservableObject {
    @Published var rows: [(String, String)] = []
    @Published var apps: [NetApp] = []
    @Published var loading = true

    func load() async {
        let route = await sh("route -n get default").out
        let iface = capture(#"interface: (\S+)"#, route)?[0] ?? ""
        let gateway = capture(#"gateway: (\S+)"#, route)?[0] ?? "—"
        let ip = await sh("ipconfig getifaddr \(iface)").out.trimmingCharacters(in: .whitespacesAndNewlines)
        let hw = await sh("networksetup -listallhardwareports").out
        let portName = capture(#"Hardware Port: ([^\n]+)\nDevice: \#(iface)\n"#, hw)?[0]
        let dns = await sh("scutil --dns").out.split(separator: "\n")
            .compactMap { capture(#"nameserver\[\d+\] : (\S+)"#, String($0))?[0] }
        rows = [("Connected via", iface.isEmpty ? "Not connected" : "\(portName ?? iface) (\(iface))"),
                ("Your IP on this network", ip.isEmpty ? "—" : ip),
                ("Router", gateway),
                ("DNS servers", NSOrderedSet(array: dns).array.map { "\($0)" }.joined(separator: ", "))]
        apps = Parse.netApps(await sh("lsof -nP -i -Fpcn").out)
        loading = false
    }
}

struct NetInfoView: View {
    @StateObject var m = NetInfoModel()
    let colors: [Color] = [.blue, .teal]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ScreenHeader(title: "Network", subtitle: "Your connection, and which apps are talking to the internet.", icon: "network", colors: colors)
                    Button { Task { await m.load() } } label: { Image(systemName: "arrow.clockwise") }
                }
                if m.loading { Loading("Reading network…", colors) }
                else {
                    Card(title: "Connection", icon: "wifi", color: .blue) {
                        ForEach(m.rows, id: \.0) { r in
                            HStack(alignment: .top) {
                                Text(r.0).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                                Text(r.1).textSelection(.enabled)
                            }
                        }
                        Text("macOS hides the Wi-Fi name from apps without Location access, so it isn't shown.").font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "Apps using the network now", icon: "app.connected.to.app.below.fill", color: .teal) {
                        if m.apps.isEmpty { Text("None of your apps have open connections.").foregroundStyle(.secondary) }
                        ForEach(m.apps) { a in
                            HStack(spacing: 10) {
                                Image(nsImage: appIcon(pid: a.pid, path: "")).resizable().frame(width: 22, height: 22)
                                Text(NSRunningApplication(processIdentifier: a.pid)?.localizedName ?? a.command).frame(width: 180, alignment: .leading).lineLimit(1)
                                Text(a.remotes.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(a.connections) connection\(a.connections == 1 ? "" : "s")").monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Battery

@MainActor final class BatteryModel: ObservableObject {
    @Published var info: [String: String] = [:]
    @Published var timeLeft = ""
    @Published var lowPower = false
    @Published var watts: Int?
    func poll() async {
        while !Task.isCancelled {
            let io = await sh("ioreg -rn AppleSmartBattery").out
            info = Parse.keyValues(io)
            watts = capture(#""Watts"=(\d+)"#, io).flatMap { Int($0[0]) }
            timeLeft = capture(#"(\d+:\d+) remaining"#, await sh("pmset -g batt").out)?[0] ?? ""
            lowPower = capture(#"lowpowermode\s+(\d)"#, await sh("pmset -g").out)?[0] == "1"
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }
    func num(_ k: String) -> Double { Double(info[k] ?? "") ?? 0 }
}

struct BatteryView: View {
    @StateObject var m = BatteryModel()
    let colors: [Color] = [.green, .mint]
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenHeader(title: "Battery", subtitle: "Real capacity, wear and charging details.", icon: "battery.100.bolt", colors: colors)
                if m.info.isEmpty { Loading("Reading battery…", colors) }
                else if m.info["DesignCapacity"] == nil { Text("This Mac has no battery.").foregroundStyle(.secondary) }
                else { content }
            }
            .padding(28)
        }
        .task { await m.poll() }
    }

    var content: some View {
        let health = m.num("DesignCapacity") > 0 ? m.num("AppleRawMaxCapacity") / m.num("DesignCapacity") : 0
        let charging = m.info["IsCharging"] == "Yes", plugged = m.info["ExternalConnected"] == "Yes"
        return VStack(spacing: 18) {
            HStack(spacing: 40) {
                VStack { Ring(value: m.num("CurrentCapacity") / 100, colors: colors, label: "\(Int(m.num("CurrentCapacity")))%", size: 140); Text("Charge").foregroundStyle(.secondary) }
                VStack { Ring(value: health, colors: health > 0.8 ? [.green, .mint] : [.orange, .red], label: "\(Int(health * 100))%", size: 140); Text("Health").foregroundStyle(.secondary) }
            }
            Text(charging ? "Charging ⚡️" : plugged ? "Plugged in, not charging" : "On battery" + (m.timeLeft.isEmpty ? "" : " · \(m.timeLeft) left"))
                .font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                Card(title: "Cycles", icon: "arrow.triangle.2.circlepath", color: .green) { Text("\(Int(m.num("CycleCount")))").font(.title.bold()); Text("Apple rates these for 1000").font(.caption).foregroundStyle(.secondary) }
                Card(title: "Capacity", icon: "battery.75percent", color: .mint) { Text("\(Int(m.num("AppleRawMaxCapacity"))) mAh").font(.title.bold()); Text("of \(Int(m.num("DesignCapacity"))) mAh when new").font(.caption).foregroundStyle(.secondary) }
                Card(title: "Temperature", icon: "thermometer.medium", color: .orange) { Text(String(format: "%.1f °C", m.num("Temperature") / 100)).font(.title.bold()) }
                Card(title: "Charger", icon: "powerplug.fill", color: .yellow) { Text(plugged ? (m.watts.map { "\($0) W" } ?? "Connected") : "Not connected").font(.title.bold()) }
                Card(title: "Low Power Mode", icon: "leaf.fill", color: .green) {
                    Text(m.lowPower ? "On" : "Off").font(.title.bold())
                    Button("Battery Settings") { openSettings("x-apple.systempreferences:com.apple.Battery-Settings.extension") }
                }
            }
        }
    }
}

// MARK: - Sleep blockers

@MainActor final class SleepModel: ObservableObject {
    @Published var blockers: [Blocker] = []
    @Published var loaded = false
    @Published var confirmSleep = false
    func poll() async {
        while !Task.isCancelled {
            blockers = Parse.blockers(await sh("pmset -g assertions").out)
            loaded = true
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }
    static let friendly = [
        "PreventUserIdleSystemSleep": "Keeps the Mac awake", "PreventUserIdleDisplaySleep": "Keeps the screen on",
        "PreventSystemSleep": "Blocks sleep completely", "NoIdleSleepAssertion": "Keeps the Mac awake",
        "NoDisplaySleepAssertion": "Keeps the screen on", "UserIsActive": "You're using the Mac",
        "BackgroundTask": "Finishing a background task", "InternalPreventDisplaySleep": "Screen dimming timer",
        "ApplePushServiceTask": "Notifications", "NetworkClientActive": "Network activity",
    ]
}

struct SleepView: View {
    @StateObject var m = SleepModel()
    let colors: [Color] = [.indigo, .blue]
    var apps: [Blocker] { m.blockers.filter { $0.process != "powerd" } }
    var system: [Blocker] { m.blockers.filter { $0.process == "powerd" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Sleep Blockers", subtitle: "What's stopping your Mac or screen from going to sleep right now.", icon: "moon.zzz.fill", colors: colors)
                HStack {
                    BigButton(title: "Turn Off Screen", icon: "display", colors: colors) { Task { _ = await sh("pmset displaysleepnow") } }
                    BigButton(title: "Sleep Now", icon: "moon.fill", colors: [.purple, .pink]) { m.confirmSleep = true }
                }
                if !m.loaded { Loading("Checking…", colors) }
                Card(title: apps.isEmpty ? "No app is blocking sleep" : "Apps keeping it awake", icon: "app.badge.fill", color: .indigo) {
                    ForEach(apps) { b in
                        HStack(spacing: 10) {
                            Image(nsImage: appIcon(pid: b.pid, path: "")).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(NSRunningApplication(processIdentifier: b.pid)?.localizedName ?? b.process).font(.headline)
                                Text(b.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            pill(SleepModel.friendly[b.type] ?? b.type, .yellow)
                            Text(b.duration).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if !system.isEmpty {
                    Card(title: "macOS itself (normal)", icon: "apple.logo", color: .gray) {
                        ForEach(system) { b in
                            HStack {
                                Text(SleepModel.friendly[b.type] ?? b.type)
                                Spacer()
                                Text(b.duration).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.poll() }
        .confirmationDialog("Put your Mac to sleep now?", isPresented: $m.confirmSleep) {
            Button("Sleep") { Task { _ = await sh("pmset sleepnow") } }
        }
    }
}

// MARK: - Security check

struct SecurityCheck: Identifiable { let id: String, title: String, ok: Bool, why: String, settings: String? }

@MainActor final class SecurityModel: ObservableObject {
    @Published var checks: [SecurityCheck] = []
    func load() async {
        let fv = await sh("fdesetup status").out
        let fw = await sh("/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate").out
        let gk = await sh("spctl --status").out
        let sip = await sh("csrutil status").out
        checks = [
            SecurityCheck(id: "fv", title: "FileVault disk encryption", ok: fv.contains("FileVault is On"),
                          why: "Keeps your files unreadable if the Mac is lost or stolen.",
                          settings: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"),
            SecurityCheck(id: "fw", title: "Firewall", ok: !fw.contains("disabled") && !fw.contains("State = 0"),
                          why: "Blocks unwanted incoming connections, mainly on public Wi-Fi.",
                          settings: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"),
            SecurityCheck(id: "gk", title: "Gatekeeper", ok: gk.contains("assessments enabled"),
                          why: "Checks that apps come from identified developers before they open.",
                          settings: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
            SecurityCheck(id: "sip", title: "System Integrity Protection", ok: sip.contains("status: enabled"),
                          why: "Stops anything, even admin tools, from changing core system files. Only changeable from Recovery.",
                          settings: nil),
        ]
    }
}

struct SecurityView: View {
    @StateObject var m = SecurityModel()
    let colors: [Color] = [.green, .teal]
    var score: Int { m.checks.filter(\.ok).count }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(title: "Security Check", subtitle: "Read-only. This screen never changes a setting.", icon: "checkmark.shield.fill", colors: colors)
                if m.checks.isEmpty { Loading("Checking…", colors) }
                else {
                    Ring(value: Double(score) / Double(m.checks.count), colors: score == m.checks.count ? colors : [.orange, .yellow],
                         label: "\(score)/\(m.checks.count)", size: 130)
                    ForEach(m.checks) { c in
                        row {
                            Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.title).foregroundStyle(c.ok ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.headline)
                                Text(c.why).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(c.ok ? "On" : "Off").bold().foregroundStyle(c.ok ? .green : .orange)
                            if !c.ok, let s = c.settings { Button("Turn On in Settings") { openSettings(s) } }
                        }
                    }
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Disk First Aid

@MainActor final class FirstAidModel: ObservableObject {
    @Published var info: [(String, String)] = []
    @Published var running = false
    @Published var result = ""
    @Published var ok: Bool?
    func load() async {
        let out = await sh("diskutil info /").out
        info = ["Volume Name", "File System Personality", "SMART Status", "Disk Size", "Container Free Space"].compactMap { k in
            capture(#"\#(k):\s+(.+)"#, out).map { (k, $0[0].replacingOccurrences(of: #"\s*\(.*$"#, with: "", options: .regularExpression)) }
        }
    }
    func verify() async {
        running = true; result = ""; ok = nil
        let r = await sh("diskutil verifyVolume /")
        ok = r.out.contains("appears to be OK")
        result = r.out.split(separator: "\n").suffix(4).joined(separator: "\n")
        running = false
    }
}

struct FirstAidView: View {
    @StateObject var m = FirstAidModel()
    let colors: [Color] = [.red, .orange]
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenHeader(title: "Disk First Aid", subtitle: "Check your startup disk for errors, like Disk Utility does.", icon: "stethoscope", colors: colors)
                Orb(colors: colors, busy: m.running, icon: "internaldrive.fill")
                Card(title: "Startup disk", icon: "internaldrive", color: .orange) {
                    ForEach(m.info, id: \.0) { r in
                        HStack { Text(r.0).foregroundStyle(.secondary).frame(width: 200, alignment: .leading); Text(r.1) }
                    }
                }
                HStack {
                    BigButton(title: m.running ? "Checking… (a minute or two)" : "Check Disk", icon: "checkmark.circle", colors: colors) { Task { await m.verify() } }
                        .disabled(m.running)
                    BigButton(title: "Open Disk Utility", icon: "wrench.and.screwdriver.fill", colors: [.gray, .secondary]) { Task { _ = await sh("open -a 'Disk Utility'") } }
                }
                if let ok = m.ok {
                    Label(ok ? "Your disk looks healthy ✓" : "Problems found. Repair it in Disk Utility (for the startup disk, from Recovery).",
                          systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3.bold()).foregroundStyle(ok ? .green : .orange)
                }
                if !m.result.isEmpty { outputBox(m.result) }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Updates (macOS + Homebrew)

struct BrewOutdated: Decodable {
    struct Pkg: Decodable { let name: String; let installed_versions: [String]; let current_version: String }
    let formulae: [Pkg], casks: [Pkg]
}

@MainActor final class UpdatesModel: ObservableObject {
    @Published var mac: [MacUpdate] = []
    @Published var formulae: [BrewOutdated.Pkg] = []
    @Published var casks: [BrewOutdated.Pkg] = []
    @Published var loadingMac = true
    @Published var loadingBrew = true
    @Published var busy: String?
    @Published var output = ""

    func load() async {
        async let macOut = sh("softwareupdate -l")
        async let brewOut = sh("command -v brew >/dev/null || exit 127; brew update --quiet >/dev/null 2>&1; brew outdated --json=v2")
        let b = await brewOut
        let o = try? JSONDecoder().decode(BrewOutdated.self, from: jsonSlice(b.out))
        formulae = o?.formulae ?? []; casks = o?.casks ?? []
        loadingBrew = false
        mac = Parse.macUpdates(await macOut.out)
        loadingMac = false
    }

    func upgrade(_ name: String?, cask: Bool) async {
        busy = name ?? "all"; output = ""
        let r = await sh("brew upgrade" + (cask ? " --cask" : "") + (name.map { " " + q($0) } ?? ""))
        output = r.out.split(separator: "\n").suffix(6).joined(separator: "\n")
        if r.status != 0 { output += "\n\nIf it needs your password, run it in Terminal instead." }
        busy = nil
        loadingBrew = true
        let o = try? JSONDecoder().decode(BrewOutdated.self, from: jsonSlice(await sh("brew outdated --json=v2").out))
        formulae = o?.formulae ?? []; casks = o?.casks ?? []
        loadingBrew = false
    }
}

struct UpdatesView: View {
    @StateObject var m = UpdatesModel()
    let colors: [Color] = [.blue, .purple]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Updates", subtitle: "macOS and Homebrew updates in one place.", icon: "arrow.down.app.fill", colors: colors)
                Card(title: "macOS & Apple apps", icon: "apple.logo", color: .blue) {
                    if m.loadingMac { HStack { ProgressView().controlSize(.small); Text("Asking Apple… (up to a minute)") } }
                    else if m.mac.isEmpty { Text("Everything is up to date ✓").foregroundStyle(.green) }
                    ForEach(m.mac) { u in
                        HStack {
                            Text(u.title).font(.headline)
                            if u.restart { pill("Restart", .orange) }
                            Spacer()
                            Text(u.size).foregroundStyle(.secondary)
                        }
                    }
                    if !m.mac.isEmpty {
                        Button("Install in Software Update") { openSettings("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
                    }
                }
                Card(title: "Homebrew", icon: "mug.fill", color: .orange) {
                    if m.loadingBrew { HStack { ProgressView().controlSize(.small); Text("Checking Homebrew…") } }
                    else if m.formulae.isEmpty && m.casks.isEmpty { Text("Everything is up to date ✓").foregroundStyle(.green) }
                    else {
                        HStack {
                            Text("\(m.formulae.count + m.casks.count) outdated").foregroundStyle(.secondary)
                            Spacer()
                            Button("Upgrade All") { Task { await m.upgrade(nil, cask: false) } }.disabled(m.busy != nil)
                        }
                        ForEach(m.casks, id: \.name) { p in pkgRow(p, cask: true) }
                        ForEach(m.formulae, id: \.name) { p in pkgRow(p, cask: false) }
                    }
                }
                if !m.output.isEmpty { outputBox(m.output) }
            }
            .padding(28)
        }
        .task { await m.load() }
    }

    func pkgRow(_ p: BrewOutdated.Pkg, cask: Bool) -> some View {
        HStack {
            Text(p.name).font(.headline)
            if cask { pill("App", .blue) }
            Text("\(p.installed_versions.last ?? "") → \(p.current_version)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if m.busy == p.name || m.busy == "all" { ProgressView().controlSize(.small) }
            else { Button("Upgrade") { Task { await m.upgrade(p.name, cask: cask) } }.disabled(m.busy != nil) }
        }
    }
}

// MARK: - Quick fixes

struct Fix: Identifiable { let id: String, title: String, detail: String, icon: String, command: String; var admin = false }

let fixes: [Fix] = [
    Fix(id: "dock", title: "Restart Dock", detail: "Dock, Launchpad or Mission Control stuck.", icon: "dock.rectangle", command: "killall Dock"),
    Fix(id: "finder", title: "Restart Finder", detail: "Finder frozen, or new files not showing up.", icon: "folder.fill", command: "killall Finder"),
    Fix(id: "menubar", title: "Restart Menu Bar", detail: "Menu bar icons or Control Center misbehaving.", icon: "menubar.rectangle", command: "killall SystemUIServer ControlCenter"),
    Fix(id: "wifi", title: "Restart Wi-Fi", detail: "Connected, but nothing loads.", icon: "wifi",
        command: "d=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'); networksetup -setairportpower $d off; sleep 2; networksetup -setairportpower $d on"),
    Fix(id: "ql", title: "Reset Quick Look", detail: "Space-bar previews or thumbnails broken.", icon: "eye.fill", command: "qlmanage -r && qlmanage -r cache"),
    Fix(id: "dns", title: "Flush DNS Cache", detail: "Websites won't load, or open the wrong place.", icon: "globe", command: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", admin: true),
    Fix(id: "sound", title: "Restart Sound", detail: "No sound, or stuck on the wrong speaker.", icon: "speaker.wave.2.fill", command: "sudo killall coreaudiod", admin: true),
    Fix(id: "spotlight", title: "Rebuild Spotlight", detail: "Search can't find files that exist. Takes a while to re-index.", icon: "magnifyingglass", command: "sudo mdutil -E /", admin: true),
]

@MainActor final class FixesModel: ObservableObject {
    @Published var done: Set<String> = []
    @Published var running: String?
    func run(_ f: Fix) async {
        if f.admin { Runner.openInTerminal(name: f.id, script: f.command); return }
        running = f.id
        _ = await sh(f.command)
        running = nil
        done.insert(f.id)
    }
}

struct FixesView: View {
    @StateObject var m = FixesModel()
    let colors: [Color] = [.orange, .pink]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Quick Fixes", subtitle: "One-click cures for common little Mac glitches.", icon: "bandage.fill", colors: colors)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(fixes) { f in
                        Card(title: f.title, icon: f.icon, color: f.admin ? .yellow : .orange) {
                            Text(f.detail).foregroundStyle(.secondary).frame(minHeight: 34, alignment: .top)
                            HStack {
                                Button(f.admin ? "Run in Terminal…" : "Run") { Task { await m.run(f) } }.disabled(m.running != nil)
                                if m.running == f.id { ProgressView().controlSize(.small) }
                                if m.done.contains(f.id) { Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                                Spacer()
                                if f.admin { pill("Password", .yellow) }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

// MARK: - Finder, Dock & screenshot tweaks

struct Tweak: Identifiable {
    let id: String, title: String, domain: String, key: String
    var restart: String? = "Finder"
    var onWrite = "-bool true"
    var offWrite: String? = "-bool false"     // nil = delete the key (back to the macOS default)
    var onValue = "1"
}

let tweaks: [Tweak] = [
    Tweak(id: "hidden", title: "Show hidden files in Finder", domain: "com.apple.finder", key: "AppleShowAllFiles"),
    Tweak(id: "ext", title: "Show all file extensions", domain: "NSGlobalDomain", key: "AppleShowAllExtensions"),
    Tweak(id: "path", title: "Show path bar in Finder", domain: "com.apple.finder", key: "ShowPathbar"),
    Tweak(id: "status", title: "Show status bar in Finder", domain: "com.apple.finder", key: "ShowStatusBar"),
    Tweak(id: "folders", title: "Keep folders on top when sorting", domain: "com.apple.finder", key: "_FXSortFoldersFirst"),
    Tweak(id: "autohide", title: "Auto-hide the Dock", domain: "com.apple.dock", key: "autohide", restart: "Dock"),
    Tweak(id: "delay", title: "Dock appears instantly (no delay)", domain: "com.apple.dock", key: "autohide-delay", restart: "Dock",
          onWrite: "-float 0", offWrite: nil, onValue: "0"),
    Tweak(id: "recents", title: "Hide recent apps in the Dock", domain: "com.apple.dock", key: "show-recents", restart: "Dock",
          onWrite: "-bool false", offWrite: "-bool true", onValue: "0"),
    Tweak(id: "shadow", title: "No window shadow in screenshots", domain: "com.apple.screencapture", key: "disable-shadow", restart: "SystemUIServer"),
    Tweak(id: "dsnet", title: "No .DS_Store files on network drives", domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", restart: nil),
    Tweak(id: "dsusb", title: "No .DS_Store files on USB drives", domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", restart: nil),
]

@MainActor final class TweaksModel: ObservableObject {
    @Published var on: [String: Bool] = [:]
    @Published var shotFolder = ""
    @Published var shotType = "png"

    func load() async {
        for t in tweaks {
            on[t.id] = await sh("defaults read \(t.domain) \(q(t.key)) 2>/dev/null").out.trimmingCharacters(in: .whitespacesAndNewlines) == t.onValue
        }
        let loc = await sh("defaults read com.apple.screencapture location 2>/dev/null").out.trimmingCharacters(in: .whitespacesAndNewlines)
        shotFolder = loc.isEmpty ? NSHomeDirectory() + "/Desktop" : (loc as NSString).expandingTildeInPath
        let type = await sh("defaults read com.apple.screencapture type 2>/dev/null").out.trimmingCharacters(in: .whitespacesAndNewlines)
        shotType = type.isEmpty ? "png" : type
    }

    func set(_ t: Tweak, _ value: Bool) async {
        on[t.id] = value
        let write = value ? "defaults write \(t.domain) \(q(t.key)) \(t.onWrite)"
                          : t.offWrite.map { "defaults write \(t.domain) \(q(t.key)) \($0)" } ?? "defaults delete \(t.domain) \(q(t.key))"
        _ = await sh(write + (t.restart.map { "; killall \($0)" } ?? ""))
    }

    func chooseFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Save Screenshots Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        shotFolder = url.path
        _ = await sh("defaults write com.apple.screencapture location \(q(url.path)); killall SystemUIServer")
    }

    func setType(_ t: String) async {
        shotType = t
        _ = await sh("defaults write com.apple.screencapture type \(q(t)); killall SystemUIServer")
    }
}

struct TweaksView: View {
    @StateObject var m = TweaksModel()
    let colors: [Color] = [.purple, .indigo]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Tweaks", subtitle: "Handy hidden macOS settings. Flip one back any time.", icon: "slider.horizontal.3", colors: colors)
                Card(title: "Finder & Dock", icon: "macwindow", color: .purple) {
                    ForEach(tweaks) { t in
                        Toggle(t.title, isOn: Binding(get: { m.on[t.id] ?? false }, set: { v in Task { await m.set(t, v) } }))
                            .toggleStyle(.switch)
                    }
                    Text("Finder or the Dock restarts for a second after a change.").font(.caption).foregroundStyle(.secondary)
                }
                Card(title: "Screenshots", icon: "camera.viewfinder", color: .indigo) {
                    HStack {
                        Text("Save to").foregroundStyle(.secondary)
                        Text((m.shotFolder as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change…") { Task { await m.chooseFolder() } }
                    }
                    Picker("Format", selection: Binding(get: { m.shotType }, set: { v in Task { await m.setType(v) } })) {
                        Text("PNG").tag("png"); Text("JPG").tag("jpg"); Text("HEIC").tag("heic"); Text("PDF").tag("pdf")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(28)
        }
        .task { await m.load() }
    }
}

// MARK: - Shortcuts

@MainActor final class ShortcutsModel: ObservableObject {
    @Published var names: [String] = []
    @Published var search = ""
    @Published var running: String?
    @Published var output = ""
    @Published var loading = true
    var filtered: [String] { search.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(search) } }
    func load() async {
        names = await sh("shortcuts list").out.split(separator: "\n").map(String.init)
        loading = false
    }
    func run(_ name: String) async {
        running = name; output = ""
        let r = await sh("shortcuts run \(q(name))")
        output = r.status == 0 ? "✓ \(name) finished" + (r.out.isEmpty ? "" : ":\n\(r.out)") : "\(name) failed:\n\(r.out)"
        running = nil
    }
}

struct ShortcutsView: View {
    @StateObject var m = ShortcutsModel()
    let colors: [Color] = [.pink, .orange]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Shortcuts", subtitle: "Run your Shortcuts app shortcuts with one click.", icon: "square.on.square.squareshape.controlhandles", colors: colors)
            HStack {
                TextField("Search shortcuts", text: $m.search).textFieldStyle(.roundedBorder)
                Button("Open Shortcuts") { Task { _ = await sh("open -a Shortcuts") } }
            }
            if !m.output.isEmpty { outputBox(m.output) }
            if m.loading { Loading("Loading your shortcuts…", colors) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(m.filtered, id: \.self) { n in
                        Button { Task { await m.run(n) } } label: {
                            HStack {
                                Image(systemName: m.running == n ? "hourglass" : "play.circle.fill").font(.title2)
                                Text(n).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(LinearGradient(colors: colors.map { $0.opacity(0.7) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(m.running != nil)
                    }
                }
            }
            Text("Shortcuts that ask for input may stop with an error here. Run those from the Shortcuts app.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .task { await m.load() }
    }
}
