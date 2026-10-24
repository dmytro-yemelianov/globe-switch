import AppKit

/// The on-screen hint with the new layout's flag (`ShowIndicator`). Unlike macOS's picker it
/// can never take keystrokes: the panel doesn't activate the app, ignores the mouse and refuses to
/// become the key window.
enum Indicator {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Room for the shadow around the flag.
    private static let padding = NSSize(width: 8, height: 8)
    private static var generation = 0

    private static let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        return label
    }()

    /// Just the flag, with no background; the layout's name only when it has no flag.
    private static func text(flag: String?, name: String) -> NSAttributedString {
        if let flag {
            return NSAttributedString(string: flag, attributes: [.font: NSFont.systemFont(ofSize: 52)])
        }
        // Without a background, white text with a shadow stays readable on light and dark windows.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 4
        return NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white, .shadow: shadow,
        ])
    }

    private static let panel: Panel = {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true // follows the flag's outline, so it stands out on any background
        panel.hidesOnDeactivate = false
        let content = NSView()
        content.addSubview(label)
        panel.contentView = content
        return panel
    }()

    /// Shows the layout near the bottom of the screen under the pointer, then fades it out.
    static func show(flag: String?, name: String) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        label.attributedStringValue = text(flag: flag, name: name)
        let textSize = label.intrinsicContentSize
        let size = NSSize(width: max(textSize.width + 2 * padding.width, textSize.height + 2 * padding.height),
                          height: textSize.height + 2 * padding.height)
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
