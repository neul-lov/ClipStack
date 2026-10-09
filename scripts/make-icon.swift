// Renders Resources/AppIcon.icns: a white clipboard on a blue rounded square.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Background tile, inset like other macOS app icons.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(red: 0.16, green: 0.45, blue: 1.0, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.33, green: 0.70, blue: 1.0, alpha: 1),
                        NSColor(red: 0.13, green: 0.36, blue: 0.96, alpha: 1)])!
        .draw(in: tilePath, angle: -90)

    // A second sheet peeking out behind the clipboard hints at the stacked history.
    NSColor.white.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: 330 * s, y: 215 * s, width: 440 * s, height: 520 * s),
                 xRadius: 56 * s, yRadius: 56 * s).fill()

    // Clipboard board.
    let board = NSRect(x: 262 * s, y: 190 * s, width: 440 * s, height: 560 * s)
    NSGraphicsContext.saveGraphicsState()
    let boardShadow = NSShadow()
    boardShadow.shadowColor = NSColor(red: 0.05, green: 0.15, blue: 0.5, alpha: 0.35)
    boardShadow.shadowBlurRadius = 30 * s
    boardShadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    boardShadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: board, xRadius: 60 * s, yRadius: 60 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Clip at the top.
    let accent = NSColor(red: 0.16, green: 0.45, blue: 1.0, alpha: 1)
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 382 * s, y: 700 * s, width: 200 * s, height: 96 * s),
                 xRadius: 40 * s, yRadius: 40 * s).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 462 * s, y: 742 * s, width: 40 * s, height: 40 * s)).fill()

    // Text lines, the first two marked with order dots.
    let lines: [(CGFloat, CGFloat, Bool)] = [(590, 300, true), (480, 240, true), (370, 280, false), (270, 190, false)]
    for (y, width, dotted) in lines {
        if dotted {
            accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: 318 * s, y: (y - 22) * s, width: 44 * s, height: 44 * s)).fill()
        }
        NSColor(white: 0.78, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 392 * s, y: (y - 14) * s, width: width * s, height: 28 * s),
                     xRadius: 14 * s, yRadius: 14 * s).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try render(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("Wrote \(output.path)")
