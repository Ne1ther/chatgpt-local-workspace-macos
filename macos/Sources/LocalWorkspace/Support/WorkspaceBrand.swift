import AppKit
import SwiftUI

enum WorkspaceBrand {
    static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "terminal", accessibilityDescription: "本地 AI 工作区")!
    }()

    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x"] {
            if let url = Bundle.main.url(forResource: "MenuBarIconTemplate\(suffix)", withExtension: "png"),
               let data = try? Data(contentsOf: url),
               let representation = NSBitmapImageRep(data: data) {
                representation.size = NSSize(width: 18, height: 18)
                image.addRepresentation(representation)
            }
        }
        if image.representations.isEmpty {
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "本地 AI 工作区")!
        }
        image.isTemplate = true
        return image
    }()
}

struct WorkspaceBrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: WorkspaceBrand.appIcon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
