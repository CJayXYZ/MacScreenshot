import AppKit
import QuartzCore

enum OverlayResult {
    case cancelled
    /// The captured pixels and the area they came from, in points with a top-left origin.
    case image(CGImage, region: CGRect)
}

/// A non-activating panel: it takes keyboard and mouse input even when macOS keeps another
/// app frontmost (since macOS 14, apps can't always force themselves forward).
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Borderless windows must still cover the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A large, high-contrast "+" cursor (about twice the system crosshair) so it's obvious
/// screenshot mode is on. White arms with a dark outline show on any background; the
/// gap in the middle keeps the exact target pixel visible.
enum CaptureCursor {
    static let shared: NSCursor = {
        let side: CGFloat = 36, arm: CGFloat = 16, gap: CGFloat = 4
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let c = side / 2
            let path = NSBezierPath()
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] as [(CGFloat, CGFloat)] {
                path.move(to: NSPoint(x: c + dx * gap, y: c + dy * gap))
                path.line(to: NSPoint(x: c + dx * arm, y: c + dy * arm))
            }
            path.lineCapStyle = .round
            path.lineWidth = 4.5
            NSColor.black.withAlphaComponent(0.75).setStroke()
            path.stroke()
            path.lineWidth = 2
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }()

    static func set() { shared.set() }
}

/// Lets this app set the cursor while another app is frontmost. Undocumented WindowServer
/// property, used by many screenshot and window-management tools; without it the frontmost
/// app's arrow cursor can win over our crosshair.
enum BackgroundCursor {
    private typealias Connection = Int32
    @_silgen_name("_CGSDefaultConnection") private static func defaultConnection() -> Connection
    @_silgen_name("CGSSetConnectionProperty")
    private static func setProperty(_ cid: Connection, _ target: Connection, _ key: CFString, _ value: CFTypeRef) -> CGError

