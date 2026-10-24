// globe-probe: synthesize Globe (fn) taps and measure whether/when the input source changes.
//
// Synthetic CGEvent taps reach globe-switch's event tap but never macOS's own 🌐 handling,
// so this exercises globe-switch alone. Needs Accessibility access for the terminal running it.
//
//   globe-probe status                              permission, current layout, TextInputSwitcher pid
//   globe-probe press <count> <gapMs> [typeAfterMs] tap 🌐 <count> times; optionally tap shift after
//   globe-probe chord                               fn held while shift is tapped: must not switch
//   globe-probe hold                                fn held 900 ms: must not switch
//   globe-probe select <inputSourceID>              select a layout directly, e.g. com.apple.keylayout.ABC
import Carbon
import Cocoa

setvbuf(stdout, nil, _IONBF, 0)

func currentID() -> String {
    let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func short(_ id: String) -> String { id.replacingOccurrences(of: "com.apple.keylayout.", with: "") }

func switcherPID() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-x", "TextInputSwitcher"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "dead" : s.trimmingCharacters(in: .whitespacesAndNewlines)
}

var changes: [(Date, String)] = []
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: nil
) { _ in changes.append((Date(), currentID())) }

func pump(_ ms: Int) { RunLoop.current.run(until: Date().addingTimeInterval(Double(ms) / 1000)) }

let hid = CGEventSource(stateID: .hidSystemState)

func postFlags(_ keyDown: Bool) {
    let e = CGEvent(keyboardEventSource: hid, virtualKey: 63, keyDown: keyDown)!
    e.type = .flagsChanged
    e.flags = keyDown ? .maskSecondaryFn : []
    e.post(tap: .cghidEventTap)
}

func tapGlobe() {
    postFlags(true)
    usleep(60_000)
    postFlags(false)
}

// A harmless modifier-only "keystroke" (shift tap) to stand in for "start typing" without inserting text.
func tapShift() {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: hid, virtualKey: 56, keyDown: down)!
        e.type = .flagsChanged
        e.flags = down ? .maskShift : []
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "status" {
case "status":
    print("postEventAccess=\(CGPreflightPostEventAccess()) current=\(short(currentID())) switcher=\(switcherPID())")

case "select":
    let want = args[2]
    let list = TISCreateInputSourceList([kTISPropertyInputSourceID: want] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
    if let s = list.first { TISSelectInputSource(s) }
    pump(300)
    print("current=\(short(currentID()))")

case "press":
    let count = Int(args[2])!, gap = Int(args[3])!
    let typeAfter = args.count > 4 ? Int(args[4]) : nil
    pump(200)
    var before = currentID()
    print("start current=\(short(before)) switcher=\(switcherPID())")
    for i in 1...count {
        changes.removeAll()
        let pidBefore = switcherPID()
        let t0 = Date()
        tapGlobe()
        if let ta = typeAfter { pump(ta); tapShift() }
        pump(gap)
        let after = currentID()
        let firstMs = changes.first.map { Int($0.0.timeIntervalSince(t0) * 1000) }
        let trail = changes.map { "\(Int($0.0.timeIntervalSince(t0) * 1000))ms→\(short($0.1))" }.joined(separator: ", ")
        let verdict = after != before ? "SWITCHED" : (changes.isEmpty ? "MISSED" : "BOUNCED")
        print("#\(i) switcher=\(pidBefore) \(short(before))→\(short(after)) \(verdict) first=\(firstMs.map { "\($0)ms" } ?? "-") events=[\(trail)]")
        before = after
    }
    pump(1500)
    print("end current=\(short(currentID())) switcher=\(switcherPID()) late-events=\(changes.count)")

case "chord":
    // fn held while shift is tapped: must NOT switch.
    pump(200)
    let before = currentID()
    changes.removeAll()
    postFlags(true); usleep(60_000)
    tapShift()
    postFlags(false)
    pump(1000)
    print("chord \(short(before))→\(short(currentID())) \(currentID() == before && changes.isEmpty ? "NO-SWITCH(ok)" : "SWITCHED(bad)")")

case "hold":
    // fn held longer than the tap window: must NOT switch.
    pump(200)
    let before = currentID()
    changes.removeAll()
    postFlags(true); usleep(900_000); postFlags(false)
    pump(1000)
    print("hold \(short(before))→\(short(currentID())) \(currentID() == before && changes.isEmpty ? "NO-SWITCH(ok)" : "SWITCHED(bad)")")

default:
    print("usage: status | press <count> <gapMs> [typeAfterMs] | chord | hold | select <id>")
}
