import SwiftUI
import AppKit

// Friendly GUI around the free `mo` CLI (brew install mole).
// Note: built with Command Line Tools only, whose SDK lacks SwiftUI macro plugins,
// so there is no @State / #Preview here — all UI state lives in the Runner object.

@main struct ClutterflyApp: App {
    init() { if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) } }
    var body: some Scene {
        // Single window (not WindowGroup) so the menu bar can bring the same one back.
        Window("Clutterfly", id: "main") { ContentView().frame(minWidth: 960, minHeight: 660) }
            .windowStyle(.hiddenTitleBar)
        MenuBarExtra { MenuBarContent() } label: { MenuBarLabel() }
    }
}

// MARK: - Tools

struct Tool: Identifiable, Hashable {
    let id: String, title: String, icon: String, blurb: String
    let colors: [Color]
    var preview: [String]? = nil   // dry-run args (scan-style tools)
    var run: [String]? = nil       // real run args, shown as `runLabel` after a scan
    var runLabel = "Clean Now"
    var group = "Clean"
}

let toolGroups = ["Clean", "Explore", "Apps", "Network", "Power", "System", "Tools"]

// To add a tool: append a Tool here. Scan-style mo commands just need preview/run args;
// anything else gets its own screen in Screens.swift plus a `case` in ContentView.
let tools: [Tool] = [
    // Clean
    Tool(id: "clean", title: "Smart Clean", icon: "sparkles", blurb: "Caches, logs, temp files and leftovers from deleted apps.",
         colors: [.pink, .orange], preview: ["clean", "--dry-run"], run: ["clean"]),
    Tool(id: "devcaches", title: "Dev Caches", icon: "chevron.left.forwardslash.chevron.right", blurb: "",
         colors: [.green, .teal]),
    Tool(id: "docker", title: "Docker", icon: "shippingbox.circle.fill", blurb: "", colors: [.blue, .cyan]),
    Tool(id: "purge", title: "Project Junk", icon: "hammer.fill", blurb: "Old build folders like node_modules, target, .build.",
         colors: [.purple, .blue], preview: ["purge", "--dry-run"], run: ["purge", "--yes"], runLabel: "Remove Junk"),
    Tool(id: "installer", title: "Installers", icon: "shippingbox.fill", blurb: ".dmg and .pkg files you already installed.",
         colors: [.teal, .green], preview: ["installer", "--dry-run"]),
    Tool(id: "largefiles", title: "Large Files", icon: "doc.badge.ellipsis", blurb: "", colors: [.pink, .purple]),
    Tool(id: "snapshots", title: "Snapshots", icon: "clock.arrow.circlepath", blurb: "", colors: [.indigo, .purple]),
    // Explore
    Tool(id: "status", title: "Live Status", icon: "gauge.with.needle.fill", blurb: "", colors: [.green, .mint], group: "Explore"),
    Tool(id: "analyze", title: "Disk Explorer", icon: "chart.pie.fill", blurb: "", colors: [.blue, .cyan], group: "Explore"),
    Tool(id: "drives", title: "External Drives", icon: "externaldrive.fill", blurb: "", colors: [.orange, .yellow], group: "Explore"),
    Tool(id: "history", title: "History & Alerts", icon: "chart.bar.xaxis", blurb: "", colors: [.mint, .green], group: "Explore"),
    // Apps
    Tool(id: "processes", title: "Running Apps", icon: "square.stack.3d.up.fill", blurb: "", colors: [.blue, .purple], group: "Apps"),
    Tool(id: "startup", title: "Startup Items", icon: "power", blurb: "", colors: [.orange, .red], group: "Apps"),
    Tool(id: "updates", title: "Updates", icon: "arrow.down.app.fill", blurb: "", colors: [.blue, .purple], group: "Apps"),
    Tool(id: "uninstall", title: "Uninstall Apps", icon: "trash.fill", blurb: "", colors: [.red, .pink], group: "Apps"),
    Tool(id: "slim", title: "Slim Apps", icon: "scissors", blurb: "Remove the Intel-only code from apps. This Mac runs Apple Silicon and never uses it.",
         colors: [.purple, .pink], preview: ["slim", "--dry-run"], group: "Apps"),
    // Network
    Tool(id: "speed", title: "Speed Test", icon: "speedometer", blurb: "", colors: [.cyan, .green], group: "Network"),
    Tool(id: "netinfo", title: "Network Info", icon: "network", blurb: "", colors: [.blue, .teal], group: "Network"),
    Tool(id: "ports", title: "Ports in Use", icon: "point.3.connected.trianglepath.dotted", blurb: "", colors: [.teal, .blue], group: "Network"),
    // Power
    Tool(id: "battery", title: "Battery", icon: "battery.100.bolt", blurb: "", colors: [.green, .mint], group: "Power"),
    Tool(id: "sleep", title: "Sleep Blockers", icon: "moon.zzz.fill", blurb: "", colors: [.indigo, .blue], group: "Power"),
    Tool(id: "caffeinate", title: "Caffeinate", icon: "cup.and.saucer.fill", blurb: "", colors: [.orange, .brown], group: "Power"),
    // System
    Tool(id: "security", title: "Security Check", icon: "checkmark.shield.fill", blurb: "", colors: [.green, .teal], group: "System"),
    Tool(id: "firstaid", title: "Disk First Aid", icon: "stethoscope", blurb: "", colors: [.red, .orange], group: "System"),
    Tool(id: "fixes", title: "Quick Fixes", icon: "bandage.fill", blurb: "", colors: [.orange, .pink], group: "System"),
    Tool(id: "tweaks", title: "Tweaks", icon: "slider.horizontal.3", blurb: "", colors: [.purple, .indigo], group: "System"),
    Tool(id: "shortcuts", title: "Shortcuts", icon: "square.on.square.squareshape.controlhandles", blurb: "", colors: [.pink, .orange], group: "System"),
    // Tools
    Tool(id: "optimize", title: "Optimize", icon: "bolt.fill", blurb: "Refresh system caches, fix broken settings files, flush DNS.",
         colors: [.yellow, .orange], preview: ["optimize", "--dry-run"], run: ["optimize"], runLabel: "Optimize Now", group: "Tools"),
    Tool(id: "protect", title: "Protected Items", icon: "lock.shield.fill", blurb: "", colors: [.yellow, .green], group: "Tools"),
    Tool(id: "touchid", title: "Touch ID", icon: "touchid", blurb: "", colors: [.pink, .red], group: "Tools"),
    Tool(id: "update", title: "Update Mole", icon: "arrow.triangle.2.circlepath", blurb: "", colors: [.cyan, .purple], group: "Tools"),
]

