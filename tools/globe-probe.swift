// globe-probe: synthesize Globe (fn) taps and measure whether/when the input source changes.
//
// Synthetic CGEvent taps reach globe-switch's event tap but never macOS's own 🌐 handling,
// so this exercises globe-switch alone. Needs Accessibility access for the terminal running it.
//
//   globe-probe status                              permission, current layout, TextInputSwitcher pid
//   globe-probe press <count> <gapMs> [typeAfterMs] tap 🌐 <count> times; optionally tap shift after
//   globe-probe chord                               fn held while shift is tapped: must not switch
//   globe-probe hold                                fn held 900 ms: must not switch
//   globe-probe scroll                              fn held while the wheel scrolls: must not switch
//   globe-probe type [count] [typeAfterMs]          tap 🌐, then type into our own field: no lost keys
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

case "scroll":
    // fn held while the wheel scrolls one line: must NOT switch.
    pump(200)
    let before = currentID()
    changes.removeAll()
    postFlags(true); usleep(60_000)
    CGEvent(scrollWheelEvent2Source: hid, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    usleep(30_000)
    postFlags(false)
    pump(1000)
    print("scroll \(short(before))→\(short(currentID())) \(currentID() == before && changes.isEmpty ? "NO-SWITCH(ok)" : "SWITCHED(bad)")")

case "type":
    // Tap 🌐, then type a letter <typeAfterMs> later into a text field of our own, <count> times.
    // Every letter must arrive and our window must stay frontmost: nothing may take the keyboard,
    // the optional indicator included.
    let count = args.count > 2 ? Int(args[2])! : 5
    let typeAfter = args.count > 3 ? Int(args[3])! : 40
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    // RunLoop.run doesn't hand key events to windows; the application has to dispatch them.
    func pumpEvents(_ ms: Int) {
        let until = Date().addingTimeInterval(Double(ms) / 1000)
        while let event = app.nextEvent(matching: .any, until: until, inMode: .default, dequeue: true) {
            app.sendEvent(event)
        }
    }
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSTextField(frame: NSRect(x: 10, y: 15, width: 340, height: 28))
    window.contentView?.addSubview(field)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    window.makeFirstResponder(field)
    pumpEvents(800)
    var indicatorSeen = false
    for i in 1...count {
        let before = field.stringValue.count
        tapGlobe()
        pumpEvents(typeAfter)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: hid, virtualKey: 0, keyDown: down)! // the A key
            e.post(tap: .cghidEventTap)
        }
        pumpEvents(150)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        indicatorSeen = indicatorSeen || windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "GlobeSwitch" }
        let arrived = field.stringValue.count - before
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        print("#\(i) layout=\(short(currentID())) typed=\(arrived == 1 ? "ok" : "LOST") front=\(front ? "ok" : "STOLEN")")
        pumpEvents(400)
    }
    print("text=\"\(field.stringValue)\" indicator=\(indicatorSeen ? "seen" : "not seen")")

default:
    print("usage: status | press <count> <gapMs> [typeAfterMs] | chord | hold | scroll | type [count] [typeAfterMs] | select <id>")
}
