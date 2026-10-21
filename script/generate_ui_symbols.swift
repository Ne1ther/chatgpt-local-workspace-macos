import AppKit
import Foundation

// Export the system's real SF Symbols for WKWebView. PNG assets are generated
// once, remain crisp at Retina density, and require no font or drawing at runtime.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = root.appendingPathComponent("src/ui/assets/macos-symbols.json")
let definitions: [(String, String, UInt32)] = [
    ("folder", "folder.fill", 0x5AA9F8),
    ("terminal", "terminal.fill", 0x64D2AA),
    ("fileText", "doc.text.fill", 0x64A8FF),
    ("file", "doc.fill", 0x64A8FF),
    ("filePen", "square.and.pencil", 0xBF8CFF),
    ("image", "photo.fill", 0xBF8CFF),
    ("layers", "square.stack.3d.up.fill", 0x729BF8),
    ("search", "magnifyingglass", 0x989DA8),
    ("git", "arrow.triangle.branch", 0xFF9F0A),
    ("listChecks", "checklist", 0xFFCC00),
    ("info", "info.circle.fill", 0x8E9AAC),
    ("alert", "exclamationmark.triangle.fill", 0xFF9F0A),
    ("check", "checkmark.circle.fill", 0x64D2AA),
    ("clock", "clock.fill", 0xBF8CFF),
    ("activity", "waveform.path.ecg", 0xFF6961),
    ("timer", "timer", 0xFF9F0A),
]
var assets: [String: String] = [:]
for (key, symbol, rgb) in definitions {
    guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
        fatalError("Missing system symbol: \(symbol)")
    }
    let tint = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    // checkmark.circle.fill has two palette layers; other glyphs retain their
    // native negative-space detail when drawn with a single foreground color.
    let colors = key == "check" ? [NSColor.white, tint] : [tint]
    let configuration = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    let configured = image.withSymbolConfiguration(configuration)!
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ratio = min(84 / configured.size.width, 84 / configured.size.height)
    let size = NSSize(width: configured.size.width * ratio, height: configured.size.height * ratio)
    configured.draw(in: NSRect(x: (96 - size.width) / 2, y: (96 - size.height) / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    assets[key] = "data:image/png;base64," + png.base64EncodedString()
}
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: assets, options: [.sortedKeys]).write(to: destination, options: .atomic)
print("Exported \(assets.count) native macOS symbols.")
