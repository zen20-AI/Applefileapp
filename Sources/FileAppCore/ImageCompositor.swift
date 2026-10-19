import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A freehand stroke in normalized (0...1, top-left origin) image coordinates.
public struct AnnotationStroke {
    public var points: [CGPoint]
    public var color: CGColor
    /// Line width as a fraction of the image's shorter side.
    public var width: CGFloat
    public var isHighlighter: Bool

    public init(points: [CGPoint], color: CGColor, width: CGFloat, isHighlighter: Bool) {
        self.points = points
        self.color = color
        self.width = width
        self.isHighlighter = isHighlighter
    }
}

public enum RedactionStyle: String, CaseIterable, Identifiable {
    case black, pixelate

    public var id: String { rawValue }
    public var label: String { self == .black ? "Black Box" : "Pixelate" }
}

public struct Adjustments: Equatable {
    public var brightness: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var exposure: Double = 0
    public var quarterTurns: Int = 0
    public var flipped = false

    public init() {}
}

/// Pixel operations behind the Crop, Edit, Annotate and Redact tools.
public enum ImageCompositor {
    static let ciContext = CIContext(options: [.workingColorSpace: ImageFile.sRGB])

    public static func crop(_ image: CGImage, to normalized: CGRect) -> CGImage? {
        let rect = CropMath.pixelRect(normalized, imageSize: CGSize(width: image.width, height: image.height))
        return image.cropping(to: rect)
    }

    public static func adjust(_ image: CGImage, _ adjustments: Adjustments) -> CGImage? {
        var output = CIImage(cgImage: image)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: adjustments.brightness,
                kCIInputContrastKey: adjustments.contrast,
                kCIInputSaturationKey: adjustments.saturation,
            ])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustments.exposure])
        if adjustments.flipped {
            output = output.oriented(.upMirrored)
        }
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let turns = ((adjustments.quarterTurns % 4) + 4) % 4
        output = output.oriented(orientations[turns])
        return ciContext.createCGImage(output, from: output.extent)
    }

    public static func annotate(_ image: CGImage, strokes: [AnnotationStroke]) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard let ctx = ImageFile.makeContext(width: image.width, height: image.height) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        flipToTopLeft(ctx, height: height)

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where !stroke.points.isEmpty {
            ctx.saveGState()
            if stroke.isHighlighter { ctx.setBlendMode(.multiply) }
            ctx.setStrokeColor(stroke.isHighlighter ? stroke.color.copy(alpha: 0.4) ?? stroke.color : stroke.color)
            ctx.setLineWidth(stroke.width * min(width, height))
            let points = stroke.points.map { CGPoint(x: $0.x * width, y: $0.y * height) }
            ctx.move(to: points[0])
            if points.count == 1 {
                ctx.addLine(to: points[0])
            } else {
                for point in points.dropFirst() { ctx.addLine(to: point) }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    public static func redact(_ image: CGImage, rects: [CGRect], style: RedactionStyle) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard let ctx = ImageFile.makeContext(width: image.width, height: image.height) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: bounds)

        // Convert normalized top-left rects into bottom-left pixel rects.
        let pixelRects = rects.map {
            CGRect(x: $0.minX * width, y: (1 - $0.maxY) * height, width: $0.width * width, height: $0.height * height)
        }

        switch style {
        case .black:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(pixelRects)
        case .pixelate:
            let blockSize = max(min(width, height) / 40, 8)
            let input = CIImage(cgImage: image)
            let pixelated = input
                .clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: blockSize, kCIInputCenterKey: CIVector(x: 0, y: 0)])
                .cropped(to: input.extent)
            guard let mosaic = ciContext.createCGImage(pixelated, from: input.extent) else { return nil }
            ctx.saveGState()
            ctx.clip(to: pixelRects)
            ctx.draw(mosaic, in: bounds)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    static func flipToTopLeft(_ ctx: CGContext, height: CGFloat) {
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }
}
