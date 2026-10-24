// globe-switch: tap 🌐 (fn) to cycle keyboard layouts instantly.
//
// Replaces macOS's own Globe handling, which goes through TextInputSwitcher: launchd idle-kills
// that helper a few minutes after each use (the next press is spent relaunching it), and its
// picker HUD swallows keystrokes typed right after switching. Needs "Press 🌐 key to: Do Nothing"
// so the system doesn't toggle too, and Input Monitoring access for this binary.
//
//   globe-switch            run the handler (normally as a LaunchAgent, see install.sh)
//   globe-switch doctor     check the agent, its permission, the 🌐 setting and the layouts
//   globe-switch --list     print the layouts a tap cycles through
//   globe-switch --version
import AppKit
import Carbon
import CoreGraphics
import Foundation
import GlobeSwitchCore
import os

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

switch CommandLine.arguments.dropFirst().first {
case nil:
    break
case "--list":
    for source in keyboardLayouts() { print(sourceID(source) ?? "?") }
    exit(0)
case "--version":
    print(GlobeSwitch.version)
    exit(0)
case "doctor":
    exit(runDoctor())
case "--check-access":
    exit(CGPreflightListenEventAccess() ? 0 : 1)
case let unknown?:
    FileHandle.standardError.write(Data("unknown argument \(unknown); usage: globe-switch [doctor | --list | --version]\n".utf8))
    exit(2)
}

let fnKeyCode: Int64 = 63

var detector = TapDetector()
var tap: CFMachPort?
var lastSwitchAt: UInt64 = 0
var lastSwitchTo: String?
var switches = 0
var bounces = 0

func switchToNextLayout() {
    let layouts = keyboardLayouts()
    let currentID = currentSourceID()
    guard let next = nextLayoutIndex(after: layouts.firstIndex { sourceID($0) == currentID }, count: layouts.count) else {
        return
    }
    switches += 1
    lastSwitchAt = now()
    lastSwitchTo = sourceID(layouts[next])
    let status = TISSelectInputSource(layouts[next])
    if status != noErr {
        log("TISSelectInputSource(\(lastSwitchTo ?? "?")) failed: \(status) \(context())", .error)
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
    let check = Process()
    check.executableURL = Bundle.main.executableURL
    check.arguments = ["--check-access"]
    guard (try? check.run()) != nil else { return false }
    check.waitUntilExit()
    return check.terminationStatus == 0
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
            + "set it to Do Nothing or run install.sh again", .error)
    }
}

// Something else switching the layout right after a tap means macOS is handling 🌐 as well
// (see install.sh); log it so the bounce is visible.
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: nil
) { _ in
    let id = currentSourceID()
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
CFRunLoopRun()
