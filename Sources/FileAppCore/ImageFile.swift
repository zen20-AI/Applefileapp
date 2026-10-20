import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileAppError: LocalizedError {
    case unreadable(URL)
    case unsupported(String)
    case writeFailed(URL)
    case noSavings
    case alreadyUnder(Int64)
    case cannotReach(Int64)

    public var errorDescription: String? {
        switch self {
        case .alreadyUnder(let limit): return String(localized: "Already under \(ByteFormatter.limit(limit))")
        case .cannotReach(let limit): return String(localized: "Couldn't get it under \(ByteFormatter.limit(limit))")
        case .unreadable(let url): return "Couldn't read \(url.lastPathComponent)"
        case .unsupported(let what): return "\(what) isn't supported on this Mac"
        case .writeFailed(let url): return "Couldn't write \(url.lastPathComponent)"
        case .noSavings: return "Already as small as it gets"
        }
    }
}

/// ImageIO helpers: orientation-correct loading, encoding, and metadata.
public enum ImageFile {
    public static let writableTypeIdentifiers: Set<String> =
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    public static func canWrite(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return writableTypeIdentifiers.contains(type.identifier)
    }

    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Loads the first frame with EXIF orientation applied, optionally downsampled.
    public static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw FileAppError.unreadable(url) }

        let fullSize = pixelSize(of: source).map { Int(max($0.width, $0.height)) } ?? 16384
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? fullSize, fullSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileAppError.unreadable(url)
        }
        return image
    }

    public static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Image properties (EXIF, GPS, TIFF, …) of the first frame.
    public static func properties(of url: URL) -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        return props
    }

    public static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double? = nil) throws {
        guard canWrite(type) else { throw FileAppError.unsupported("Saving \(type.preferredFilenameExtension?.uppercased() ?? type.identifier)") }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw FileAppError.writeFailed(url)
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        let needsOpaque = type.conforms(to: .jpeg) || type.conforms(to: .bmp)
        CGImageDestinationAddImage(destination, needsOpaque ? flattened(image) : image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileAppError.writeFailed(url) }
    }

    /// Encodes in memory, so callers can measure the size before writing.
    public static func data(_ image: CGImage, type: UTType, quality: Double? = nil) throws -> Data {
        guard canWrite(type) else { throw FileAppError.unsupported("Saving \(type.preferredFilenameExtension?.uppercased() ?? type.identifier)") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw FileAppError.unsupported("Saving \(type.identifier)")
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        let needsOpaque = type.conforms(to: .jpeg) || type.conforms(to: .bmp)
        CGImageDestinationAddImage(destination, needsOpaque ? flattened(image) : image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileAppError.unsupported("Saving \(type.identifier)") }
        return data as Data
    }

    /// Writes a pixel-identical copy without EXIF/GPS/TIFF/IPTC metadata.
    /// Pixels are re-encoded, which also bakes in the orientation.
    public static func writeWithoutMetadata(from url: URL, to output: URL) throws {
        let image = try load(url)
        let type = url.contentType.flatMap { canWrite($0) ? $0 : nil } ?? .png
        try write(image, to: output, type: type, quality: 0.95)
    }

    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Composites onto an opaque background for formats without transparency.
    public static func flattened(_ image: CGImage, background: CGColor = CGColor(gray: 1, alpha: 1)) -> CGImage {
        guard hasAlpha(image),
              let ctx = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(background)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    /// An 8-bit premultiplied sRGB bitmap context.
    public static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
