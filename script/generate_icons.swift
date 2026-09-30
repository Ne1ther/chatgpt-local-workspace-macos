import AppKit
import Foundation

// Original vector artwork: two linked workspaces with a local command prompt.
// AppKit renders every icon size directly, so small Dock/menu icons stay crisp.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("macos/Resources", isDirectory: true)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-icons-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func drawAppIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 88, width: 864, height: 864), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x292826, alpha: 0.24)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    color(0xE7E3DC).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0xD9D6D0), color(0xECE9E3), color(0xFAF8F3)])!
        .draw(in: tile, angle: 90)
    color(0xFFFFFF, alpha: 0.8).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // Two overlapping windows express the web-to-local connection. Warm ceramic,
    // graphite and brushed silver replace the conventional blue/purple AI glow.
    let back = NSBezierPath(roundedRect: NSRect(x: 324, y: 398, width: 488, height: 378), xRadius: 76, yRadius: 76)
    NSGraphicsContext.saveGraphicsState()
    let backShadow = NSShadow()
    backShadow.shadowColor = color(0x292826, alpha: 0.14)
    backShadow.shadowBlurRadius = 18
    backShadow.shadowOffset = NSSize(width: 0, height: -8)
    backShadow.set()
    color(0xBBBAB5).setFill()
    back.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xA3A39F), color(0xD8D8D2), color(0xF0EEE8)])!
        .draw(in: back, angle: 90)
    color(0xFFFFFF, alpha: 0.8).setStroke()
    back.lineWidth = 3
    back.stroke()

    let front = NSBezierPath(roundedRect: NSRect(x: 212, y: 254, width: 580, height: 458), xRadius: 82, yRadius: 82)
    NSGraphicsContext.saveGraphicsState()
    let frontShadow = NSShadow()
    frontShadow.shadowColor = color(0x232322, alpha: 0.34)
    frontShadow.shadowBlurRadius = 28
    frontShadow.shadowOffset = NSSize(width: 0, height: -16)
    frontShadow.set()
    color(0x28292B).setFill()
    front.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x242527), color(0x303234), color(0x454749)])!
        .draw(in: front, angle: 90)
    color(0xFFFFFF, alpha: 0.22).setStroke()
    front.lineWidth = 3
    front.stroke()

    NSGraphicsContext.saveGraphicsState()
    front.addClip()
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 212, y: 624))
    divider.line(to: NSPoint(x: 792, y: 624))
    divider.lineWidth = 2
    color(0xFFFFFF, alpha: 0.11).setStroke()
    divider.stroke()
    for x in [278.0, 309.0, 340.0] {
        color(0xD5D2CB, alpha: 0.62).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 8, y: 661, width: 16, height: 16)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 328, y: 541))
    prompt.line(to: NSPoint(x: 406, y: 472))
    prompt.line(to: NSPoint(x: 328, y: 403))
    prompt.move(to: NSPoint(x: 482, y: 403))
    prompt.line(to: NSPoint(x: 588, y: 403))
    prompt.lineWidth = 35
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    color(0xF5F1E9).setStroke()
    prompt.stroke()
}

func drawMenuIcon() {
    NSColor.black.setStroke()
    let back = NSBezierPath()
    back.move(to: NSPoint(x: 5.8, y: 14.75))
    back.line(to: NSPoint(x: 13.8, y: 14.75))
    back.curve(to: NSPoint(x: 16.0, y: 12.55), controlPoint1: NSPoint(x: 15.05, y: 14.75), controlPoint2: NSPoint(x: 16, y: 13.8))
    back.line(to: NSPoint(x: 16.0, y: 7.6))
    back.lineWidth = 1.4
    back.lineCapStyle = .round
    back.stroke()
    let front = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 2.75, width: 11.75, height: 9.9), xRadius: 2.1, yRadius: 2.1)
    front.lineWidth = 1.4
    front.stroke()
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 5.0, y: 9.4))
    prompt.line(to: NSPoint(x: 6.85, y: 7.65))
    prompt.line(to: NSPoint(x: 5.0, y: 5.9))
    prompt.lineWidth = 1.4
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    prompt.stroke()
}

func render(pixels: Int, logicalSize: CGFloat, draw: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / logicalSize
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

try render(pixels: 1024, logicalSize: 1024, draw: drawAppIcon).write(to: resources.appendingPathComponent("AppIcon.png"))
for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let suffix = retina ? "@2x" : ""
        let pixels = size * (retina ? 2 : 1)
        try render(pixels: pixels, logicalSize: 1024, draw: drawAppIcon)
            .write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
for (pixels, suffix) in [(18, ""), (36, "@2x")] {
    try render(pixels: pixels, logicalSize: 18, draw: drawMenuIcon)
        .write(to: resources.appendingPathComponent("MenuBarIconTemplate\(suffix).png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated app and menu bar icons.")
