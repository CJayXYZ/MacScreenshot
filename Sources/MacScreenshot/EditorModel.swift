import AppKit
import Combine

enum EditorTool: String, CaseIterable, Identifiable {
    case crop, arrow, box, circle, text, highlight

    var id: Self { self }

    var title: String {
        switch self {
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .circle: return "Circle"
        case .text: return "Text"
        case .highlight: return "Highlight"
        }
    }

    var symbol: String {
        switch self {
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .box: return "rectangle"
        case .circle: return "circle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        }
    }

    /// Single-key shortcut while the canvas has focus.
    var key: Character {
        switch self {
        case .crop: return "c"
        case .arrow: return "a"
        case .box: return "b"
        case .circle: return "o"
        case .text: return "t"
        case .highlight: return "h"
        }
    }

    /// Tools whose outline thickness can be chosen.
    var usesStroke: Bool { self == .arrow || self == .box || self == .circle }
}

enum StrokeWidth: String, CaseIterable, Identifiable {
    case thin = "Thin", medium = "Medium", thick = "Thick"

    var id: Self { self }

    /// Line width in points; multiplied by the image scale to get pixels.
    var points: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 4
        case .thick: return 7
        }
    }
}

enum TextWeight: String, CaseIterable, Identifiable {
    case regular = "Regular", bold = "Bold", heavy = "Heavy"

    var id: Self { self }

    var font: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .bold: return .bold
        case .heavy: return .black
        }
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small = "S", medium = "M", large = "L", extraLarge = "XL"

    var id: Self { self }

    /// Font size in points; multiplied by the image scale to get pixels.
    var points: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 20
        case .large: return 28
        case .extraLarge: return 40
        }
    }
}

/// One mark on the image. Coordinates are image pixels with a top-left origin.
enum Annotation {
    case arrow(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat)
    case box(CGRect, color: NSColor, width: CGFloat)
    case circle(CGRect, color: NSColor, width: CGFloat)
    case highlight(CGRect, color: NSColor)
    case text(String, at: CGPoint, color: NSColor, fontSize: CGFloat, weight: NSFont.Weight)
}

struct EditorDocument {
    var image: CGImage
    var annotations: [Annotation] = []
}

@MainActor
final class EditorModel: ObservableObject {
    static let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .black, .white]
    private static let maxUndo = 30

    @Published var tool: EditorTool = .arrow
    @Published var color: NSColor = .systemRed
    @Published var textSize: TextSize = .medium
    @Published var textWeight: TextWeight = .bold
    @Published var stroke: StrokeWidth = .medium
    @Published private(set) var document: EditorDocument
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Image pixels per point (2 for a Retina capture), read from the file's DPI.
    let scale: CGFloat

    private var undoStack: [EditorDocument] = []
    private var redoStack: [EditorDocument] = []

    init(image: CGImage, scale: CGFloat) {
        document = EditorDocument(image: image)
        self.scale = max(scale, 1)
    }

    var hasChanges: Bool { !undoStack.isEmpty }
    var lineWidth: CGFloat { stroke.points * scale }
    var textPixelSize: CGFloat { textSize.points * scale }

    func add(_ annotation: Annotation) {
        change { $0.annotations.append(annotation) }
    }

    /// Crops to `rect` (image pixels). Marks drawn so far are burned into the image first.
    func crop(to rect: CGRect) {
        let bounds = CGRect(x: 0, y: 0, width: document.image.width, height: document.image.height)
        let area = rect.integral.intersection(bounds)
        guard area.width >= 2, area.height >= 2,
              let cropped = EditorRenderer.flatten(document).cropping(to: area) else { return }
        change { $0 = EditorDocument(image: cropped) }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        updateFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        updateFlags()
    }

    private func change(_ edit: (inout EditorDocument) -> Void) {
        undoStack.append(document)
        if undoStack.count > Self.maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
        edit(&document)
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

/// Draws annotations, shared by the on-screen canvas and the saved file so they match exactly.
enum EditorRenderer {
    /// Draws into the current NSGraphicsContext, which must be flipped (top-left origin)
    /// and in image-pixel units.
    static func draw(_ annotations: [Annotation]) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for annotation in annotations {
            ctx.saveGState()
            switch annotation {
            case let .arrow(from, to, color, width):
                drawArrow(ctx, from: from, to: to, color: color.cgColor, width: width)
            case let .box(rect, color, width):
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(width)
                ctx.setLineJoin(.round)
                ctx.stroke(rect)
            case let .circle(rect, color, width):
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(width)
                ctx.strokeEllipse(in: rect)
            case let .highlight(rect, color):
                ctx.setBlendMode(.multiply)
                ctx.setFillColor(color.withAlphaComponent(0.4).cgColor)
                ctx.fill(rect)
            case let .text(string, point, color, fontSize, weight):
                NSAttributedString(string: string, attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                    .foregroundColor: color,
                ]).draw(at: point)
            }
            ctx.restoreGState()
        }
    }

    private static func drawArrow(_ ctx: CGContext, from: CGPoint, to: CGPoint, color: CGColor, width: CGFloat) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = max(width * 4.5, 14)
        let spread = CGFloat.pi / 7
        // Stop the shaft inside the head so the round cap doesn't poke through the tip.
        let shaftEnd = CGPoint(x: to.x - cos(angle) * head * 0.7, y: to.y - sin(angle) * head * 0.7)

        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.setFillColor(color)
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread)))
        ctx.addLine(to: CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread)))
        ctx.closePath()
        ctx.fillPath()
    }

    /// The image with all annotations burned in.
    static func flatten(_ document: EditorDocument) -> CGImage {
        guard !document.annotations.isEmpty else { return document.image }
        let image = document.image
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(document.annotations)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? image
    }
}
