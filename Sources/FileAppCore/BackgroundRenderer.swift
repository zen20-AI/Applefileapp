import CoreGraphics
import Foundation

public enum BackgroundFill {
    /// Linear gradient; `angle` in degrees, 0 = left → right, 90 = bottom → top.
    case gradient([CGColor], angle: Double)
    case solid(CGColor)
    case image(CGImage)
}

public enum CanvasRatio: String, CaseIterable, Identifiable {
    case auto, square, wide, portrait

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .portrait: return "4:5"
        }
    }

    public var value: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .portrait: return 4.0 / 5.0
        }
    }
}

public struct BackgroundOptions {
    public var fill: BackgroundFill
    /// All lengths are in pixels of the full-resolution source image.
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var shadow: CGFloat
    public var ratio: CanvasRatio

    public init(fill: BackgroundFill, padding: CGFloat, cornerRadius: CGFloat, shadow: CGFloat, ratio: CanvasRatio) {
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.ratio = ratio
    }
}

/// Places an image on a padded, styled canvas ("Add BG").
public enum BackgroundRenderer {
    public static func canvasSize(for imageSize: CGSize, padding: CGFloat, ratio: CGFloat?) -> CGSize {
        var size = CGSize(width: imageSize.width + 2 * padding, height: imageSize.height + 2 * padding)
        guard let ratio else { return size }
        if size.width / size.height > ratio {
            size.height = size.width / ratio
        } else {
            size.width = size.height * ratio
        }
        return size
    }

    /// `scale` shrinks the lengths in `options` when rendering a downsampled preview.
    public static func render(_ image: CGImage, options: BackgroundOptions, scale: CGFloat = 1) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvas = canvasSize(for: imageSize, padding: options.padding * scale, ratio: options.ratio.value)
        let width = Int(canvas.width.rounded()), height = Int(canvas.height.rounded())
        guard let ctx = ImageFile.makeContext(width: width, height: height) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        drawFill(options.fill, in: bounds, ctx: ctx)

        let imageRect = CGRect(
            x: (bounds.width - imageSize.width) / 2,
            y: (bounds.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height)
        let radius = min(options.cornerRadius * scale, min(imageSize.width, imageSize.height) / 2)
        let shape = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if options.shadow > 0 {
            let blur = options.shadow * scale
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -blur * 0.4), blur: blur, color: CGColor(gray: 0, alpha: 0.35))
            ctx.addPath(shape)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func drawFill(_ fill: BackgroundFill, in bounds: CGRect, ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color)
            ctx.fill(bounds)

        case .gradient(let colors, let angle):
            guard let gradient = CGGradient(colorsSpace: ImageFile.sRGB, colors: colors as CFArray, locations: nil) else { return }
            let radians = angle * .pi / 180
            let dx = CGFloat(cos(radians)), dy = CGFloat(sin(radians))
            let half = (abs(dx) * bounds.width + abs(dy) * bounds.height) / 2
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: center.x - dx * half, y: center.y - dy * half),
                end: CGPoint(x: center.x + dx * half, y: center.y + dy * half),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        case .image(let background):
            // Aspect-fill.
            let size = CGSize(width: background.width, height: background.height)
            let scale = max(bounds.width / size.width, bounds.height / size.height)
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            ctx.draw(background, in: CGRect(
                x: (bounds.width - drawSize.width) / 2,
                y: (bounds.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height))
        }
    }
}
