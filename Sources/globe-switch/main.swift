// globe-switch: tap 🌐 (fn) to cycle keyboard layouts instantly.
//
// Replaces macOS's own Globe handling, which goes through TextInputSwitcher: launchd idle-kills
// that helper a few minutes after each use (the next press is spent relaunching it), and its
// picker HUD swallows keystrokes typed right after switching. Needs "Press 🌐 key to: Do Nothing"
// so the system doesn't toggle too, and Input Monitoring access for GlobeSwitch.app.
import AppKit
import Carbon
import CoreGraphics
import Foundation
import GlobeSwitchCore
import os

let usage = """
    usage: globe-switch <command>
      install     copy GlobeSwitch.app to ~/Applications, start it at login and hand 🌐 to it
      uninstall   remove the LaunchAgent and the app, and give 🌐 back to macOS
      doctor      check the agent, its permissions, the 🌐 setting, layouts and settings
      run         run the agent in this terminal, for debugging
      --list      print the layout IDs a tap cycles through
      --version
    """

let logger = Logger(subsystem: GlobeSwitch.label, category: "agent")
let logToTerminal = isatty(STDERR_FILENO) != 0

/// Goes to the unified log (`/usr/bin/log show --predicate 'subsystem == "dev.yemelianov.globe-switch"'`),
/// which rotates on its own, and to the terminal when run by hand.
func log(_ message: String, _ level: OSLogType = .default) {
    logger.log(level: level, "\(message, privacy: .public)")
    if logToTerminal { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
}

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

func ms(_ nanos: UInt64) -> Int { Int(nanos / 1_000_000) }

func context() -> String {
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    let switcher = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextInputSwitcher")
        .first.map { "\($0.processIdentifier)" } ?? "dead"
    return "front=\(front) TextInputSwitcher=\(switcher)"
}

/// Double-clicking GlobeSwitch.app installs it and shows what the doctor found.
func openedFromFinder() -> Int32 {
    let status = install(runDoctorAfter: false)
    Thread.sleep(forTimeInterval: 1) // let the agent start before asking it for its state
    let diagnosis = diagnose()
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = status == 0 && diagnosis.failures == 0 ? "GlobeSwitch is running" : "GlobeSwitch needs attention"
    alert.informativeText = diagnosis.lines.joined(separator: "\n")
    alert.addButton(withTitle: "OK")
    if diagnosis.needsInputMonitoring {
        alert.addButton(withTitle: "Open Input Monitoring")
    }
    if alert.runModal() == .alertSecondButtonReturn,
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
        NSWorkspace.shared.open(url)
    }
    return status
}

// Run through a symlink (~/.local/bin, Homebrew's bin), Bundle.main is not the app, so install has
// nothing to copy. Start again from the real path inside GlobeSwitch.app.
if Bundle.main.bundleURL.pathExtension != "app", let executable = Bundle.main.executableURL {
    let real = executable.resolvingSymlinksInPath()
    if real != executable, real.deletingLastPathComponent().path.hasSuffix(".app/Contents/MacOS") {
        execv(real.path, CommandLine.unsafeArgv)
    }
}

switch CommandLine.arguments.dropFirst().first {
case nil where ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == GlobeSwitch.label:
    break // started by launchd: run the agent
case nil where isatty(STDIN_FILENO) == 0:
    exit(openedFromFinder())
case "run":
    if let other = requestAgentStatus(timeout: 0.5) {
        printError("the agent is already running (pid \(other.pid)); stop it first: launchctl bootout \(agentJob)")
        exit(1)
    }
case "install":
    exit(install(runDoctorAfter: !CommandLine.arguments.contains("--no-doctor")))
case "uninstall":
    exit(uninstall())
case "doctor":
    exit(runDoctor())
case "--list":
    for source in keyboardLayouts() { print(sourceID(source) ?? "?") }
    exit(0)
case "--version":
    print(GlobeSwitch.version)
    exit(0)
case "--check-access":
    exit(CGPreflightListenEventAccess() ? 0 : 1)
default:
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
    exit(2)
}

// The agent.

let fnKeyCode: Int64 = 63

var settings = readSettings()
var detector = TapDetector(maxTapNanos: settings.tapWindowNanos)
var tap: CFMachPort?
var lastSwitchAt: UInt64 = 0
var lastSwitchTo: String?
var switches = 0
var bounces = 0
/// Layouts in the order they were last used, most recent first, for `CycleOrder=recent`.
var recentLayouts = [currentSourceID()]

