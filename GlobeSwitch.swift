// globe-switch: tap 🌐 (fn) to cycle keyboard layouts instantly.
//
// Replaces macOS's own Globe handling, which goes through TextInputSwitcher: launchd idle-kills
// that helper a few minutes after each use (the next press is spent relaunching it), and its
// picker HUD swallows keystrokes typed right after switching. Needs "Press 🌐 key to: Do Nothing"
// so the system doesn't toggle too, and Input Monitoring access for this binary.
//
//   globe-switch          run the handler (normally as a LaunchAgent, see install.sh)
//   globe-switch --list   print the layouts a tap cycles through
import AppKit
import Carbon
import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

/// fn released within this window, with nothing else pressed while it was held, counts as a tap.
let maxTapNanos: UInt64 = 600_000_000
let fnKeyCode: Int64 = 63

var fnDown = false
var fnDownAt: UInt64 = 0
var chorded = false
var tap: CFMachPort?
var lastSwitchAt: UInt64 = 0
var lastSwitchTo: String?

let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func log(_ message: String) {
    print("\(timestampFormatter.string(from: Date())) \(message)")
}

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

func ms(_ nanos: UInt64) -> Int { Int(nanos / 1_000_000) }

func context() -> String {
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    let switcher = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextInputSwitcher")
        .first.map { "\($0.processIdentifier)" } ?? "dead"
    return "front=\(front) TextInputSwitcher=\(switcher)"
}

func currentSourceID() -> String {
    sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) ?? "?"
}

func sourceID(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func sourceType(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

/// Enabled, selectable keyboard layouts and input modes — no emoji palette, dictation or press-and-hold.
func keyboardLayouts() -> [TISInputSource] {
    let filter: [String: Any] = [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
        kTISPropertyInputSourceIsSelectCapable as String: true,
    ]
    let typing: Set<String> = [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String]
    guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return list.filter { sourceType($0).map(typing.contains) ?? false }
}

func switchToNextLayout() {
    let layouts = keyboardLayouts()
    guard layouts.count > 1 else { return }
    let currentID = currentSourceID()
    let index = layouts.firstIndex { sourceID($0) == currentID } ?? -1
    let next = layouts[(index + 1) % layouts.count]
    lastSwitchAt = now()
    lastSwitchTo = sourceID(next)
    let status = TISSelectInputSource(next)
    if status != noErr {
        log("TISSelectInputSource(\(lastSwitchTo ?? "?")) failed: \(status) \(context())")
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        log("event tap re-enabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input"))")
    case .flagsChanged where event.getIntegerValueField(.keyboardEventKeycode) == fnKeyCode:
        if event.flags.contains(.maskSecondaryFn) {
            fnDown = true
            chorded = false
            fnDownAt = now()
        } else if fnDown {
            fnDown = false
            let held = now() - fnDownAt
            if !chorded && held <= maxTapNanos {
                switchToNextLayout()
            } else if !chorded {
                log("fn held \(ms(held))ms, too long for a tap")
            }
        }
    default:
        // Any key, other modifier, media key or click while fn is held makes it a chord (fn+←, fn+E, …).
        if fnDown { chorded = true }
    }
    return Unmanaged.passUnretained(event)
}

func installTap() -> Bool {
    let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
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

switch CommandLine.arguments.dropFirst().first {
case "--list":
    for source in keyboardLayouts() { print(sourceID(source) ?? "?") }
    exit(0)
case "--check-access":
    exit(CGPreflightListenEventAccess() ? 0 : 1)
default:
    break
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
    log("bounced to \(id) \(ms(since))ms after a tap to \(lastSwitchTo ?? "?"), \(context())")
}

// Without Input Monitoring access the tap is still created but never sees key events,
// so wait for the grant before installing it.
if CGPreflightListenEventAccess() && installTap() {
    log("started, cycling \(keyboardLayouts().compactMap(sourceID))")
} else {
    CGRequestListenEventAccess()
    log("waiting for Input Monitoring access (System Settings → Privacy & Security → Input Monitoring)")
    // This process will keep seeing "denied" even after the grant; exit and let launchd's
    // KeepAlive start a fresh one that sees it.
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        guard listenAccessGranted() else { return }
        log("Input Monitoring access granted, restarting")
        exit(0)
    }
}
CFRunLoopRun()
