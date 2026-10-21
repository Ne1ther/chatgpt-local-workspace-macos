import AppKit
import Foundation

// Package the selected Interlace artwork. No rasterized presentation-board crops
// or code-drawn approximations: the two dedicated masters are the source assets.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("macos/Resources", isDirectory: true)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-icons-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func load(_ name: String) throws -> (NSImage, NSBitmapImageRep) {
    let data = try Data(contentsOf: resources.appendingPathComponent("Brand/\(name).png"))
    guard let bitmap = NSBitmapImageRep(data: data), let cg = bitmap.cgImage else {
        fatalError("Invalid icon master: \(name)")
    }
    return (NSImage(cgImage: cg, size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)), bitmap)
}

func bounds(_ bitmap: NSBitmapImageRep, threshold: CGFloat) -> NSRect {
    var left = bitmap.pixelsWide, top = bitmap.pixelsHigh, right = -1, bottom = -1
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > threshold {
            left = min(left, x); top = min(top, y); right = max(right, x); bottom = max(bottom, y)
        }
    }
    guard right >= left, bottom >= top else { fatalError("Icon master has no visible pixels") }
    return NSRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
}

func render(_ size: NSSize, scale: CGFloat = 1, draw: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func drawFitted(_ image: NSImage, pixelBounds: NSRect, in target: NSRect) {
    let scale = min(target.width / pixelBounds.width, target.height / pixelBounds.height)
    // NSBitmapImageRep uses top-origin rows; NSImage draws in bottom-origin space.
    let centerY = image.size.height - pixelBounds.midY
    image.draw(in: NSRect(x: target.midX - pixelBounds.midX * scale,
                         y: target.midY - centerY * scale,
                         width: image.size.width * scale, height: image.size.height * scale))
}

let (app, appBitmap) = try load("InterlaceApp")
let (menu, menuBitmap) = try load("InterlaceMenuOptical")
// The opaque tile's centre cross-section is stable even when a transparent
// master has tiny edge remnants. Packaging clips to the native rounded tile.
func tileBounds(_ bitmap: NSBitmapImageRep) -> NSRect {
    let midX = bitmap.pixelsWide / 2, midY = bitmap.pixelsHigh / 2
    let xs = (0..<bitmap.pixelsWide).filter { (bitmap.colorAt(x: $0, y: midY)?.alphaComponent ?? 0) > 0.95 }
    let ys = (0..<bitmap.pixelsHigh).filter { (bitmap.colorAt(x: midX, y: $0)?.alphaComponent ?? 0) > 0.95 }
    guard let left = xs.first, let right = xs.last, let top = ys.first, let bottom = ys.last else { fatalError("Missing opaque app tile") }
    return NSRect(x: left, y: top, width: right-left+1, height: bottom-top+1)
}
let appBounds = tileBounds(appBitmap)
let menuBounds = bounds(menuBitmap, threshold: 0.5)
func appPNG(_ pixels: Int) -> Data {
    render(NSSize(width: 1024, height: 1024), scale: CGFloat(pixels) / 1024) {
        // Native safe area, clean alpha silhouette at every icon size.
        NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 174, yRadius: 174).addClip()
        drawFitted(app, pixelBounds: appBounds, in: NSRect(x: 80, y: 80, width: 864, height: 864))
    }
}
func menuPNG(_ scale: CGFloat, color: NSColor = .black) -> Data {
    render(NSSize(width: 20, height: 20), scale: scale) {
        // Optical-size artwork: broad bands, open counters and a longer baseline.
        // Keep native status-item width; use more of its available image area.
        drawFitted(menu, pixelBounds: menuBounds, in: NSRect(x: 1, y: 1, width: 18, height: 18))
        color.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill(using: .sourceIn)
    }
}
try appPNG(1024).write(to: resources.appendingPathComponent("AppIcon.png"))
for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let suffix = retina ? "@2x" : ""
        try appPNG(size * (retina ? 2 : 1)).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
for (scale, suffix) in [(CGFloat(1), ""), (CGFloat(2), "@2x")] {
    let data = menuPNG(scale)
    try data.write(to: resources.appendingPathComponent("MenuBarIconTemplate\(suffix).png"))
    let bitmap = NSBitmapImageRep(data: data)!
    let ink = bounds(bitmap, threshold: 0.1)
    print("Menu \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)px; ink \(Int(ink.width))x\(Int(ink.height))px")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// A native asset-size proof, not a screenshot of the user's global menu bar.
// The symbol and SF Symbols share the same 18pt cells, at 2x pixel density.
let proof = render(NSSize(width: 620, height: 160), scale: 2) {
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 620, height: 160).fill()
    let icon = NSImage(data: appPNG(256))!
    icon.draw(in: NSRect(x: 18, y: 16, width: 128, height: 128))
    for (y, foreground, background) in [(CGFloat(88), NSColor.black, NSColor(calibratedWhite: 0.9, alpha: 1)),
                                        (CGFloat(40), NSColor.white, NSColor(calibratedWhite: 0.16, alpha: 1))] {
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 170, y: y - 4, width: 424, height: 28), xRadius: 7, yRadius: 7).fill()
        NSImage(data: menuPNG(2, color: foreground))!.draw(in: NSRect(x: 189, y: y, width: 20, height: 20))
        for (index, symbol) in ["wifi", "battery.100", "switch.2"].enumerated() {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let mask = render(NSSize(width: 18, height: 18), scale: 2) {
                    let source = image.size
                    let ratio = min(18 / source.width, 14 / source.height)
                    image.draw(in: NSRect(x: (18 - source.width * ratio) / 2, y: (18 - source.height * ratio) / 2,
                                          width: source.width * ratio, height: source.height * ratio))
                    foreground.setFill()
                    NSRect(x: 0, y: 0, width: 18, height: 18).fill(using: .sourceIn)
                }
                NSImage(data: mask)!.draw(in: NSRect(x: 238 + index * 46, y: Int(y) + 1, width: 18, height: 18))
            }
        }
        ("20 pt  ·  optical glyph 18 pt" as NSString).draw(at: NSPoint(x: 380, y: y + 2),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: foreground])
    }
    ("Native asset size proof · 2× pixels" as NSString).draw(at: NSPoint(x: 174, y: 132),
        withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray])
}
try proof.write(to: root.appendingPathComponent("docs/design-preview/icon-size-proof.png"))
print("Generated Interlace app icon and native-size menu template.")
