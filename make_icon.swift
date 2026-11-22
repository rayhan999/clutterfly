// Draws the 1024px app icon PNG: a warm molehill under a sky, with sparkles (clean!).
// Pure shapes, no SF Symbols (Apple's licence doesn't allow them in app icons).
// Run: swiftc make_icon.swift -o /tmp/mk && /tmp/mk icon.png   (build.sh notes how to make AppIcon.icns)
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ c: [CGColor]) -> CGGradient { CGGradient(colorsSpace: nil, colors: c as CFArray, locations: nil)! }

/// Four-point sparkle centred on c with radius r.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath(), k = r * 0.14
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    return p
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

    // Sky
    ctx.drawLinearGradient(gradient([rgb(0x5B8CFF), rgb(0x7B5CFA), rgb(0x9B4DE0)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Glow behind the big sparkle
    let sc = CGPoint(x: 512, y: 725)
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]),
                           startCenter: sc, startRadius: 0, endCenter: sc, endRadius: 260, options: [])

    // Back hill (soft, for depth)
    let back = CGMutablePath()
    back.move(to: CGPoint(x: 60, y: 60)); back.addLine(to: CGPoint(x: 60, y: 380))
    back.addCurve(to: CGPoint(x: 964, y: 330), control1: CGPoint(x: 300, y: 470), control2: CGPoint(x: 700, y: 420))
    back.addLine(to: CGPoint(x: 964, y: 60)); back.closeSubpath()
    ctx.addPath(back); ctx.setFillColor(rgb(0xFFFFFF, 0.14)); ctx.fillPath()

    // The molehill
    let hill = CGMutablePath()
    hill.move(to: CGPoint(x: 60, y: 60)); hill.addLine(to: CGPoint(x: 60, y: 180))
    hill.addCurve(to: CGPoint(x: 512, y: 520), control1: CGPoint(x: 260, y: 250), control2: CGPoint(x: 300, y: 520))
    hill.addCurve(to: CGPoint(x: 964, y: 180), control1: CGPoint(x: 724, y: 520), control2: CGPoint(x: 764, y: 250))
    hill.addLine(to: CGPoint(x: 964, y: 60)); hill.closeSubpath()
    ctx.saveGState()
    ctx.addPath(hill); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFC15E), rgb(0xFF7A59), rgb(0xF2456E)]),
                           start: CGPoint(x: 512, y: 520), end: CGPoint(x: 512, y: 100), options: [])
    // Little burrow hole near the top
    ctx.setFillColor(rgb(0x5A1838, 0.55))
    ctx.fillEllipse(in: CGRect(x: 457, y: 452, width: 110, height: 38))
    ctx.restoreGState()

    // Shine along the hill's left shoulder
    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: 308, y: 346))
    shine.addQuadCurve(to: CGPoint(x: 417, y: 454), control: CGPoint(x: 353, y: 412))
    ctx.addPath(shine); ctx.setStrokeColor(rgb(0xFFFFFF, 0.5)); ctx.setLineWidth(18); ctx.setLineCap(.round); ctx.strokePath()

    // Sparkles
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.addPath(sparkle(sc, 140)); ctx.fillPath()
    ctx.addPath(sparkle(CGPoint(x: 712, y: 800), 58)); ctx.fillPath()
    ctx.setFillColor(rgb(0xFFFFFF, 0.85))
    ctx.addPath(sparkle(CGPoint(x: 318, y: 610), 42)); ctx.fillPath()

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
