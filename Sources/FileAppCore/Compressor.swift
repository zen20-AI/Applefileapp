import Foundation
import PDFKit
import UniformTypeIdentifiers

public struct CompressionResult {
    public let output: URL
    public let originalSize: Int64
    public let compressedSize: Int64

    public var savedFraction: Double {
        originalSize > 0 ? 1 - Double(compressedSize) / Double(originalSize) : 0
    }
}

public enum Compressor {
    /// Default quality used by `compress(_:)`.
    nonisolated(unsafe) public static var defaultQuality: Double = 0.6

    public static func canCompress(_ url: URL) -> Bool {
        switch FileKind(url: url) {
        case .image, .pdf: return true
        default: return false
        }
    }

    /// Writes a smaller "<name> Compressed" copy; throws `noSavings` (and removes it) if it isn't smaller.
    public static func compress(_ url: URL, quality: Double? = nil) throws -> CompressionResult {
        let originalSize = url.fileSize
        let output: URL

        switch FileKind(url: url) {
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw FileAppError.unreadable(url) }
            output = OutputNaming.url(for: url, suffix: "Compressed", fileExtension: "pdf")
            let options: [PDFDocumentWriteOption: Any] = [
                .saveImagesAsJPEGOption: true,
                .optimizeImagesForScreenOption: true,
            ]
            guard document.write(to: output, withOptions: options) else { throw FileAppError.writeFailed(output) }

        case .image:
            let image = try ImageFile.load(url)
            let type = lossyType(for: url, hasAlpha: ImageFile.hasAlpha(image))
            output = OutputNaming.url(for: url, suffix: "Compressed", fileExtension: type.preferredFilenameExtension ?? "jpg")
            try ImageFile.write(image, to: output, type: type, quality: quality ?? defaultQuality)

        default:
            throw FileAppError.unsupported("Compressing \(url.pathExtension.uppercased())")
        }

        let compressedSize = output.fileSize
        if compressedSize >= originalSize {
            try? FileManager.default.removeItem(at: output)
            throw FileAppError.noSavings
        }
        return CompressionResult(output: output, originalSize: originalSize, compressedSize: compressedSize)
    }

    /// Keeps lossy formats as they are; lossless ones go to HEIC (if transparent) or JPEG.
    static func lossyType(for url: URL, hasAlpha: Bool) -> UTType {
        let lossy = [UTType.jpeg, .heic, .heif, UTType("public.avif")].compactMap { $0 }
        if let source = url.contentType, lossy.contains(where: { source.conforms(to: $0) }), ImageFile.canWrite(source) {
            return source
        }
        if hasAlpha, ImageFile.canWrite(.heic) { return .heic }
        return .jpeg
    }
}
