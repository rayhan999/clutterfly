// Draws the 1024px Clutterfly app icon: a colorful butterfly on a night sky.
// Pure shapes, no SF Symbols (Apple's licence doesn't allow them in app icons).
// Run: swiftc make_icon.swift -o /tmp/mk && /tmp/mk icon.png   (build.sh notes how to make AppIcon.icns)
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ c: [CGColor]) -> CGGradient { CGGradient(colorsSpace: nil, colors: c as CFArray, locations: nil)! }

/// Fills an ellipse (centre, size, rotation in degrees) with a top-to-bottom gradient.
func wing(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ deg: CGFloat, _ colors: [CGColor]) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: deg * .pi / 180)
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    ctx.addEllipse(in: r); ctx.clip()
    ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: -w / 2, y: h / 2), end: CGPoint(x: w / 2, y: -h / 2), options: [])
    ctx.setFillColor(rgb(0xFFFFFF, 0.28))  // soft highlight spot
    ctx.fillEllipse(in: CGRect(x: w * 0.02, y: -h * 0.05, width: w * 0.28, height: h * 0.32))
    ctx.restoreGState()
}

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)  // macOS icon grid
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0.3))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x2A1B5E), rgb(0x161033)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let mid = CGPoint(x: 512, y: 480)
    ctx.drawRadialGradient(gradient([rgb(0xFF5FA2, 0.35), rgb(0xFF5FA2, 0)]),
                           startCenter: mid, startRadius: 0, endCenter: mid, endRadius: 420, options: [])

    // A few twinkles
    ctx.setFillColor(rgb(0xFFFFFF, 0.7))
    for (x, y, r) in [(232.0, 790.0, 7.0), (808.0, 820.0, 9.0), (830.0, 300.0, 6.0), (196.0, 330.0, 8.0), (300.0, 210.0, 5.0)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    ctx.saveGState(); ctx.translateBy(x: 0, y: -62)  // centre the butterfly in the tile
    // Wings: right side, then mirrored for the left
    for side: CGFloat in [1, -1] {
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 0); ctx.scaleBy(x: side, y: 1); ctx.translateBy(x: -512, y: 0)
        wing(ctx, CGPoint(x: 646, y: 440), 250, 190, -42, [rgb(0x8B5CF6), rgb(0x3B82F6)])  // lower
        wing(ctx, CGPoint(x: 680, y: 646), 360, 262, 38, [rgb(0xFFB547), rgb(0xFF5FA2)])   // upper
        ctx.restoreGState()
    }

    // Body and antennae
    ctx.addPath(CGPath(roundedRect: CGRect(x: 492, y: 372, width: 40, height: 340), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(rgb(0xFFF4E6)); ctx.fillPath()
    ctx.setStrokeColor(rgb(0xFFF4E6)); ctx.setLineWidth(14); ctx.setLineCap(.round)
    for side: CGFloat in [1, -1] {
        ctx.move(to: CGPoint(x: 512 + side * 6, y: 700))
        ctx.addQuadCurve(to: CGPoint(x: 512 + side * 92, y: 846), control: CGPoint(x: 512 + side * 20, y: 820))
        ctx.strokePath()
        ctx.setFillColor(rgb(0xFFF4E6))
        ctx.fillEllipse(in: CGRect(x: 512 + side * 92 - 18, y: 846 - 18, width: 36, height: 36))
    }

    ctx.restoreGState()
    ctx.restoreGState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: CGRect(x: 0, y: 0, width: S, height: S))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
