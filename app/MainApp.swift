// Clinj — SwiftUI front-end over the clinj engine (core/clinj.sh).
// Build with app/build-app.sh (swiftc + bundle). macOS 13+.
import SwiftUI

// MARK: - Model

struct CatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let category: String
    let safe: String
    let mode: String
    let size_kb: Int
    let regen: String
    let label: String
    let path: String
}

enum Engine {
    static var script: String {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("core/clinj.sh").path,
           FileManager.default.fileExists(atPath: res) { return res }
        // dev fallback when run unbundled
        return (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/Clinj/core/clinj.sh")
    }

    @discardableResult
    static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return "launch error: \(error.localizedDescription)" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // parse one TSV catalog line: id\tcategory\tsafe\tmode\tregen\tsize_kb\tlabel\tpath
    static func parseTSV(_ line: String) -> CatalogItem? {
        let f = line.components(separatedBy: "\t")
        guard f.count == 8, let kb = Int(f[5]) else { return nil }
        return CatalogItem(id: f[0], category: f[1], safe: f[2], mode: f[3],
                           size_kb: kb, regen: f[4], label: f[6], path: f[7])
    }
}

// Accumulates pipe data and yields complete newline-terminated lines.
final class LineBox {
    private var buf = Data()
    func feed(_ d: Data) -> [String] {
        buf.append(d)
        var out: [String] = []
        while let nl = buf.firstIndex(of: 0x0A) {
            let lineData = buf.subdata(in: buf.startIndex..<nl)
            buf.removeSubrange(buf.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8), !s.isEmpty { out.append(s) }
        }
        return out
    }
}

let PROFILES: [(id: String, name: String, cats: Set<String>, aggressive: Bool)] = [
    ("minimal",   "Minimal",   ["trash", "system"], false),
    ("general",   "General",   ["browsers", "apps", "system", "trash"], false),
    ("designer",  "Designer",  ["browsers", "apps", "system", "trash", "dev-mobile"], false),
    ("developer", "Developer", ["dev-js", "dev-py", "dev-native", "dev-mobile", "containers", "browsers", "apps", "system", "trash"], true),
]

func humanKB(_ kb: Int) -> String {
    var v = Double(kb); let u = ["KB", "MB", "GB", "TB"]; var i = 0
    while v >= 1024 && i < 3 { v /= 1024; i += 1 }
    return (v >= 10 || v == v.rounded()) ? String(format: "%.0f %@", v, u[i]) : String(format: "%.1f %@", v, u[i])
}

@MainActor final class Model: ObservableObject {
    @Published var profileIndex = 3            // Developer
    @Published var items: [CatalogItem] = []
    @Published var selected = Set<String>()
    @Published var includeReview = false
    @Published var scanning = false
    @Published var busy = false
    @Published var resultText: String?
    @Published var didScan = false
    @Published var foundKB = 0
    @Published var currentLabel = ""

    var profile: (id: String, name: String, cats: Set<String>, aggressive: Bool) { PROFILES[profileIndex] }
    var categories: [String] {
        Array(Set(items.map { $0.category })).sorted { catRank($0) < catRank($1) }
    }
    func items(in cat: String) -> [CatalogItem] { items.filter { $0.category == cat } }
    var selectedKB: Int { items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size_kb } }
    var totalKB: Int { items.reduce(0) { $0 + $1.size_kb } }

    func catRank(_ c: String) -> Int {
        ["dev-js", "dev-py", "dev-native", "dev-mobile", "containers", "browsers", "apps", "system", "trash"]
            .firstIndex(of: c) ?? 99
    }

    func defaultSelected() -> Set<String> {
        var s = Set<String>()
        for it in items {
            guard profile.cats.contains(it.category) else { continue }
            switch it.safe {
            case "safe": s.insert(it.id)
            case "aggressive": if profile.aggressive { s.insert(it.id) }
            case "review": if includeReview { s.insert(it.id) }
            default: break
            }
        }
        return s
    }

    func scan() {
        scanning = true; didScan = false; resultText = nil
        items = []; foundKB = 0; currentLabel = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Engine.script, "scan", "--stream"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        let handle = pipe.fileHandleForReading
        let box = LineBox()
        handle.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            for line in box.feed(d) {
                if let item = Engine.parseTSV(line) { Task { @MainActor in self.append(item) } }
            }
        }
        p.terminationHandler = { _ in
            handle.readabilityHandler = nil
            Task { @MainActor in self.finishScan() }
        }
        do { try p.run() } catch { scanning = false; resultText = "Scan failed to launch." }
    }

    func append(_ it: CatalogItem) { items.append(it); foundKB += it.size_kb; currentLabel = it.label }

    func finishScan() {
        items.sort { $0.size_kb > $1.size_kb }
        selected = defaultSelected()
        scanning = false; didScan = true; currentLabel = ""
    }

    func clean(dryRun: Bool) {
        guard !selected.isEmpty else { resultText = "Nothing selected."; return }
        busy = true
        let ids = selected.joined(separator: ",")
        let args = ["clean", "--ids", ids] + (dryRun ? ["--dry-run"] : [])
        Task {
            let out = await Task.detached { Engine.run(args) }.value
            let summary = out.split(separator: "\n").last.map(String.init) ?? out
            self.resultText = (dryRun ? "Preview — " : "") + summary.trimmingCharacters(in: .whitespaces)
            self.busy = false
            if !dryRun { self.scan() }   // refresh sizes
        }
    }

    func restore() {
        busy = true
        Task {
            let out = await Task.detached { Engine.run(["restore"]) }.value
            self.resultText = out.trimmingCharacters(in: .whitespacesAndNewlines)
            self.busy = false
        }
    }

    func toggleCategory(_ cat: String, on: Bool) {
        for it in items(in: cat) { if on { selected.insert(it.id) } else { selected.remove(it.id) } }
    }
}

