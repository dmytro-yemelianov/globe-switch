import AppKit
import GlobeSwitchCore
import Security

/// What `globe-switch doctor` found.
struct Diagnosis {
    var lines: [String] = []
    var failures = 0
    var needsInputMonitoring = false

    /// `mark` is ✓ for fine, ! for a warning and ✗ for something that keeps 🌐 from working.
    mutating func report(_ mark: String, _ name: String, _ detail: String, fix: String? = nil) {
        lines.append("\(mark) \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(detail)")
        if let fix { lines.append("             → \(fix)") }
        if mark == "✗" { failures += 1 }
    }
}

/// `globe-switch doctor`: checks everything a working 🌐 tap needs and says how to fix what isn't.
/// Exits 1 when something is broken.
func runDoctor() -> Int32 {
    let diagnosis = diagnose()
    print("globe-switch \(GlobeSwitch.version)")
    diagnosis.lines.forEach { print($0) }
    let failures = diagnosis.failures
    print(failures == 0 ? "\nAll good." : "\n\(failures) problem\(failures == 1 ? "" : "s") found.")
    print("Agent log: /usr/bin/log show --last 1d --predicate 'subsystem == \"\(GlobeSwitch.label)\"'")
    return failures == 0 ? 0 : 1
}

func diagnose() -> Diagnosis {
    var result = Diagnosis()
    let settings = readSettings()

    let status = requestAgentStatus(timeout: 1.5)
    if let status {
        if status.listening {
            result.report("✓", "agent", "running (pid \(status.pid)), listening for 🌐 taps")
        } else {
            result.needsInputMonitoring = true
            result.report("✗", "agent", "running (pid \(status.pid)), but has no Input Monitoring access",
                          fix: "System Settings → Privacy & Security → Input Monitoring: turn on GlobeSwitch. "
                              + "If it is already on, remove it with − and run globe-switch install again")
        }
        if status.version != GlobeSwitch.version {
            result.report("!", "version", "the agent runs \(status.version), this binary is \(GlobeSwitch.version)",
                          fix: "run globe-switch install to update the agent")
        }
    } else if FileManager.default.fileExists(atPath: agentPlist.path) {
        result.report("✗", "agent", "installed but not answering",
                      fix: "launchctl kickstart -k \(agentJob), then run doctor again")
    } else {
        result.report("✗", "agent", "not installed", fix: "run globe-switch install")
    }

    if let program = agentProgram {
        if agentDisabled {
            result.report("✗", "login", "GlobeSwitch is turned off in Login Items",
                          fix: "turn it on in System Settings → General → Login Items & Extensions, "
                              + "then run globe-switch install")
        } else if program != installedExecutable.path {
            result.report("!", "login", "the LaunchAgent starts \(program)",
                          fix: "run globe-switch install to start \(installedExecutable.path) instead")
        } else if !agentJobLoaded {
            result.report("✗", "login", "the LaunchAgent is not loaded", fix: "run globe-switch install")
        } else {
            result.report("✓", "login", "starts at login (\(agentPlist.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")))")
        }
    }

    let signedApp = FileManager.default.fileExists(atPath: installedApp.path) ? installedApp : Bundle.main.bundleURL
    if let signer = signer(of: signedApp) {
        result.report("✓", "signature", "\(signer), so Input Monitoring stays granted across updates")
    } else {
        result.report("!", "signature", "ad-hoc, so Input Monitoring has to be granted again after each update",
                      fix: "install with an Apple Development identity to keep the grant (see README)")
    }

    let fnUsage = fnUsageSetting()
    if fnUsage == FnUsage.doNothing.rawValue {
        result.report("✓", "globe key", "Press 🌐 key to: Do Nothing (globe-switch handles it)")
    } else {
        result.report("✗", "globe key", "Press 🌐 key to: \(FnUsage.describe(fnUsage)), so macOS reacts to taps too",
                      fix: "run globe-switch install; it sets Do Nothing and restarts macOS's input agents")
    }

    let layouts = keyboardLayouts()
    let ids = layouts.compactMap(sourceID)
    let switchable = layouts.filter { !settings.skippedLayouts.contains(sourceID($0) ?? "") }
    let names = switchable.map { source -> String in
        let shown = flagAndName(source, overrides: settings.layoutFlags)
        return [shown.flag, shown.name].compactMap { $0 }.joined(separator: " ")
    }
    if switchable.count > 1 {
        result.report("✓", "layouts", names.joined(separator: " → "))
    } else {
        result.report("✗", "layouts", names.first.map { "only \($0) to switch to" } ?? "none",
                      fix: "add a second layout in System Settings → Keyboard → Text Input, or skip fewer")
    }

    if settings.changes.isEmpty {
        result.report("✓", "settings", "defaults")
    } else {
        result.report("✓", "settings", settings.changes.joined(separator: ", "))
    }
    if settings.playSound && NSSound(named: NSSound.Name(settings.sound)) == nil {
        result.report("!", "settings", "Sound \(settings.sound) was not found, so switches are silent",
                      fix: "use Click, or a name from /System/Library/Sounds or ~/Library/Sounds, such as Tink or Pop")
    }
    let unknown = settings.skippedLayouts.subtracting(ids).sorted()
    if !unknown.isEmpty {
        result.report("!", "settings", "SkippedLayouts names layouts that aren't enabled: \(unknown.joined(separator: ", "))",
                      fix: "globe-switch --list prints the IDs to use")
    }

    if let status {
        let last = status.secondsSinceSwitch.map { "last one \(duration($0)) ago" } ?? "none yet"
        result.report(status.bounces == 0 ? "✓" : "!", "activity",
                      "\(status.switches) switches since the agent started (\(last)), \(status.bounces) bounced back",
                      fix: status.bounces == 0 ? nil : "something else switched right after a tap; if 🌐 is set to "
                          + "Do Nothing, run globe-switch install to restart macOS's input agents")
    }
    return result
}

/// Asks a running agent for its state; nil when none answers in time.
func requestAgentStatus(timeout: TimeInterval) -> AgentStatus? {
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

/// The certificate that signed the code at `url`, or nil when it is ad-hoc signed or unsigned.
/// Input Monitoring remembers the signature, and only a certificate stays the same across builds.
private func signer(of url: URL) -> String? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certificates.first else {
        return nil
    }
    return SecCertificateCopySubjectSummary(leaf) as String?
}

private func duration(_ seconds: Int) -> String {
    switch seconds {
    case ..<60: return "\(seconds) s"
    case ..<3600: return "\(seconds / 60) min"
    default: return "\(seconds / 3600) h"
    }
}
