// Renders the MacScreenshot app icon (1024x1024 PNG): a white camera inside
// viewfinder corners on a dark rounded square. Drawn from scratch (no SF Symbols,
// whose license doesn't allow use in app icons).
// Usage: swift scripts/make-icon.swift <output.png> [--light | --glyph]
//   default: white glyph on a dark tile (macOS 14/15 .icns)
//   --light: dark glyph on a light tile (preview only)
//   --glyph: white glyph alone on a transparent, full-bleed canvas: the foreground layer of
//            Resources/AppIcon.icon, where macOS 26 draws the shape and light/dark background.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let light = CommandLine.arguments.contains("--light")
let glyphOnly = CommandLine.arguments.contains("--glyph")

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS icon grid: 824 pt body centred in 1024, corner radius ~185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

if !glyphOnly {
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4))
ctx.addPath(bodyPath)
ctx.setFillColor(color(light ? 0xF2F2F7 : 0x1C1C1E))
ctx.fillPath()
ctx.restoreGState()

// Dark body with a subtle top-to-bottom sheen.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let tile = light ? [color(0xFFFFFF), color(0xF2F2F7), color(0xDCDCE2)] : [color(0x3A3A3C), color(0x1C1C1E), color(0x0E0E10)]
let gradient = CGGradient(colorsSpace: space, colors: tile as CFArray,
                          locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
ctx.restoreGState()
} else {
    // The system shape fills the whole canvas, so scale the glyph up from the 824 tile
    // to span ~70% of 1024 (192...832 -> 152...872).
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: 1.125, y: 1.125)
    ctx.translateBy(x: -512, y: -512)
}

// Glyph colour and the tile colour used to cut the lens ring.
let white = light ? color(0x1C1C1E) : color(0xFFFFFF)
let dark = light ? color(0xF2F2F7) : color(0x1C1C1E)

// Viewfinder corner brackets.
ctx.setStrokeColor(white)
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let inset: CGFloat = 238, arm: CGFloat = 116
let lo = inset, hi = size - inset
for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.move(to: CGPoint(x: x, y: y + dy * arm))
    ctx.addLine(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x + dx * arm, y: y))
}
ctx.strokePath()

// Camera: body with a viewfinder hump on top, and a ringed lens.
let camera = CGRect(x: 342, y: 382, width: 340, height: 236)
let hump = CGRect(x: 436, y: 590, width: 152, height: 70)
ctx.setFillColor(white)
ctx.addPath(CGPath(roundedRect: hump, cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: camera, cornerWidth: 52, cornerHeight: 52, transform: nil))
ctx.fillPath()

let lens = CGPoint(x: camera.midX, y: camera.midY - 4)
ctx.setFillColor(dark)
if glyphOnly { ctx.setBlendMode(.clear) }
ctx.fillEllipse(in: CGRect(x: lens.x - 84, y: lens.y - 84, width: 168, height: 168))
ctx.setBlendMode(.normal)
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: lens.x - 52, y: lens.y - 52, width: 104, height: 104))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