    static func enable() {
        let cid = defaultConnection()
        _ = setProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// Owns the full-screen window that shows the frozen frame. Everything it holds
/// (window, layers, the frozen image) is released when `close()` is called.
final class OverlayController {
    private var window: OverlayWindow?

    init(screen: NSScreen, image: CGImage, onFinish: @escaping (OverlayResult) -> Void) {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.setFrame(screen.frame, display: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                         image: image, scale: screen.backingScaleFactor, onFinish: onFinish)
        self.window = window
    }

    func show() {
        guard let window, let view = window.contentView as? OverlayView else { return }
        BackgroundCursor.enable()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.showLoupeAtMouse()
        CaptureCursor.set()
        // Re-assert once the window server has finished ordering the panel in.
        DispatchQueue.main.async { CaptureCursor.set() }
    }

    func close() {
        NSCursor.arrow.set()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}

/// Layer-hosting view: the frozen frame as the background layer, a dim layer with an
/// even-odd hole for the selection, the selection border, and the loupe.
final class OverlayView: NSView {
    private let image: CGImage
    private let scale: CGFloat
    private var onFinish: ((OverlayResult) -> Void)?

    // Image pixels per view point (normally the backing scale, measured to be exact).
    private let sx: CGFloat
    private let sy: CGFloat

    private var start: NSPoint?
    private var current: NSPoint?
    /// After Esc mid-drag, ignore the rest of that drag until the mouse is released.
    private var ignoreUntilMouseUp = false

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let loupe = CALayer()
    private let loupeImage = CALayer()
    private let loupeLabel = CATextLayer()

    private static let cells = 21          // pixels shown across the loupe (odd, so one is centred)
    private static let cellSize: CGFloat = 8
    private static var loupeSide: CGFloat { CGFloat(cells) * cellSize }
    private static let labelHeight: CGFloat = 18
    private static let labelGap: CGFloat = 4
    private static let loupeOffset: CGFloat = 24

    init(frame: NSRect, image: CGImage, scale: CGFloat, onFinish: @escaping (OverlayResult) -> Void) {
        self.image = image
        self.scale = scale
        self.onFinish = onFinish
        self.sx = CGFloat(image.width) / frame.width
        self.sy = CGFloat(image.height) / frame.height
        super.init(frame: frame)

        let root = CALayer()
        root.contentsScale = scale
        layer = root
        wantsLayer = true

        let background = CALayer()
        background.frame = bounds
        background.contents = image
        background.contentsGravity = .resize
        root.addSublayer(background)

        dimLayer.frame = bounds
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        root.addSublayer(dimLayer)

        borderLayer.frame = bounds
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        borderLayer.lineWidth = 1
        root.addSublayer(borderLayer)

        setUpLoupe()
        root.addSublayer(loupe)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Loupe

    private func setUpLoupe() {
        let side = Self.loupeSide
        loupe.isHidden = true
        loupe.bounds = CGRect(x: 0, y: 0, width: side, height: side + Self.labelGap + Self.labelHeight)
        loupe.anchorPoint = .zero

        loupeImage.frame = CGRect(x: 0, y: Self.labelHeight + Self.labelGap, width: side, height: side)
        loupeImage.magnificationFilter = .nearest
        loupeImage.backgroundColor = NSColor.black.cgColor
        loupeImage.cornerRadius = 6
        loupeImage.masksToBounds = true
        loupeImage.borderWidth = 1.5
        loupeImage.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        loupe.addSublayer(loupeImage)

        let grid = CAShapeLayer()
        grid.frame = loupeImage.bounds
        let gridPath = CGMutablePath()
        for i in 1..<Self.cells {
            let p = CGFloat(i) * Self.cellSize
            gridPath.move(to: CGPoint(x: p, y: 0)); gridPath.addLine(to: CGPoint(x: p, y: side))
            gridPath.move(to: CGPoint(x: 0, y: p)); gridPath.addLine(to: CGPoint(x: side, y: p))
        }
        grid.path = gridPath
        grid.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        grid.lineWidth = 0.5
        loupeImage.addSublayer(grid)

        let centre = CAShapeLayer()
        centre.frame = loupeImage.bounds
        let c = CGFloat(Self.cells / 2) * Self.cellSize
        centre.path = CGPath(rect: CGRect(x: c, y: c, width: Self.cellSize, height: Self.cellSize), transform: nil)
        centre.fillColor = nil
        centre.strokeColor = NSColor.systemRed.cgColor
        centre.lineWidth = 1.5
        loupeImage.addSublayer(centre)

        loupeLabel.frame = CGRect(x: 0, y: 0, width: side, height: Self.labelHeight)
        loupeLabel.contentsScale = scale
        loupeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        loupeLabel.fontSize = 11
        loupeLabel.alignmentMode = .center
        loupeLabel.foregroundColor = NSColor.white.cgColor
        loupeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        loupeLabel.cornerRadius = 4
        loupe.addSublayer(loupeLabel)
    }

    func showLoupeAtMouse() {
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updateLoupe(at: convert(inWindow, from: nil))
    }

    private func pixel(at p: NSPoint) -> (x: Int, y: Int) {
        let x = Int((p.x * sx).rounded(.down))
        let y = Int(((bounds.height - p.y) * sy).rounded(.down))
        return (min(max(x, 0), image.width - 1), min(max(y, 0), image.height - 1))
    }

    private func updateLoupe(at p: NSPoint) {
        let (px, py) = pixel(at: p)
        withoutAnimation {
            loupeImage.contents = sample(px: px, py: py)
            if let rect = selectionRect {
                let r = pixelRect(rect)
                loupeLabel.string = "\(Int(r.width)) × \(Int(r.height))"
            } else {
                loupeLabel.string = "\(px), \(py)"
            }

            // Below-right of the pointer, flipped to the other side near screen edges.
            let size = loupe.bounds.size
            var origin = NSPoint(x: p.x + Self.loupeOffset, y: p.y - Self.loupeOffset - size.height)
            if origin.x + size.width > bounds.maxX { origin.x = p.x - Self.loupeOffset - size.width }
            if origin.y < bounds.minY { origin.y = p.y + Self.loupeOffset }
            loupe.position = origin
            loupe.isHidden = false
        }
    }

    /// The cells x cells block of frozen pixels centred on (px, py), top-left image coordinates.
    private func sample(px: Int, py: Int) -> CGImage? {
        let n = Self.cells, half = n / 2
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.15, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))

        let wanted = CGRect(x: px - half, y: py - half, width: n, height: n)
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if !available.isNull, let piece = image.cropping(to: available) {
            ctx.interpolationQuality = .none
            // Image rows run top-down; the context's y axis runs bottom-up.
            let x = available.minX - wanted.minX
            let y = CGFloat(n) - (available.minY - wanted.minY) - available.height
            ctx.draw(piece, in: CGRect(x: x, y: y, width: available.width, height: available.height))
        }
        return ctx.makeImage()
    }

    // MARK: Selection

    private var selectionRect: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    /// View rect (points, bottom-left origin) to image rect (pixels, top-left origin).
    private func pixelRect(_ r: NSRect) -> CGRect {
        let x0 = (r.minX * sx).rounded(), x1 = (r.maxX * sx).rounded()
        let y0 = ((bounds.height - r.maxY) * sy).rounded(), y1 = ((bounds.height - r.minY) * sy).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private func renderSelection() {
        withoutAnimation {
            if let rect = selectionRect {
                let path = CGMutablePath()
                path.addRect(bounds)
                path.addRect(rect)
                dimLayer.path = path
                borderLayer.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            } else {
                dimLayer.path = nil
                borderLayer.path = nil
            }
        }
    }

    private func clamp(_ p: NSPoint) -> NSPoint {
        NSPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: CaptureCursor.shared) }
    override func cursorUpdate(with event: NSEvent) { CaptureCursor.set() }

    override func mouseMoved(with event: NSEvent) {
        CaptureCursor.set()
        updateLoupe(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        CaptureCursor.set()
        let p = clamp(convert(event.locationInWindow, from: nil))
        ignoreUntilMouseUp = false
        start = p
        current = p
        renderSelection()
        updateLoupe(at: p)
    }

    override func mouseDragged(with event: NSEvent) {
        CaptureCursor.set()
        let p = clamp(convert(event.locationInWindow, from: nil))
        guard !ignoreUntilMouseUp, start != nil else { updateLoupe(at: p); return }
        current = p
        renderSelection()
        updateLoupe(at: p)
    }

    override func mouseUp(with event: NSEvent) {
        if ignoreUntilMouseUp { ignoreUntilMouseUp = false; return }
        guard let rect = selectionRect else { return }
        start = nil
        current = nil
        let px = pixelRect(rect)
        // A click, or a selection under 4 x 4 px, is ignored.
        guard px.width >= 4, px.height >= 4, let cropped = image.cropping(to: px) else {
            renderSelection()
            updateLoupe(at: convert(event.locationInWindow, from: nil))
            return
        }
        finish(.image(cropped, region: CGRect(x: px.minX / sx, y: px.minY / sy, width: px.width / sx, height: px.height / sy)))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            escape()
        } else if isCommandA(event) {
            finishFullScreen()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCommandA(event) {
            finishFullScreen()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func isCommandA(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    /// First Esc clears an active selection; Esc with no selection closes the overlay.
    private func escape() {
        if start != nil {
            start = nil
            current = nil
            ignoreUntilMouseUp = NSEvent.pressedMouseButtons & 1 != 0
            renderSelection()
            showLoupeAtMouse()
        } else {
            finish(.cancelled)
        }
    }

    private func finishFullScreen() {
        finish(.image(image, region: CGRect(origin: .zero, size: bounds.size)))
    }

    private func finish(_ result: OverlayResult) {
        guard let onFinish else { return }
        self.onFinish = nil
        onFinish(result)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
