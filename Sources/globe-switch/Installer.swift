import AppKit
import Foundation
import GlobeSwitchCore

private let home = FileManager.default.homeDirectoryForCurrentUser
let installedApp = home.appendingPathComponent("Applications/GlobeSwitch.app")
let installedExecutable = installedApp.appendingPathComponent("Contents/MacOS/globe-switch")
let agentPlist = home.appendingPathComponent("Library/LaunchAgents/\(GlobeSwitch.label).plist")
let agentJob = "gui/\(getuid())/\(GlobeSwitch.label)"
/// Before 0.3 the LaunchAgent ran a bare binary from here, and the agent logged to a file.
private let legacyBinary = home.appendingPathComponent(".local/bin/globe-switch")
private let legacyLog = home.appendingPathComponent("Library/Logs/globe-switch.log")
private let launchctl = URL(fileURLWithPath: "/bin/launchctl")

/// True when this process runs from a GlobeSwitch.app bundle, which install copies.
var runningFromApp: Bool {
    Bundle.main.bundleIdentifier == GlobeSwitch.label && Bundle.main.bundleURL.pathExtension == "app"
}

/// The program the installed LaunchAgent starts, if there is one.
var agentProgram: String? {
    (NSDictionary(contentsOf: agentPlist)?["ProgramArguments"] as? [String])?.first
}

/// Whether launchd has the agent's job loaded.
var agentJobLoaded: Bool {
    run(launchctl, ["print", agentJob], quiet: true) == 0
}

/// Whether the agent was turned off in Login Items & Extensions.
var agentDisabled: Bool {
    let disabled = output(of: launchctl, ["print-disabled", "gui/\(getuid())"])
    return disabled.contains("\"\(GlobeSwitch.label)\" => disabled") || disabled.contains("\"\(GlobeSwitch.label)\" => true")
}

/// `globe-switch install`: puts GlobeSwitch.app in ~/Applications, starts its agent at login, hands
/// 🌐 over to it and runs the doctor. Run it again after an update.
func install(runDoctorAfter: Bool = true) -> Int32 {
    guard runningFromApp else {
        printError("install has to run from GlobeSwitch.app; build it with ./install.sh or scripts/build-app.sh")
        return 1
    }
    let source = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    if source != installedApp.resolvingSymlinksInPath().standardizedFileURL {
        do {
            try copyApp(from: source, to: installedApp)
        } catch {
            printError("could not copy GlobeSwitch.app to \(installedApp.path): \(error.localizedDescription)")
            return 1
        }
        print("copied GlobeSwitch.app to \(installedApp.path)")
    }

    let earlierInstall = FileManager.default.fileExists(atPath: agentPlist.path)
    rememberFnUsage(afterEarlierInstall: earlierInstall)
    setFnUsageSetting(FnUsage.doNothing.rawValue)
    restartInputAgents()

    do {
        try writeAgentPlist()
    } catch {
        printError("could not write \(agentPlist.path): \(error.localizedDescription)")
        return 1
    }
    // Replaces a running agent, including one from before 0.3 that ran ~/.local/bin/globe-switch.
    _ = run(launchctl, ["bootout", agentJob], quiet: true)
    _ = run(launchctl, ["enable", agentJob], quiet: true)
    if run(launchctl, ["bootstrap", "gui/\(getuid())", agentPlist.path], quiet: true) != 0 && !agentJobLoaded {
        printError("launchctl could not load \(agentPlist.path); if GlobeSwitch is off in System Settings → "
            + "General → Login Items & Extensions, turn it on and run install again")
    }
    removeLegacyFiles()
    print("installed \(installedApp.path), started by \(agentPlist.path)")
    guard runDoctorAfter else { return 0 }
    print()
    Thread.sleep(forTimeInterval: 1) // let the agent start before asking it for its state
    return runDoctor()
}

