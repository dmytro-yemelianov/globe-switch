// make-icon: draws the GlobeSwitch app icon (a line-art globe on a blue rounded square) and writes
// App/AppIcon.icns. Drawn from scratch, so it carries no emoji or SF Symbols artwork.
//
//   swift tools/make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024

    // macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.56, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.27, blue: 0.70, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    let center = NSPoint(x: 512 * s, y: 512 * s)
    let radius = 270 * s
    let line = 30 * s
    NSColor.white.setStroke()

    let outline = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    outline.lineWidth = line
    outline.stroke()

    // Meridians: a half-width ellipse and the central line.
    let meridian = NSBezierPath(ovalIn: NSRect(x: center.x - radius / 2, y: center.y - radius, width: radius, height: 2 * radius))
    meridian.lineWidth = line
    meridian.stroke()
    let axis = NSBezierPath()
    axis.move(to: NSPoint(x: center.x, y: center.y - radius))
    axis.line(to: NSPoint(x: center.x, y: center.y + radius))
    axis.lineWidth = line
    axis.stroke()

    // Equator and two parallels, clipped to the globe.
    NSGraphicsContext.saveGraphicsState()
    outline.addClip()
    for offset in [-0.5, 0, 0.5] as [CGFloat] {
        let y = center.y + radius * offset
        let parallel = NSBezierPath()
        parallel.move(to: NSPoint(x: center.x - radius, y: y))
        parallel.line(to: NSPoint(x: center.x + radius, y: y))
        parallel.lineWidth = line
        parallel.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let output = URL(fileURLWithPath: "App/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