// MARK: - Parsing mo output

struct Item: Identifiable { let id = UUID(); let kind: Kind; let name: String; let detail: String
    enum Kind { case found, done, review, skipped }
}
struct Section: Identifiable { let id = UUID(); let title: String; var items: [Item] = [] }

struct Report {
    var sections: [Section] = []
    var headline = ""     // "6.24GB+" or "Removed: 1.2GB"
    var subline = ""      // "519 items"
    var current = ""      // section being scanned right now

    mutating func feed(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("➤ ") {
            current = String(line.dropFirst(2))
            sections.append(Section(title: current))
        } else if line.hasPrefix("Potential space:") || line.hasPrefix("Removed:") {
            let parts = line.components(separatedBy: " · ")
            headline = parts[0].replacingOccurrences(of: "Potential space: ", with: "")
            subline = parts.dropFirst().joined(separator: " · ")
        } else if raw.hasPrefix("  "), !raw.hasPrefix("    "), let icon = line.first,
                  let kind: Item.Kind = ["○": .found, "●": .found, "✓": .done, "⊙": .review, "◎": .skipped, "☻": .skipped][String(icon)],
                  !sections.isEmpty {
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if body == "Nothing to clean" { return }
            var parts = body.components(separatedBy: " · ")
            let name = parts.removeFirst()
            var detail = parts.joined(separator: " · ")
            if detail.hasSuffix(" dry") { detail = String(detail.dropLast(4)) }
            sections[sections.count - 1].items.append(Item(kind: kind, name: name, detail: detail))
        } else if raw.hasPrefix("  "), !raw.hasPrefix("    "),
                  let m = line.range(of: #"^(.+?)\s{2,}([0-9.]+\s?[KMGT]?B)$"#, options: .regularExpression) {
            // Plain "  Name      870.8MB" rows, e.g. mo slim.
            let row = String(line[m])
            let size = row.range(of: #"[0-9.]+\s?[KMGT]?B$"#, options: .regularExpression).map { String(row[$0]) } ?? ""
            if sections.isEmpty { sections.append(Section(title: "Found")) }
            sections[sections.count - 1].items.append(
                Item(kind: .found, name: row.replacingOccurrences(of: size, with: "").trimmingCharacters(in: .whitespaces), detail: size))
        } else if let m = line.range(of: #"^\d+ apps?, [0-9.]+\s?[KMGT]?B"#, options: .regularExpression) {
            let parts = line[m].components(separatedBy: ", ")   // "9 apps, 1.40GB of Intel code"
            headline = parts[1]; subline = parts[0]
        }
    }
}

func selfTest() {
    var r = Report()
    """
    ➤ User essentials
      ○ User app cache · 9 items, 2.74GB dry
      ◎ Trash · skipped, grant Full Disk Access to your terminal
    ➤ Virtualization
      ✓ Nothing to clean
    ➤ Large files
      ⊙ Docker storage · Images 9.169GB, 2.734GB reclaimable
        pcre2 10.47_1 · 7.3MB
    Potential space: 6.24GB+ · 519 items
    """.split(separator: "\n").forEach { r.feed(String($0)) }
    precondition(r.sections.map(\.title) == ["User essentials", "Virtualization", "Large files"])
    precondition(r.sections[0].items.count == 2 && r.sections[0].items[0].detail == "9 items, 2.74GB")
    precondition(r.sections[1].items.isEmpty)
    precondition(r.sections[2].items.count == 1 && r.sections[2].items[0].kind == .review)
    precondition(r.headline == "6.24GB+" && r.subline == "519 items")
    systemSelfTest()
    var slim = Report()
    ["  Google Chrome        870.8MB", "  ZoomLauncher           420KB", "9 apps, 1.40GB of Intel code"].forEach { slim.feed($0) }
    precondition(slim.sections.first?.items.map(\.name) == ["Google Chrome", "ZoomLauncher"], "\(slim.sections)")
    precondition(slim.sections[0].items[0].detail == "870.8MB" && slim.headline == "1.40GB" && slim.subline == "9 apps")
    precondition(parseSize("2.734GB") == 2.734e9 && parseSize("938kB") == 938_000 && parseSize("1.40GB+") == 1.4e9 && parseSize("0B") == 0)
    // Live check: the native screens can decode what the installed mo prints.
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        let status = try? JSONDecoder().decode(Snapshot.self, from: await Runner.capture(["status", "--json"]))
        let apps = try? JSONDecoder().decode([AppInfo].self, from: await Runner.capture(["uninstall", "--list"]))
        let disk = try? JSONDecoder().decode(Analysis.self, from: await Runner.capture(["analyze", "--json", NSHomeDirectory() + "/Library/Logs"]))
        let history = try? JSONDecoder().decode(HistoryFile.self, from: await Runner.capture(["history", "--json", "--limit", "200"]))
        print("history:", history.map { "\($0.sessions.count) sessions" } ?? "FAILED",
              "· protected defaults:", ProtectModel.moleDefaults().count)
        precondition(history != nil, "mo history no longer decodes")
        // Live check of the macOS-tool screens.
        let procs = Parse.ps(await sh("ps -axo pid=,ppid=,pcpu=,rss=,user=,comm=").out)
        let ports = Parse.listeners(await sh("lsof -nP -iTCP -sTCP:LISTEN -Fpcn").out)
        let net = Parse.netApps(await sh("lsof -nP -i -Fpcn").out)
        let blockers = Parse.blockers(await sh("pmset -g assertions").out)
        let battery = Parse.keyValues(await sh("ioreg -rn AppleSmartBattery").out)
        print("processes:", procs.count, "· ports:", ports.map { "\($0.command):\($0.port)" }.prefix(4),
              "· net apps:", net.count, "· sleep blockers:", blockers.count, "· battery cycles:", battery["CycleCount"] ?? "none")
        precondition(procs.count > 50 && procs.allSatisfy { $0.path.hasPrefix("/") || !$0.path.isEmpty }, "ps parsing broke")
        print("status:", status.map { "health \(Int($0.health_score))" } ?? "FAILED",
              "· apps:", apps.map { "\($0.count)" } ?? "FAILED",
              "· analyze:", disk?.entries.map { "\($0.count) entries" } ?? "FAILED")
        precondition(status != nil && apps != nil && disk != nil, "mo output no longer decodes")
        done.signal()
    }
    done.wait()
    print("selftest ok · full disk access:", Runner.checkFullDiskAccess())
    // Optional: `--selftest file.txt` parses a saved `mo clean --dry-run` output.
    if let i = CommandLine.arguments.firstIndex(of: "--selftest"), i + 1 < CommandLine.arguments.count,
       let text = try? String(contentsOfFile: CommandLine.arguments[i + 1]) {
        var real = Report()
        Runner.strip(text).components(separatedBy: "\n").forEach { real.feed($0) }
        real.sections.forEach { print("\($0.title): \($0.items.count) items") }
        print("headline:", real.headline, "|", real.subline)
    }
}

