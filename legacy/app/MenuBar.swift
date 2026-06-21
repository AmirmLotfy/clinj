// Clinj menu-bar app — a tiny resident NSStatusItem that drives ~/.clinj/bin/clinj.sh.
// Build: swiftc -O MenuBar.swift -o clinj-menubar   (wrapped into a .app by install.sh)

import Cocoa

let clinjHome = ("~/.clinj" as NSString).expandingTildeInPath
let engine = clinjHome + "/bin/clinj.sh"
let scheduleScript = clinjHome + "/bin/schedule.sh"
let confFile = clinjHome + "/etc/clinj.conf"

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let idleTitle = "🧼"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = idleTitle

        let menu = NSMenu()
        add(menu, "Clean Now  (safe)", #selector(cleanNow))
        add(menu, "Deep Clean  (max space)", #selector(deepClean))
        add(menu, "RAM Boost", #selector(ramBoost))
        add(menu, "Preview  (dry run)", #selector(preview))
        menu.addItem(.separator())
        add(menu, "Reclaim Claude VM bundles  (13 GB)…", #selector(reclaimVMs))
        menu.addItem(.separator())

        let sched = NSMenu()
        for (label, arg) in [("Daily", "daily"), ("Every 3 days", "3day"), ("Weekly", "weekly"), ("Off", "off")] {
            let it = NSMenuItem(title: label, action: #selector(setSchedule(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = arg
            sched.addItem(it)
        }
        let schedItem = NSMenuItem(title: "Auto-run schedule", action: nil, keyEquivalent: "")
        schedItem.submenu = sched
        menu.addItem(schedItem)

        add(menu, "Open Settings…", #selector(openSettings))
        menu.addItem(.separator())
        add(menu, "Quit Clinj", #selector(quit))
        statusItem.menu = menu
    }

    func add(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // ── engine helpers ──────────────────────────────────────────────────────
    func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [engine] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        do { try p.run() } catch { return "Error launching engine: \(error.localizedDescription)" }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func memFree() -> Int { Int(run(["--mem"])) ?? 0 }

    func busy(_ on: Bool) { DispatchQueue.main.async { self.statusItem.button?.title = on ? "⏳" : self.idleTitle } }

    func runAsync(_ args: [String], title: String) {
        busy(true)
        DispatchQueue.global().async {
            let out = self.run(args + ["--report"])
            DispatchQueue.main.async { self.busy(false); self.alert(title, out) }
        }
    }

    func alert(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func confirm(_ title: String, _ msg: String, _ okTitle: String) -> Bool {
        let a = NSAlert()
        a.messageText = title; a.informativeText = msg; a.alertStyle = .warning
        a.addButton(withTitle: okTitle); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    // ── actions ───────────────────────────────────────────────────────────────
    @objc func cleanNow() { runAsync([], title: "Clean complete") }

    @objc func deepClean() {
        if confirm("Deep Clean",
                   "Also clears Chrome ML caches, Xcode archives & device support. Apps keep working; some caches re-download as needed.",
                   "Deep Clean") {
            runAsync(["--aggressive"], title: "Deep Clean complete")
        }
    }

    @objc func preview() { runAsync(["--aggressive", "--dry-run"], title: "Preview (nothing deleted)") }

    @objc func reclaimVMs() {
        if confirm("Reclaim Claude VM bundles",
                   "Claude's sandbox VM bundles can use 13 GB+. Removing them is safe — they re-download the next time you use Claude's sandbox. Continue?",
                   "Reclaim") {
            runAsync(["--vm-bundles"], title: "Reclaimed Claude VM bundles")
        }
    }

    @objc func ramBoost() {
        busy(true)
        DispatchQueue.global().async {
            let before = self.memFree()
            let purge = Process()
            purge.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            purge.arguments = ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"]
            var ok = false
            do { try purge.run(); purge.waitUntilExit(); ok = purge.terminationStatus == 0 } catch { ok = false }
            let after = self.memFree()
            DispatchQueue.main.async {
                self.busy(false)
                if !ok { self.alert("RAM Boost", "Cancelled."); return }
                let freed = max(0, after - before)
                self.alert("RAM Boost done",
                           "Free memory: \(before) MB → \(after) MB\nReclaimed ~\(freed) MB\n\n(macOS reclaims memory automatically too, so gains are usually modest.)")
            }
        }
    }

    @objc func setSchedule(_ sender: NSMenuItem) {
        guard let arg = sender.representedObject as? String else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scheduleScript, arg]
        try? p.run(); p.waitUntilExit()
        alert("Schedule updated", "Auto-run set to: \(sender.title)")
    }

    @objc func openSettings() { NSWorkspace.shared.openFile(confFile, withApplication: "TextEdit") }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
