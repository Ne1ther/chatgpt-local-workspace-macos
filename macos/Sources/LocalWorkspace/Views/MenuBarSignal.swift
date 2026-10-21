import AppKit
import QuartzCore
import SwiftUI
import OSLog

/// Attached directly to NSStatusBarButton so its composited layer stays live.
final class MenuBarSignalView: NSView {
    private static let logger = Logger(subsystem: "community.localworkspace.mac", category: "MenuBarSignal")
    private let imageView = NSImageView()
    private let signal = CALayer()
    private let beam = CAGradientLayer()
    private let accent = CALayer()
    private var running = false
    private var attention = false
    private var reduceMotion = false
    private var occlusionObserver: NSObjectProtocol?
    private let blue = NSColor(srgbRed: 0.22, green: 0.48, blue: 1, alpha: 1)

    init() {
        let size = WorkspaceBrand.menuBarSize
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        imageView.frame = bounds
        imageView.image = WorkspaceBrand.menuBarImage
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
        guard let bitmap = WorkspaceBrand.menuBarImage.representations.compactMap({ $0 as? NSBitmapImageRep }).last,
              let maskImage = bitmap.cgImage else { return }
        func mask() -> CALayer {
            let mask = CALayer(); mask.frame = bounds; mask.contents = maskImage
            mask.contentsScale = 2; mask.contentsGravity = .resizeAspect
            return mask
        }
        // The baseline is a native 2pt capsule. Downsampling the artwork alone
        // makes this key identifying detail too thin, even at Retina scale.
        let underline = Self.underscoreBounds(bitmap)
        accent.frame = CGRect(x: (underline.minX * 2).rounded(.down) / 2,
                              y: 1, width: max(9, (underline.width * 2).rounded(.up) / 2), height: 2)
        accent.backgroundColor = blue.cgColor; accent.cornerRadius = 1
        layer?.addSublayer(accent)

        signal.frame = bounds; signal.mask = mask(); signal.opacity = 0
        beam.frame = CGRect(x: -size, y: 0, width: size * 2, height: size)
        beam.startPoint = CGPoint(x: 0, y: 0.5); beam.endPoint = CGPoint(x: 1, y: 0.5)
        beam.colors = [blue.withAlphaComponent(0).cgColor, blue.cgColor, NSColor.white.cgColor, blue.cgColor, blue.withAlphaComponent(0).cgColor]
        beam.locations = [0, 0.35, 0.5, 0.65, 1]
        signal.addSublayer(beam); layer?.addSublayer(signal)
        updateTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var intrinsicContentSize: NSSize { NSSize(width: WorkspaceBrand.menuBarSize, height: WorkspaceBrand.menuBarSize) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = occlusionObserver { NotificationCenter.default.removeObserver(observer) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncAnimation() }
            }
        }
        syncAnimation()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateTint() }
    func update(running: Bool, attention: Bool, reduceMotion: Bool) {
        self.running = running; self.attention = attention; self.reduceMotion = reduceMotion
        updateTint(); syncAnimation()
    }
    func stop() {
        if beam.animation(forKey: "workspace.signalSweep") != nil { Self.logger.info("Menu signal stopped") }
        beam.removeAnimation(forKey: "workspace.signalSweep"); signal.opacity = 0
    }
    private func updateTint() {
        imageView.contentTintColor = attention ? .systemOrange : .labelColor
    }
    private func syncAnimation() {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        guard running && !attention && !reduceMotion && visible else { stop(); return }
        guard beam.animation(forKey: "workspace.signalSweep") == nil else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true); signal.opacity = 0.95; CATransaction.commit()
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = -WorkspaceBrand.menuBarSize; sweep.toValue = WorkspaceBrand.menuBarSize * 2; sweep.duration = 1.8
        sweep.repeatCount = .infinity; sweep.timingFunction = CAMediaTimingFunction(name: .linear)
        beam.add(sweep, forKey: "workspace.signalSweep")
        Self.logger.info("Menu signal started: Core Animation, 20pt")
    }
    // The longer baseline now extends under the knot: identify by horizontal
    // shape and lower position, rather than requiring its left edge on the right.
    private static func underscoreBounds(_ bitmap: NSBitmapImageRep) -> CGRect {
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        var visited = Set<Int>(), components: [CGRect] = []
        for y in 0..<h { for x in 0..<w {
            let start = y * w + x
            guard !visited.contains(start), (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 else { continue }
            var queue = [start], index = 0, left = x, right = x, top = y, bottom = y
            visited.insert(start)
            while index < queue.count {
                let p = queue[index]; index += 1
                let px = p % w, py = p / w
                left = min(left, px); right = max(right, px); top = min(top, py); bottom = max(bottom, py)
                for (nx, ny) in [(px-1,py),(px+1,py),(px,py-1),(px,py+1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let next = ny*w+nx
                    if !visited.contains(next) && (bitmap.colorAt(x: nx, y: ny)?.alphaComponent ?? 0) > 0.2 { visited.insert(next); queue.append(next) }
                }
            }
            if top > h/2 && right > w*2/3 && right-left+1 > (bottom-top+1)*2 {
                let size = WorkspaceBrand.menuBarSize
                components.append(CGRect(x: CGFloat(left)*size/CGFloat(w), y: CGFloat(h-bottom-1)*size/CGFloat(h), width: CGFloat(right-left+1)*size/CGFloat(w), height: CGFloat(bottom-top+1)*size/CGFloat(h)))
            }
        }}
        return components.max(by: { $0.width < $1.width })?.insetBy(dx: -0.25, dy: -0.25) ?? CGRect(x: 9, y: 1, width: 10, height: 3)
    }
    deinit { if let observer = occlusionObserver { NotificationCenter.default.removeObserver(observer) } }
}
