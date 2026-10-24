import Foundation
import GlobeSwitchCore

/// `globe-switch doctor`: checks everything a working 🌐 tap needs and says how to fix what isn't.
/// Exits 1 when something is broken.
func runDoctor() -> Int32 {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let plist = "\(home)/Library/LaunchAgents/\(GlobeSwitch.label).plist"
    let installed = "\(home)/.local/bin/globe-switch"
    let job = "gui/\(getuid())/\(GlobeSwitch.label)"
    var failures = 0

    func report(_ mark: String, _ name: String, _ detail: String, fix: String? = nil) {
        print("\(mark) \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(detail)")
        if let fix { print("             → \(fix)") }
        if mark == "✗" { failures += 1 }
    }

    print("globe-switch \(GlobeSwitch.version)")

    if let status = requestAgentStatus(timeout: 1.5) {
        if status.listening {
            report("✓", "agent", "running (pid \(status.pid)), listening for 🌐 taps")
        } else {
            report("✗", "agent", "running (pid \(status.pid)), but has no Input Monitoring access",
                   fix: "System Settings → Privacy & Security → Input Monitoring: allow globe-switch. "
                       + "If it is already on, remove it with − and add \(installed) again with +")
        }
        if status.version != GlobeSwitch.version {
            report("!", "version", "the agent runs \(status.version), this binary is \(GlobeSwitch.version)",
                   fix: "run ./install.sh to update the agent")
        }
        let last = status.secondsSinceSwitch.map { "last one \(duration($0)) ago" } ?? "none yet"
        report(status.bounces == 0 ? "✓" : "!", "activity",
               "\(status.switches) switches since the agent started (\(last)), \(status.bounces) bounced back",
               fix: status.bounces == 0 ? nil : "something else switched right after a tap; if 🌐 is set to Do Nothing, "
                   + "run ./install.sh to restart macOS's input agents")
    } else if !FileManager.default.fileExists(atPath: plist) {
        report("✗", "agent", "not installed", fix: "run ./install.sh")
    } else if launchctl(["print", job]) {
        report("✗", "agent", "loaded but not answering", fix: "launchctl kickstart -k \(job), then run doctor again")
    } else {
        report("✗", "agent", "installed but not loaded", fix: "launchctl bootstrap gui/\(getuid()) \(plist)")
    }

    let fnUsage = fnUsageSetting()
    if fnUsage == FnUsage.doNothing.rawValue {
        report("✓", "globe key", "Press 🌐 key to: Do Nothing (globe-switch handles it)")
    } else {
        report("✗", "globe key", "Press 🌐 key to: \(FnUsage.describe(fnUsage)), so macOS reacts to taps too",
               fix: "run ./install.sh; it sets Do Nothing and restarts macOS's input agents")
    }

    let layouts = keyboardLayouts().map { localizedName($0) ?? sourceID($0) ?? "?" }
    if layouts.count > 1 {
        report("✓", "layouts", layouts.joined(separator: " → "))
    } else {
        report("✗", "layouts", layouts.first.map { "only \($0)" } ?? "none",
               fix: "add a second layout in System Settings → Keyboard → Text Input")
    }

    print(failures == 0 ? "\nAll good." : "\n\(failures) problem\(failures == 1 ? "" : "s") found.")
    print("Agent log: /usr/bin/log show --last 1d --predicate 'subsystem == \"\(GlobeSwitch.label)\"'")
    return failures == 0 ? 0 : 1
}

private func requestAgentStatus(timeout: TimeInterval) -> AgentStatus? {
    let center = DistributedNotificationCenter.default()
    var reply: AgentStatus?
    let observer = center.addObserver(forName: statusReply, object: nil, queue: nil) { note in
        reply = (note.object as? String).flatMap(AgentStatus.init(json:))
    }
    defer { center.removeObserver(observer) }
    center.postNotificationName(statusRequest, object: nil, userInfo: nil, deliverImmediately: true)
    let deadline = Date(timeIntervalSinceNow: timeout)
    while reply == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: min(deadline, Date(timeIntervalSinceNow: 0.05)))
    }
    return reply
}

/// Runs launchctl quietly and says whether it succeeded.
private func launchctl(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func duration(_ seconds: Int) -> String {
    switch seconds {
    case ..<60: return "\(seconds) s"
    case ..<3600: return "\(seconds / 60) min"
    default: return "\(seconds / 3600) h"
    }
}
