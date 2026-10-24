import AppKit
import GlobeSwitchCore
import QuartzCore

/// The on-screen hint after a switch (`ShowIndicator`): every layout's flag in a row, with the active
/// one in the middle, larger and glowing in the accent colour, and the row sliding to put the new
/// layout there. Unlike macOS's picker it can never take keystrokes: the panel doesn't activate the
/// app, ignores the mouse and refuses to become the key window.
enum Indicator {
    struct Item: Equatable {
        let id: String
        let flag: LayoutFlag?
        let name: String
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Distance between the centres of neighbouring flags.
    private static let slot: CGFloat = 78
    private static let height: CGFloat = 100
    private static let restScale: CGFloat = 0.55
    private static let restOpacity: Float = 0.45
    /// One pixel of a pixel-art flag: 22 × 14 pixels make a 66 × 42 flag, about as wide as an emoji one.
    private static let flagPixel: CGFloat = 3

    private static var items: [Item] = []
    private static var layers: [CALayer] = []
    private static var generation = 0

    private static let panel: Panel = {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the flags carry their own shadows
        panel.hidesOnDeactivate = false
        let content = NSView()
        content.layer = CALayer() // layer-hosting, so the flag layers are ours to animate
        content.wantsLayer = true
        panel.contentView = content
        return panel
    }()

    /// Lines up `items` near the bottom of the screen under the pointer and slides the row from
    /// `previous` to `active`, then fades it out.
    static func show(_ items: [Item], from previous: String, to active: String) {
        guard let target = items.firstIndex(where: { $0.id == active }),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else {
            return
        }
        let wasShowing = panel.isVisible
        if items != self.items {
            rebuild(items, scale: screen.backingScaleFactor)
        }
        // Wide enough to centre the first or the last layout with all the others still in view.
        let width = slot * CGFloat(2 * items.count - 1)
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: visible.minY + visible.height * 0.16,
                              width: width, height: height), display: false)
        if !wasShowing {
            // Start from the layout that was active, so the move to the new one shows.
            arrange(around: items.firstIndex(where: { $0.id == previous }) ?? target, animated: false)
        }
        arrange(around: target, animated: true)

        generation += 1
        let shown = generation
        NSAnimationContext.runAnimationGroup { $0.duration = 0; panel.animator().alphaValue = 1 }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard shown == generation else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                if shown == generation { panel.orderOut(nil) }
            })
        }
    }

    private static func rebuild(_ newItems: [Item], scale: CGFloat) {
        layers.forEach { $0.removeFromSuperlayer() }
        layers = newItems.map { item in
            let layer = CALayer()
            if case .region(let code)? = item.flag, let flag = PixelFlag.byRegion[code], let image = bitmap(of: flag) {
                layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(PixelFlag.width) * flagPixel,
                                      height: CGFloat(PixelFlag.height) * flagPixel)
                layer.contents = image
                // Scaled up and down without smoothing, so the pixels stay sharp squares.
                layer.magnificationFilter = .nearest
                layer.minificationFilter = .nearest
            } else {
                let image = picture(of: item)
                layer.bounds = CGRect(origin: .zero, size: image.size)
                layer.contentsScale = scale
                layer.contents = image.layerContents(forContentsScale: scale)
            }
            layer.shadowOffset = .zero
            panel.contentView?.layer?.addSublayer(layer)
            return layer
        }
        items = newItems
    }

    /// A pixel-art flag at one image pixel per flag pixel.
    private static func bitmap(of flag: PixelFlag) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(flag.rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: PixelFlag.width, height: PixelFlag.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: PixelFlag.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The emoji flag or the user's text as a picture, or the layout's name when it has no flag.
    private static func picture(of item: Item) -> NSImage {
        let text: NSAttributedString
        if let flag = item.flag {
            text = NSAttributedString(string: flag.description, attributes: [.font: NSFont.systemFont(ofSize: 56)])
        } else {
            text = NSAttributedString(string: item.name, attributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white,
            ])
        }
        let size = text.size()
        return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
            text.draw(at: .zero)
            return true
        }
    }

    /// Puts layout `index` in the middle at full size with a glow, and the others beside it, smaller
    /// and dimmed. Animated moves start from wherever each flag is on screen right now, so quick
    /// taps carry on smoothly instead of jumping.
    private static func arrange(around index: Int, animated: Bool) {
        let centre = slot * CGFloat(2 * layers.count - 1) / 2
        let glow = NSColor.controlAccentColor.cgColor
        let shade = NSColor.black.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, layer) in layers.enumerated() {
            let active = i == index
            let scale = active ? 1 : restScale
            set(layer, "position", NSValue(point: CGPoint(x: centre + CGFloat(i - index) * slot, y: height / 2)), animated)
            set(layer, "transform", NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)), animated)
            set(layer, "opacity", NSNumber(value: active ? 1 : restOpacity), animated)
            set(layer, "shadowColor", active ? glow : shade, animated)
            set(layer, "shadowOpacity", NSNumber(value: active ? 0.9 : 0.35), animated)
            set(layer, "shadowRadius", NSNumber(value: active ? 10 : 3), animated)
        }
        CATransaction.commit()
    }

    private static func set(_ layer: CALayer, _ keyPath: String, _ value: Any, _ animated: Bool) {
        if animated {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
            animation.toValue = value
            animation.stiffness = 320
            animation.damping = 28
            animation.duration = animation.settlingDuration
            layer.add(animation, forKey: keyPath)
        }
        layer.setValue(value, forKeyPath: keyPath)
    }
}
