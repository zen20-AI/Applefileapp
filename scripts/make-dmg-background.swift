// Draws the DMG window background: black/mint, "drag Petal to Applications" with an arrow.
// Usage: swift scripts/make-dmg-background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
let output = URL(fileURLWithPath: args.count > 1 ? args[1] : "background.png")
let scale = CGFloat(args.count > 2 ? Double(args[2]) ?? 1 : 1)
let size = CGSize(width: 660, height: 400)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

let mint = NSColor(red: 0.42, green: 0.92, blue: 0.78, alpha: 1)
let background = NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.04, alpha: 1)])!
background.draw(in: CGRect(origin: .zero, size: size), angle: -90)
let bloom = NSGradient(colors: [mint.withAlphaComponent(0.22), mint.withAlphaComponent(0)])!
bloom.draw(fromCenter: CGPoint(x: 330, y: 200), radius: 0, toCenter: CGPoint(x: 330, y: 200), radius: 330, options: [])

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributed = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ])
    attributed.draw(in: CGRect(x: 0, y: y, width: size == 0 ? 0 : 660, height: size * 1.6))
}

// Icons sit at (170, 190) and (490, 190) in Finder coordinates (top-left origin) → y = 400 - 190.
text("Drag Petal to Applications", size: 22, weight: .semibold, color: .white, y: 318)
text("ลาก Petal ไปไว้ในโฟลเดอร์ Applications", size: 13, weight: .regular, color: NSColor(white: 1, alpha: 0.6), y: 296)

// Arrow between the icons
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 262, y: 210))
arrow.curve(to: CGPoint(x: 392, y: 210), controlPoint1: CGPoint(x: 300, y: 236), controlPoint2: CGPoint(x: 354, y: 236))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
mint.setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: CGPoint(x: 378, y: 224))
head.line(to: CGPoint(x: 394, y: 209))
head.line(to: CGPoint(x: 374, y: 204))
head.lineWidth = 3
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

text("Blocked on first launch? System Settings → Privacy & Security → Open Anyway", size: 11, weight: .regular,
     color: NSColor(white: 1, alpha: 0.45), y: 40)
text("เปิดไม่ได้ครั้งแรก? System Settings → Privacy & Security → Open Anyway", size: 11, weight: .regular,
     color: NSColor(white: 1, alpha: 0.45), y: 20)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