/// `globe-switch uninstall`: stops the agent, removes it and ~/Applications/GlobeSwitch.app, and
/// gives 🌐 back to macOS as it was before the first install.
func uninstall() -> Int32 {
    _ = run(launchctl, ["bootout", agentJob], quiet: true)
    let fm = FileManager.default
    try? fm.removeItem(at: agentPlist)
    removeLegacyFiles()

    let previous = PreviousFnUsage.load() ?? .value(FnUsage.changeInputSource.rawValue)
    switch previous {
    case .value(let value): setFnUsageSetting(value)
    case .unset: setFnUsageSetting(nil)
    }
    PreviousFnUsage.forget()
    restartInputAgents()

    if let link = try? fm.destinationOfSymbolicLink(atPath: legacyBinary.path), link.hasPrefix(installedApp.path) {
        try? fm.removeItem(at: legacyBinary)
    }
    try? fm.removeItem(at: installedApp)
    switch previous {
    case .value(let value): print("🌐 is back to \(FnUsage.describe(value))")
    case .unset: print("🌐 is back to the macOS default")
    }
    print("uninstalled GlobeSwitch")
    return 0
}

/// The LaunchAgent starts the installed app's executable by its absolute path. SMAppService's
/// BundleProgram was tried first and dropped: launchd found the program through LaunchServices by
/// bundle ID, which picked whichever copy of GlobeSwitch.app was registered (a Homebrew build, a
/// deleted one) and then failed to restart the agent. AssociatedBundleIdentifiers still shows the
/// agent as GlobeSwitch, with its icon, in Login Items & Extensions.
private func writeAgentPlist() throws {
    let agent: [String: Any] = [
        "Label": GlobeSwitch.label,
        "ProgramArguments": [installedExecutable.path],
        "AssociatedBundleIdentifiers": [GlobeSwitch.label],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Interactive",
        "LimitLoadToSessionType": "Aqua",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
    try FileManager.default.createDirectory(at: agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: agentPlist, options: .atomic)
}

/// Copies the app next to the target and swaps it in, rather than writing over the files: macOS
/// caches code signatures per file, and the running agent keeps the old executable until it restarts.
private func copyApp(from source: URL, to target: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = target.deletingLastPathComponent().appendingPathComponent(".GlobeSwitch.app.new")
    try? fm.removeItem(at: staging)
    try fm.copyItem(at: source, to: staging)
    if fm.fileExists(atPath: target.path) {
        _ = try fm.replaceItemAt(target, withItemAt: staging)
    } else {
        try fm.moveItem(at: staging, to: target)
    }
}

/// Removes the bare binary and the log file of an install from before 0.3; a symlink to the app,
/// which install.sh makes, stays.
private func removeLegacyFiles() {
    let fm = FileManager.default
    try? fm.removeItem(at: legacyLog)
    guard fm.fileExists(atPath: legacyBinary.path),
          (try? fm.destinationOfSymbolicLink(atPath: legacyBinary.path)) == nil else { return }
    try? fm.removeItem(at: legacyBinary)
    print("removed \(legacyBinary.path) from before 0.3; in Input Monitoring, remove its globe-switch entry with −")
}

/// Records what 🌐 did before the first install. An earlier install already set Do Nothing; 0.1
/// didn't record the value it replaced, so uninstall then falls back to Change Input Source.
private func rememberFnUsage(afterEarlierInstall: Bool) {
    guard PreviousFnUsage.load() == nil else { return }
    switch fnUsageSetting() {
    case nil: PreviousFnUsage.unset.save()
    case .some(FnUsage.doNothing.rawValue) where afterEarlierInstall: break
    case let value?: PreviousFnUsage.value(value).save()
    }
}

/// TextInputMenuAgent and TextInputSwitcher read "Press 🌐 key to" once at launch; until they
/// restart, macOS keeps switching on 🌐 too and races the agent. launchd relaunches both on demand.
func restartInputAgents() {
    // TextInputSwitcher ignores SIGTERM.
    for (bundleID, signal) in [("com.apple.TextInputSwitcher", SIGKILL), ("com.apple.TextInputMenuAgent", SIGTERM)] {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            kill(app.processIdentifier, signal)
        }
    }
}

/// Runs a program and waits for it. Its output goes to ours unless `quiet`.
func run(_ executable: URL, _ arguments: [String], quiet: Bool = false) -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if quiet {
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    guard (try? process.run()) != nil else { return 127 }
    process.waitUntilExit()
    return process.terminationStatus
}

/// Runs a program and returns what it printed; empty if it could not run.
func output(of executable: URL, _ arguments: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("globe-switch: \(message)\n".utf8))
}
