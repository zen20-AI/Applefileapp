// Draws Petal's 1024 × 1024 app icon: smoky glass petals and a mint petal around an orb on a black tile.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// MARK: Tile (macOS grid: 824 pt rounded square with a soft drop shadow)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0, 0, 0, 0.4))
ctx.addPath(tilePath)
ctx.setFillColor(color(0.06, 0.07, 0.07))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let tileGradient = CGGradient(colorsSpace: sRGB, colors: [
    color(0.17, 0.19, 0.19), color(0.08, 0.09, 0.09), color(0.02, 0.03, 0.03),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 300, y: tile.maxY), end: CGPoint(x: 724, y: tile.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Mint glow behind the ring.
let bloom = CGGradient(colorsSpace: sRGB, colors: [color(0.25, 0.95, 0.75, 0.30), color(0.25, 0.95, 0.75, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
ctx.restoreGState()

// MARK: Petals — separate rounded glass pieces with even gaps

let center = CGPoint(x: 512, y: 512)
let count = 6
let inner: CGFloat = 168, outer: CGFloat = 330
let rounding: CGFloat = 46, spacing: CGFloat = 30

func petalPath(_ index: Int) -> CGPath {
    // Core sector, inset so that stroking it by `rounding` gives rounded, evenly spaced petals.
    let step = 2 * CGFloat.pi / CGFloat(count)
    let start = CGFloat.pi / 2 - step / 2 + CGFloat(index) * step
    let end = start + step
    let edge = spacing / 2 + rounding / 2
    let r1 = inner + rounding / 2, r2 = outer - rounding / 2
    let path = CGMutablePath()
    path.addArc(center: center, radius: r2, startAngle: start + asin(edge / r2), endAngle: end - asin(edge / r2), clockwise: false)
    path.addArc(center: center, radius: r1, startAngle: end - asin(edge / r1), endAngle: start + asin(edge / r1), clockwise: true)
    path.closeSubpath()
    // Core ∪ its rounded stroke = one smooth outline (CGPath boolean ops, macOS 14+).
    return path.union(path.copy(strokingWithWidth: rounding, lineCap: .round, lineJoin: .round, miterLimit: 10))
}

for index in 0..<count {
    let highlighted = index == 0 // top petal
    let outline = petalPath(index)
    let bounds = outline.boundingBoxOfPath

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: highlighted ? color(0.15, 0.9, 0.7, 0.55) : color(0, 0, 0, 0.5))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(outline)
    ctx.setFillColor(color(1, 1, 1, 1))
    ctx.fillPath(using: .winding)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Body: frosted white, or the accent for the highlighted petal
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip(using: .winding)
    let body = highlighted
        ? CGGradient(colorsSpace: sRGB, colors: [color(0.50, 0.96, 0.82), color(0.10, 0.74, 0.60)] as CFArray, locations: [0, 1])!
        : CGGradient(colorsSpace: sRGB, colors: [color(0.32, 0.35, 0.35), color(0.17, 0.19, 0.19)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(body, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
    ctx.restoreGState()

    // Glass rim highlight
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.setStrokeColor(color(1, 1, 1, highlighted ? 0.5 : 0.22))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: Hub orb with a document glyph

let hubRadius: CGFloat = 128
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0, 0, 0, 0.5))
ctx.setFillColor(color(1, 1, 1))
ctx.fillEllipse(in: CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2))
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2))
ctx.clip()
let orb = CGGradient(colorsSpace: sRGB, colors: [color(0.26, 0.29, 0.29), color(0.11, 0.12, 0.12)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(orb, start: CGPoint(x: 512, y: center.y + hubRadius), end: CGPoint(x: 512, y: center.y - hubRadius), options: [])
ctx.restoreGState()

// Document glyph with folded corner
let doc = CGRect(x: center.x - 44, y: center.y - 58, width: 88, height: 116)
let fold: CGFloat = 30
let page = CGMutablePath()
page.move(to: CGPoint(x: doc.minX, y: doc.minY + 14))
page.addArc(tangent1End: CGPoint(x: doc.minX, y: doc.minY), tangent2End: CGPoint(x: doc.maxX, y: doc.minY), radius: 14)
page.addArc(tangent1End: CGPoint(x: doc.maxX, y: doc.minY), tangent2End: CGPoint(x: doc.maxX, y: doc.maxY), radius: 14)
page.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
page.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
page.addArc(tangent1End: CGPoint(x: doc.minX, y: doc.maxY), tangent2End: CGPoint(x: doc.minX, y: doc.minY), radius: 14)
page.closeSubpath()
ctx.saveGState()
ctx.addPath(page)
ctx.clip()
let ink = CGGradient(colorsSpace: sRGB, colors: [color(0.50, 0.96, 0.82), color(0.10, 0.74, 0.60)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ink, start: CGPoint(x: 512, y: doc.maxY), end: CGPoint(x: 512, y: doc.minY), options: [])
ctx.restoreGState()
// Folded corner
let corner = CGMutablePath()
corner.move(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
corner.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold + 6))
corner.addQuadCurve(to: CGPoint(x: doc.maxX - fold + 6, y: doc.maxY - fold), control: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold))
corner.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
corner.closeSubpath()
ctx.addPath(corner)
ctx.setFillColor(color(0.75, 0.98, 0.90))
ctx.fillPath()

// Glass rim on the orb.
ctx.addEllipse(in: CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2))
ctx.setStrokeColor(color(1, 1, 1, 0.22))
ctx.setLineWidth(4)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
