import AppKit
import Combine
import Shared

/// Shows the image fitted to the view and turns mouse drags into annotations.
/// Flipped (top-left origin) so view and image coordinates run the same way.
final class EditorCanvas: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var subscription: AnyCancellable?

    private var dragStart: CGPoint?   // image pixels
    private var dragCurrent: CGPoint?
    private var textField: NSTextField?
    private var textOrigin: CGPoint?  // image pixels
    private var cancelText = false
    private var textWeight: NSFont.Weight = .bold

    var onEscape: (() -> Void)?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.model.tool != .text { self.commitText() }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private var imageSize: CGSize { CGSize(width: model.document.image.width, height: model.document.image.height) }

    /// View points per image pixel: fit inside the view, never larger than the capture's real size.
    private var displayScale: CGFloat {
        let area = bounds.insetBy(dx: 20, dy: 20)
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(area.width / imageSize.width, area.height / imageSize.height, 1 / model.scale)
    }

    private var imageRect: CGRect {
        let s = displayScale
        let size = CGSize(width: imageSize.width * s, height: imageSize.height * s)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height).integral
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = displayScale
        return CGPoint(x: min(max((p.x - r.minX) / s, 0), imageSize.width),
                       y: min(max((p.y - r.minY) / s, 0), imageSize.height))
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = displayScale
        return CGPoint(x: r.minX + p.x * s, y: r.minY + p.y * s)
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let r = imageRect
        NSImage(cgImage: model.document.image, size: .zero)
            .draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                  hints: [.interpolation: NSImageInterpolation.high])

        // Annotations are drawn in image pixels, scaled onto the view.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: r.minX, yBy: r.minY)
        transform.scale(by: displayScale)
        transform.concat()
        var marks = model.document.annotations
        if let preview = previewAnnotation { marks.append(preview) }
        EditorRenderer.draw(marks)
        NSGraphicsContext.restoreGraphicsState()

        if model.tool == .crop, let start = dragStart, let current = dragCurrent {
            drawCropPreview(rect(toView(start), toView(current)), in: r)
        }
    }

    private func drawCropPreview(_ crop: CGRect, in imageRect: CGRect) {
        let dim = NSBezierPath(rect: imageRect)
        dim.append(NSBezierPath(rect: crop))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        let border = NSBezierPath(rect: crop.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()
    }

    private var previewAnnotation: Annotation? {
        guard let start = dragStart, let end = dragCurrent else { return nil }
        switch model.tool {
        case .arrow: return .arrow(from: start, to: end, color: model.color, width: model.lineWidth)
        case .box: return .box(rect(start, end), color: model.color, width: model.lineWidth)
        case .circle: return .circle(rect(start, end), color: model.color, width: model.lineWidth)
        case .highlight: return .highlight(rect(start, end), color: model.color)
        case .crop, .text: return nil
        }
    }

    // MARK: Mouse

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: model.tool == .text ? .iBeam : .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = toImage(convert(event.locationInWindow, from: nil))
        if model.tool == .text {
            beginText(at: p)
            return
        }
        dragStart = p
        dragCurrent = p
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = toImage(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
        guard let start = dragStart, let end = dragCurrent else { return }
        let area = rect(start, end)
        let minSize = 4 * model.scale
        switch model.tool {
        case .arrow:
            if hypot(end.x - start.x, end.y - start.y) >= minSize {
                model.add(.arrow(from: start, to: end, color: model.color, width: model.lineWidth))
            }
        case .box:
            if area.width >= minSize, area.height >= minSize {
                model.add(.box(area, color: model.color, width: model.lineWidth))
            }
        case .circle:
            if area.width >= minSize, area.height >= minSize {
                model.add(.circle(area, color: model.color, width: model.lineWidth))
            }
        case .highlight:
            if area.width >= minSize, area.height >= minSize { model.add(.highlight(area, color: model.color)) }
        case .crop:
            if area.width >= minSize, area.height >= minSize { model.crop(to: area) }
        case .text:
            break
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .option, .control])
        if event.keyCode == 53 { // Esc
            onEscape?()
        } else if plain, let ch = event.charactersIgnoringModifiers?.lowercased().first,
                  let tool = EditorTool.allCases.first(where: { $0.key == ch }) {
            model.tool = tool
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Text

    private func beginText(at point: CGPoint) {
        let fontSize = model.textPixelSize * displayScale
        let field = NSTextField(string: "")
        field.font = NSFont.systemFont(ofSize: fontSize, weight: model.textWeight.font)
        textWeight = model.textWeight.font
        field.textColor = model.color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.placeholderString = "Type, then Return"
        let origin = toView(point)
        // NSTextField insets its text by ~2pt; shift so typed text lands where it will be drawn.
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(imageRect.maxX - origin.x, 80),
                             height: ceil(fontSize * 1.35))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOrigin = point
        cancelText = false
    }

    /// Turns the text being typed into an annotation (or drops it if empty / cancelled).
    func commitText() {
        guard let field = textField, let origin = textOrigin else { return }
        textField = nil
        textOrigin = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        if !cancelText, !text.isEmpty {
            model.add(.text(text, at: origin, color: field.textColor ?? model.color,
                            fontSize: model.textPixelSize, weight: textWeight))
        }
        window?.makeFirstResponder(self)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText = true
            commitText()
            return true
        }
        return false
    }

    var isEditingText: Bool { textField != nil }
}
