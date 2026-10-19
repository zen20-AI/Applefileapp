import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// How a batch of images should be scaled.
public enum ResizeMode: Equatable {
    /// Scale both sides by a factor (0.5 = half size).
    case percent(Double)
    /// Fit inside a square of this many pixels, keeping the aspect ratio. Never upscales.
    case maxSide(Int)
}

public enum Resizer {
    public static func targetSize(for size: CGSize, mode: ResizeMode) -> CGSize {
        let scale: CGFloat
        switch mode {
        case .percent(let factor):
            scale = CGFloat(max(factor, 0.01))
        case .maxSide(let side):
            scale = min(1, CGFloat(side) / max(size.width, size.height, 1))
        }
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    public static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = ImageFile.makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// Writes "<name> Resized.<ext>" in the source's format (PNG if it can't be encoded).
    public static func resize(_ url: URL, mode: ResizeMode) throws -> URL {
        let image = try ImageFile.load(url)
        let size = targetSize(for: image.size, mode: mode)
        guard let resized = resize(image, to: size) else { throw FileAppError.writeFailed(url) }
        let type = url.contentType.flatMap { ImageFile.canWrite($0) ? $0 : nil } ?? .png
        let output = OutputNaming.url(for: url, suffix: "Resized", fileExtension: type.preferredFilenameExtension ?? "png")
        let lossy = [UTType.jpeg, .heic, .heif].contains { type.conforms(to: $0) }
        try ImageFile.write(resized, to: output, type: type, quality: lossy ? Converter.lossyQuality : nil)
        return output
    }
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}