// MARK: - Views

struct ScanningView: View {
    let count: Int; let kb: Int; let current: String
    @State private var spin = false
    @State private var pulse = false
    @State private var phase = 0
    private let phases = ["Scanning caches…", "Detecting apps & browsers…",
                          "Measuring sizes…", "Classifying what's safe…"]
    private let timer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()
    private let accent = LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 9)
                Circle().trim(from: 0, to: 0.22)
                    .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "sparkles").font(.system(size: 36))
                    .foregroundStyle(accent)
                    .scaleEffect(pulse ? 1.12 : 0.9)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            }
            .frame(width: 120, height: 120)

            Text(phases[phase]).font(.headline).transition(.opacity)
            Text("\(count) items · \(humanKB(kb)) found")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(current.isEmpty ? " " : current)
                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                .frame(maxWidth: 400).truncationMode(.middle)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { spin = true; pulse = true }
        .onReceive(timer) { _ in withAnimation { phase = (phase + 1) % phases.count } }
    }
}

struct SafeTag: View {
    let safe: String
    var body: some View {
        let (txt, col): (String, Color) = safe == "review" ? ("review", .orange)
            : safe == "aggressive" ? ("aggressive", .yellow) : ("safe", .green)
        Text(txt).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(col.opacity(0.18)).foregroundColor(col).clipShape(Capsule())
    }
}

struct ContentView: View {
    @StateObject var m = Model()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if m.scanning {
                ScanningView(count: m.items.count, kb: m.foundKB, current: m.currentLabel)
            } else if !m.didScan {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { if !m.didScan { m.scan() } }
    }

    var header: some View {
        HStack(spacing: 12) {
            Text("🧼 Clinj").font(.title2.bold())
            Picker("", selection: $m.profileIndex) {
                ForEach(PROFILES.indices, id: \.self) { i in Text(PROFILES[i].name).tag(i) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 320)
            .onChange(of: m.profileIndex) { _ in m.selected = m.defaultSelected() }
            Spacer()
            Toggle("Unknown", isOn: $m.includeReview)
                .toggleStyle(.checkbox)
                .onChange(of: m.includeReview) { _ in m.selected = m.defaultSelected() }
                .help("Include unrecognized caches (cleaned to a recoverable quarantine)")
            Button { m.scan() } label: { Image(systemName: "arrow.clockwise") }.help("Rescan")
        }.padding(12)
    }

    var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Press Scan to see what's reclaimable.").foregroundColor(.secondary)
            Button("Scan") { m.scan() }.keyboardShortcut(.defaultAction)
            Spacer()
        }
    }

    var list: some View {
        List {
            ForEach(m.categories, id: \.self) { cat in
                let rows = m.items(in: cat)
                let catKB = rows.reduce(0) { $0 + $1.size_kb }
                let allOn = rows.allSatisfy { m.selected.contains($0.id) }
                Section {
                    ForEach(rows) { it in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { m.selected.contains(it.id) },
                                set: { v in if v { m.selected.insert(it.id) } else { m.selected.remove(it.id) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(it.label)
                                Text(it.regen).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            SafeTag(safe: it.safe)
                            Text(humanKB(it.size_kb)).monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                    }
                } header: {
                    HStack {
                        Toggle(isOn: Binding(get: { allOn }, set: { m.toggleCategory(cat, on: $0) })) {
                            Text(cat.uppercased()).font(.caption.bold())
                        }.toggleStyle(.checkbox)
                        Spacer()
                        Text(humanKB(catKB)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }.listStyle(.inset)
    }

    var footer: some View {
        VStack(spacing: 6) {
            if let r = m.resultText {
                Text(r).font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            }
            HStack {
                Text("Selected: \(humanKB(m.selectedKB))  of  \(humanKB(m.totalKB))").font(.callout)
                Spacer()
                Button("Restore last") { m.restore() }.disabled(m.busy)
                Button("Preview") { m.clean(dryRun: true) }.disabled(m.busy || m.selected.isEmpty)
                Button("Clean Selected") { m.clean(dryRun: false) }
                    .keyboardShortcut(.defaultAction).disabled(m.busy || m.selected.isEmpty)
            }.padding(12)
        }
    }
}

// MARK: - App

@main
struct ClinjApp: App {
    var body: some Scene {
        WindowGroup("Clinj") { ContentView() }
            .windowResizability(.contentSize)
        MenuBarExtra("Clinj", systemImage: "sparkles") {
            Button("Open Clinj") {
                NSApp.activate(ignoringOtherApps: true)
                for w in NSApp.windows { w.makeKeyAndOrderFront(nil) }
            }
            Divider()
            Button("Quick Clean (Developer, safe)") {
                _ = Engine.run(["clean", "--profile", "developer"])
            }
            Button("Scan in Terminal output") { _ = Engine.run(["scan"]) }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