func switchToNextLayout() {
    let layouts = keyboardLayouts()
    let ids = layouts.map { sourceID($0) ?? "" }
    let currentID = currentSourceID()
    guard let nextID = nextLayout(current: currentID, enabled: ids,
                                  skipped: settings.skippedLayouts, recent: recentLayouts, order: settings.cycleOrder),
          let next = layouts.first(where: { sourceID($0) == nextID }) else {
        return
    }
    switches += 1
    lastSwitchAt = now()
    lastSwitchTo = nextID
    let status = TISSelectInputSource(next)
    guard status == noErr else {
        log("TISSelectInputSource(\(nextID)) failed: \(status) \(context())", .error)
        return
    }
    if settings.showIndicator {
        let shownIDs = indicatorLayouts(enabled: ids, skipped: settings.skippedLayouts, keeping: [currentID, nextID])
        let items = zip(ids, layouts).filter { shownIDs.contains($0.0) }.map { id, source in
            let shown = flagAndName(source, overrides: settings.layoutFlags)
            return Indicator.Item(id: id, flag: shown.flag, name: shown.name)
        }
        Indicator.show(items, from: currentID, to: nextID)
    }
    if settings.playSound {
        SwitchSound.play(settings.sound, volume: settings.soundVolume)
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        // Events were missed while the tap was off, so a press in progress can't be trusted.
        detector.reset()
        log("event tap re-enabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input"))")
    case .flagsChanged where event.getIntegerValueField(.keyboardEventKeycode) == fnKeyCode:
        let pressed = event.flags.contains(.maskSecondaryFn)
        if pressed {
            // Pick up `defaults write` changes before this press is judged.
            settings = readSettings()
            detector.maxTapNanos = settings.tapWindowNanos
        }
        switch detector.handle(pressed ? .fnDown(at: now()) : .fnUp(at: now())) {
        case .tap: switchToNextLayout()
        case .heldTooLong(let nanos): log("fn held \(ms(nanos))ms, too long for a tap")
        case .none: break
        }
    default:
        // Any key, other modifier, media key, click or scroll while fn is held makes it a chord (fn+←, fn+E, …).
        _ = detector.handle(.other)
    }
    return Unmanaged.passUnretained(event)
}

func installTap() -> Bool {
    let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    var mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    mask |= 1 << 14 // NX_SYSDEFINED: brightness / volume / media keys
    // Listen-only: a stuck handler can never block typing.
    guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                       options: .listenOnly, eventsOfInterest: mask,
                                       callback: callback, userInfo: nil) else {
        return false
    }
    tap = port
    CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    return true
}

/// macOS caches the Input Monitoring answer for the life of a process, so ask a fresh copy of ourselves.
func listenAccessGranted() -> Bool {
    guard let executable = Bundle.main.executableURL else { return false }
    return run(executable, ["--check-access"], quiet: true) == 0
}

var fnUsageAtLastCheck: Int? = FnUsage.doNothing.rawValue

/// Runs at start and every 30 s. A revoked Input Monitoring grant leaves the tap silently deaf,
/// so restart into the waiting state; 🌐 handed back to macOS makes taps bounce, so say so once.
func healthCheck() {
    if let tap {
        guard listenAccessGranted() else {
            log("Input Monitoring access was revoked, restarting to wait for it", .error)
            exit(0)
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            detector.reset()
            log("event tap was off, re-enabled")
        }
    }
    let fnUsage = fnUsageSetting()
    guard fnUsage != fnUsageAtLastCheck else { return }
    fnUsageAtLastCheck = fnUsage
    if fnUsage == FnUsage.doNothing.rawValue {
        log("🌐 is set to Do Nothing again")
    } else {
        log("🌐 is set to \(FnUsage.describe(fnUsage)), so macOS reacts to taps too and they may bounce; "
            + "set it to Do Nothing or run globe-switch install again", .error)
    }
}

// Every layout change, whoever makes it, feeds the recent list. Something else switching right after
// a tap means macOS is handling 🌐 as well (see restartInputAgents); log it so the bounce is visible.
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: nil
) { _ in
    let id = currentSourceID()
    recentLayouts.removeAll { $0 == id }
    recentLayouts.insert(id, at: 0)
    if recentLayouts.count > 10 { recentLayouts.removeLast() }

    let since = now() - lastSwitchAt
    guard since < 1_000_000_000, id != lastSwitchTo else { return }
    bounces += 1
    log("bounced to \(id) \(ms(since))ms after a tap to \(lastSwitchTo ?? "?"), \(context())", .error)
}

DistributedNotificationCenter.default().addObserver(forName: statusRequest, object: nil, queue: nil) { _ in
    let status = AgentStatus(
        pid: getpid(), version: GlobeSwitch.version,
        listening: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
        switches: switches, bounces: bounces,
        secondsSinceSwitch: lastSwitchAt == 0 ? nil : Int((now() - lastSwitchAt) / 1_000_000_000))
    DistributedNotificationCenter.default().postNotificationName(
        statusReply, object: status.json, userInfo: nil, deliverImmediately: true)
}

// An accessory app (no Dock icon, never activated), so the indicator panel can be shown.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Without Input Monitoring access the tap is still created but never sees key events,
// so wait for the grant before installing it.
if CGPreflightListenEventAccess() && installTap() {
    log("started \(GlobeSwitch.version), cycling \(keyboardLayouts().compactMap(sourceID))")
} else {
    CGRequestListenEventAccess()
    log("waiting for Input Monitoring access (System Settings → Privacy & Security → Input Monitoring)", .error)
    // This process will keep seeing "denied" even after the grant; exit and let launchd's
    // KeepAlive start a fresh one that sees it.
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        guard listenAccessGranted() else { return }
        log("Input Monitoring access granted, restarting")
        exit(0)
    }
}
healthCheck()
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in healthCheck() }
app.run()
