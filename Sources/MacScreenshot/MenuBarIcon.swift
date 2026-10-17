import AppKit

/// The app icon's glyph (viewfinder corners + camera) without its background, as a template
/// image so macOS tints it for light/dark menu bars. Same geometry as scripts/make-icon.swift,
/// whose 1024-unit artwork spans x/y 192...832.
enum MenuBarIcon {
    static func make(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let origin: CGFloat = 192, span: CGFloat = 640
            let k = rect.width / span
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -origin, y: -origin)

            ctx.setStrokeColor(.black)
            ctx.setFillColor(.black)

            // Viewfinder corners.
            ctx.setLineWidth(46)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let lo: CGFloat = 238, hi: CGFloat = 1024 - 238, arm: CGFloat = 116
            for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                ctx.move(to: CGPoint(x: x, y: y + dy * arm))
                ctx.addLine(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
            }
            ctx.strokePath()

            // Camera body + hump, then the lens ring cut out of it.
            let camera = CGRect(x: 342, y: 382, width: 340, height: 236)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 436, y: 590, width: 152, height: 70), cornerWidth: 26, cornerHeight: 26, transform: nil))
            ctx.addPath(CGPath(roundedRect: camera, cornerWidth: 52, cornerHeight: 52, transform: nil))
            ctx.fillPath()

            let lens = CGPoint(x: camera.midX, y: camera.midY - 4)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: lens.x - 84, y: lens.y - 84, width: 168, height: 168))
            ctx.setBlendMode(.normal)
            ctx.fillEllipse(in: CGRect(x: lens.x - 52, y: lens.y - 52, width: 104, height: 104))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacScreenshot"
        return image
    }
}
