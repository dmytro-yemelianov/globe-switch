import AppKit

/// The optional on-screen hint with the new layout's name (`ShowIndicator`). Unlike macOS's picker it
/// can never take keystrokes: the panel doesn't activate the app, ignores the mouse and refuses to
/// become the key window.
enum Indicator {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private static let padding = NSSize(width: 28, height: 14)
    private static var generation = 0

    private static let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.alignment = .center
        return label
    }()

    private static let panel: Panel = {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.addSubview(label)
        panel.contentView = background
        return panel
    }()

    /// Shows `text` near the bottom of the screen under the pointer, then fades it out.
    static func show(_ text: String) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        label.stringValue = text
        let textSize = label.intrinsicContentSize
        let size = NSSize(width: max(textSize.width + 2 * padding.width, 120), height: textSize.height + 2 * padding.height)
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.18,
                              width: size.width, height: size.height), display: false)
        label.frame = NSRect(x: 0, y: padding.height, width: size.width, height: textSize.height)

        generation += 1
        let shown = generation
        NSAnimationContext.runAnimationGroup { $0.duration = 0; panel.animator().alphaValue = 1 }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard shown == generation else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                if shown == generation { panel.orderOut(nil) }
            })
        }
    }
}
