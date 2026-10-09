// Renders Resources/AppIcon.icns and Resources/AppIcon.png.
// Usage: swift scripts/make-icon.swift
import AppKit

/// A continuous-corner rounded square (superellipse), the shape macOS app icons use.
func squircle(_ rect: NSRect, exponent: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / exponent), c)
        let y = cy + b * copysign(pow(abs(s), 2 / exponent), s)
        i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func withShadow(_ shadowColor: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func rotated(around center: NSPoint, degrees: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: degrees)
    transform.translateX(by: -center.x, yBy: -center.y)
    transform.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }

    // Background tile with a deep indigo-to-violet gradient and a soft glow at the top.
    let tile = squircle(r(100, 100, 824, 824))
    withShadow(.black.withAlphaComponent(0.28), blur: 28 * s, y: -12 * s) {
        color(0x3B3FE0).setFill()
        tile.fill()
    }
    NSGradient(colors: [color(0x6F7BFF), color(0x4B3FE8), color(0x2B1C9E)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: tile, angle: -70)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: color(0xFFFFFF, 0.35), ending: color(0xFFFFFF, 0))!
        .draw(fromCenter: NSPoint(x: 380 * s, y: 900 * s), radius: 0,
              toCenter: NSPoint(x: 380 * s, y: 900 * s), radius: 620 * s, options: [])
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.18).setStroke()
    let rim = squircle(r(102, 102, 820, 820))
    rim.lineWidth = 3 * s
    rim.stroke()

    // Two frosted cards fanned out behind the front one: the stack of past copies.
    let cardRect = r(312, 196, 400, 520)
    for (angle, alpha) in [(14.0, 0.22), (7.0, 0.38)] {
        rotated(around: NSPoint(x: 512 * s, y: 300 * s), degrees: CGFloat(angle)) {
            withShadow(color(0x12086B, 0.25), blur: 24 * s, y: -8 * s) {
                color(0xFFFFFF, CGFloat(alpha)).setFill()
                NSBezierPath(roundedRect: cardRect, xRadius: 64 * s, yRadius: 64 * s).fill()
            }
        }
    }

    // Front card.
    let front = NSBezierPath(roundedRect: cardRect, xRadius: 64 * s, yRadius: 64 * s)
    withShadow(color(0x12086B, 0.45), blur: 40 * s, y: -18 * s) {
        color(0xFFFFFF).setFill()
        front.fill()
    }
    NSGradient(starting: color(0xFFFFFF), ending: color(0xEEF0FF))!.draw(in: front, angle: -90)

    // Clip: a rounded tab with a gradient and a punched hole.
    let clip = NSBezierPath(roundedRect: r(422, 664, 180, 92), xRadius: 46 * s, yRadius: 46 * s)
    withShadow(color(0x12086B, 0.35), blur: 12 * s, y: -5 * s) {
        color(0x5B5BF5).setFill()
        clip.fill()
    }
    NSGradient(starting: color(0x8C93FF), ending: color(0x4B3FE8))!.draw(in: clip, angle: -90)
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: r(492, 694, 40, 40)).fill()

    // Numbered rows: picks copied in order.
    let rounded = NSFont.systemFont(ofSize: 54 * s, weight: .heavy).fontDescriptor.withDesign(.rounded)!
    let font = NSFont(descriptor: rounded, size: 54 * s)!
    let rows: [(CGFloat, CGFloat, String?)] = [(560, 200, "1"), (440, 150, "2"), (320, 180, nil)]
    for (y, width, number) in rows {
        let badge = r(366, y - 36, 72, 72)
        if let number {
            withShadow(color(0x4B3FE8, 0.4), blur: 10 * s, y: -4 * s) {
                color(0x5B5BF5).setFill()
                NSBezierPath(ovalIn: badge).fill()
            }
            NSGradient(starting: color(0x8C93FF), ending: color(0x4B3FE8))!
                .draw(in: NSBezierPath(ovalIn: badge), angle: -90)
            let text = NSAttributedString(string: number, attributes: [.font: font, .foregroundColor: NSColor.white])
            let textSize = text.size()
            text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
        } else {
            color(0xC9CCF2).setStroke()
            let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 5 * s, dy: 5 * s))
            ring.lineWidth = 8 * s
            ring.stroke()
        }
        color(number == nil ? 0xDCDEF5 : 0xC9CCF2).setFill()
        NSBezierPath(roundedRect: r(468, y - 16, width, 32), xRadius: 16 * s, yRadius: 16 * s).fill()
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