// MARK: - Runner

final class Runner: ObservableObject {
    static let shared = Runner()          // shared by the window and the menu bar
    @Published var selection: String? = "clean"
    @Published var explorerStart: String?  // set by External Drives → opens Disk Explorer there
    @Published var log = ""
    @Published var report = Report()
    @Published var running = false
    @Published var didRealRun = false
    @Published var confirmClean = false
    @Published var showLog = false
    private var proc: Process?
    private var buffer = ""

    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        // GUI apps don't inherit the shell PATH; mo shells out to brew, docker, etc.
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (e["PATH"] ?? "")
        e["NO_COLOR"] = "1"
        return e
    }()

    @Published var moInstalled = Runner.find("mo") != nil
    @Published var hasFullDiskAccess = Runner.checkFullDiskAccess()

    /// TCC.db can only be opened with Full Disk Access, and trying never shows a prompt.
    static func checkFullDiskAccess() -> Bool {
        let fd = open(NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 { close(fd) }
        return fd >= 0
    }

    /// Opens Settings › Privacy & Security › Full Disk Access and shows this app in Finder so it can be dragged in.
    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func find(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin"].map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// brew present → install in-app. No brew → Homebrew's installer needs a password prompt, so use Terminal.
    func installMole() {
        if Self.find("brew") != nil { run(["install", "mole"], program: "brew"); return }
        Self.openInTerminal(name: "install", script: """
            echo "Installing Homebrew, then Mole. Homebrew will ask for your Mac password."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &&
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" &&
            brew install mole &&
            echo "\\nDone! Switch back to Clutterfly."
            """)
    }

    func run(_ args: [String], program: String = "mo") {
        guard !running else { return }
        log = "$ \(program) \(args.joined(separator: " "))\n\n"
        report = Report(); buffer = ""
        didRealRun = program == "mo" && !args.contains("--dry-run")
        running = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [program] + args
        p.environment = Self.env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.standardInput = FileHandle.nullDevice  // forces mo's non-interactive mode
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let text = Self.strip(String(decoding: h.availableData, as: UTF8.self))
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self.append(text) }
        }
        p.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self.append("\n"); self.running = false
                self.moInstalled = Self.find("mo") != nil
            }
        }
        do { try p.run(); proc = p } catch {
            append("Could not run mo: \(error.localizedDescription)\nInstall it with: brew install mole\n")
            running = false
        }
    }

    func stop() { proc?.terminate() }

    /// Runs `mo args` off the main thread and returns stdout (for the --json / --list modes).
    static func capture(_ args: [String], withErrors: Bool = false) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = ["mo"] + args
                p.environment = env
                p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                p.standardInput = FileHandle.nullDevice
                let out = Pipe()
                p.standardOutput = out; p.standardError = withErrors ? out : FileHandle.nullDevice
                guard (try? p.run()) != nil else { return cont.resume(returning: Data()) }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: data)
            }
        }
    }

    private func append(_ text: String) {
        log += text
        buffer += text
        var lines = buffer.components(separatedBy: "\n")
        buffer = lines.removeLast()          // keep partial line for next chunk
        lines.forEach { report.feed($0) }
    }

    static func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
         .replacingOccurrences(of: "\r", with: "\n")
    }

    // Interactive (TUI) commands need a real terminal: hand them to Terminal.app via a .command file.
    static func openInTerminal(_ cmd: String) { openInTerminal(name: cmd, script: "mo \(cmd)") }

    static func openInTerminal(name: String, script: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mole-\(name).command")
        try? "#!/bin/zsh -l\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Views

let bg = LinearGradient(colors: [Color(red: 0.10, green: 0.07, blue: 0.22), Color(red: 0.04, green: 0.03, blue: 0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)

struct ContentView: View {
    @ObservedObject var r = Runner.shared
    @ObservedObject var caffeine = Caffeine.shared
    var tool: Tool { tools.first { $0.id == r.selection } ?? tools[0] }

    var body: some View {
        Group {
            if r.moInstalled { main } else { ZStack { bg.ignoresSafeArea(); SetupView(r: r) } }
        }
        .preferredColorScheme(.dark)
        // Re-check when the user comes back from a Terminal install.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !r.running { r.moInstalled = Runner.find("mo") != nil }
            r.hasFullDiskAccess = Runner.checkFullDiskAccess()
        }
    }

    var main: some View {
        NavigationSplitView {
            List(selection: $r.selection) {
                ForEach(toolGroups, id: \.self) { g in
                    SwiftUI.Section(g) {
                        ForEach(tools.filter { $0.group == g }) { t in
                            Label {
                                HStack {
                                    Text(t.title)
                                    if t.id == "caffeinate", caffeine.active { Circle().fill(.green).frame(width: 7, height: 7) }
                                }
                            } icon: { IconTile(icon: t.icon, colors: t.colors, size: 22) }
                                .tag(t.id).padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(210)
            .disabled(r.running)
        } detail: {
            ZStack {
                bg.ignoresSafeArea()
                switch tool.id {
                case "status": StatusView()
                case "analyze": ExplorerView()
                case "uninstall": UninstallView()
                case "caffeinate": CaffeinateView()
                case "docker": DockerView()
                case "devcaches": DevCachesView()
                case "snapshots": SnapshotsView()
                case "history": HistoryView()
                case "protect": ProtectView()
                case "drives": DrivesView()
                case "touchid": TouchIDView()
                case "update": UpdateView()
                case "processes": ProcessesView()
                case "startup": StartupView()
                case "ports": PortsView()
                case "largefiles": LargeFilesView()
                case "speed": SpeedTestView()
                case "netinfo": NetInfoView()
                case "battery": BatteryView()
                case "sleep": SleepView()
                case "security": SecurityView()
                case "firstaid": FirstAidView()
                case "updates": UpdatesView()
                case "fixes": FixesView()
                case "tweaks": TweaksView()
                case "shortcuts": ShortcutsView()
                default: ToolView(r: r, tool: tool)
                }
            }
                .safeAreaInset(edge: .top) { if !r.hasFullDiskAccess { AccessBanner() } }
        }
        .onChange(of: r.selection) { r.report = Report(); r.log = ""; r.showLog = false }
    }
}

/// Without Full Disk Access macOS asks again for each protected folder on every scan.
struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stop the permission pop-ups").font(.headline)
                Text("Give Clutterfly Full Disk Access once. In Settings, turn on Clutterfly, or drag it in from the Finder window that opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { Runner.openFullDiskAccessSettings() }.buttonStyle(.borderedProminent).tint(.yellow)
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.yellow.opacity(0.4)))
        .padding(.horizontal, 20).padding(.top, 8)
    }
}

struct SetupView: View {
    @ObservedObject var r: Runner
    let colors: [Color] = [.pink, .purple]
    var body: some View {
        VStack(spacing: 20) {
            Orb(colors: colors, busy: r.running, icon: "arrow.down.circle.fill")
            Text(r.running ? "Installing Mole…" : "Welcome!").font(.largeTitle.bold())
            Text(r.running ? "This can take a minute." :
                 "Clutterfly needs the free Mole tool to scan and clean your Mac.\nIt isn't installed yet. One click sets it up.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if r.running {
                BigButton(title: "Stop", icon: "stop.fill", colors: [.gray, .secondary]) { r.stop() }
            } else {
                BigButton(title: "Install Mole", icon: "arrow.down.circle.fill", colors: colors) { r.installMole() }
                Text(Runner.find("brew") != nil ? "Runs: brew install mole"
                     : "Homebrew isn't installed either, so this opens Terminal to install Homebrew first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !r.log.isEmpty {
                ScrollView {
                    Text(r.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(maxWidth: 640, maxHeight: 180)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(32)
    }
}

struct IconTile: View {
    let icon: String, colors: [Color], size: CGFloat
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

/// Scanner: the tool's icon on a glossy disc inside a ring. While working, a comet arc sweeps the ring
/// and the disc breathes; when idle it sits still (the timeline pauses, so no CPU is spent).
struct Orb: View {
    let colors: [Color], busy: Bool
    var icon = "sparkles"
    var body: some View {
        TimelineView(.animation(paused: !busy)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let spin = Angle.degrees((t * 240).truncatingRemainder(dividingBy: 360))
            let breathe = busy ? 1 + 0.03 * sin(t * 3) : 1
            ZStack {
                Circle().fill(RadialGradient(colors: [colors[0].opacity(busy ? 0.4 : 0.2), .clear],
                                             center: .center, startRadius: 60, endRadius: 120))
                Circle().stroke(colors[0].opacity(0.15), lineWidth: 8).frame(width: 180, height: 180)
                if busy {
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(AngularGradient(colors: [colors[0].opacity(0), colors[0], colors[1]], center: .center,
                                                startAngle: .zero, endAngle: .degrees(108)),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 180, height: 180).rotationEffect(spin)
                } else {
                    Circle().stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.6),
                                    lineWidth: 3).frame(width: 180, height: 180)
                }
                Circle().fill(LinearGradient(colors: [colors[0], colors[1]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                    .overlay(Image(systemName: icon).font(.system(size: 58, weight: .semibold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                    .frame(width: 136, height: 136)
                    .shadow(color: colors[0].opacity(0.5), radius: 18, y: 6)
                    .scaleEffect(breathe)
            }
        }
        .frame(width: 240, height: 240)
    }
}

struct BigButton: View {
    let title: String, icon: String, colors: [Color], action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.title3.bold()).foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
                .shadow(color: colors[0].opacity(0.5), radius: 12, y: 4)
        }.buttonStyle(.plain)
    }
}

struct ToolView: View {
    @ObservedObject var r: Runner
    let tool: Tool
    var hasResults: Bool { !r.report.sections.isEmpty && !r.running }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Orb(colors: tool.colors, busy: r.running, icon: tool.icon).padding(.top, 24)
                header
                buttons
                if hasResults { results }
                if !r.log.isEmpty { logView }
            }
            .padding(.horizontal, 32).padding(.bottom, 32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("\(tool.runLabel)?", isPresented: $r.confirmClean) {
            Button(tool.runLabel, role: .destructive) { r.run(tool.run!) }
        } message: { Text("This applies everything listed in the scan above.") }
    }

    @ViewBuilder var header: some View {
        VStack(spacing: 6) {
            if r.running {
                Text(r.didRealRun ? "Working…" : "Scanning…").font(.largeTitle.bold())
                Text(r.report.current.isEmpty ? "Getting started" : r.report.current).foregroundStyle(.secondary)
            } else if !r.report.headline.isEmpty {
                Text(r.report.headline)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: tool.colors, startPoint: .leading, endPoint: .trailing))
                Text(r.didRealRun ? "cleaned up 🎉" : "can be freed" + (r.report.subline.isEmpty ? "" : " · \(r.report.subline)"))
                    .font(.title3).foregroundStyle(.secondary)
            } else if hasResults, r.didRealRun {
                Text("All done 🎉").font(.largeTitle.bold())
            } else {
                Text(tool.title).font(.largeTitle.bold())
                Text(tool.blurb).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder var buttons: some View {
        HStack(spacing: 14) {
            if r.running {
                BigButton(title: "Stop", icon: "stop.fill", colors: [.gray, .secondary]) { r.stop() }
            } else if let preview = tool.preview {
                BigButton(title: hasResults ? "Scan Again" : "Scan", icon: "magnifyingglass", colors: tool.colors) { r.run(preview) }
                if tool.run != nil, hasResults, !r.didRealRun {
                    BigButton(title: tool.runLabel, icon: "sparkles", colors: [.red, .pink]) { r.confirmClean = true }
                }
                if tool.run == nil, hasResults {
                    BigButton(title: "Pick Files to Remove", icon: "checklist", colors: [.indigo, .purple]) { Runner.openInTerminal(tool.id) }
                }
            }
        }
        if tool.run == nil, hasResults {
            Text("Mole only lets you choose which ones in its own Terminal picker, so that step opens Terminal.")
                .font(.caption).foregroundStyle(.secondary)
        } else if ["clean", "optimize"].contains(tool.id), !r.running {
            Text("Steps that need your admin password are skipped here. For those, run sudo -v && mo \(tool.id) in Terminal.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    var results: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
            ForEach(r.report.sections) { s in SectionCard(section: s, colors: tool.colors) }
        }
    }

    var logView: some View {
        DisclosureGroup(isExpanded: $r.showLog) {
            Text(r.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        } label: { Text("Show details").foregroundStyle(.secondary) }
    }
}

struct SectionCard: View {
    let section: Section, colors: [Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title).font(.headline)
                Spacer()
                if section.items.isEmpty {
                    Label("Clean", systemImage: "checkmark.seal.fill").font(.caption.bold()).foregroundStyle(.green)
                }
            }
            ForEach(section.items) { i in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(color(i.kind)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i.name).font(.callout)
                        if !i.detail.isEmpty { Text(i.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                    if i.kind == .review { tag("Review", .yellow) }
                    if i.kind == .skipped { tag("Skipped", .gray) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: colors.map { $0.opacity(0.5) },
                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
    func color(_ k: Item.Kind) -> Color { [.found: colors[0], .done: .green, .review: .yellow, .skipped: .gray][k]! }
    func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.2), in: Capsule()).foregroundStyle(c)
    }
}
