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
    /// When set, `compress(_:)` without a quality aims for a file no bigger than this.
    nonisolated(unsafe) public static var defaultLimit: Int64?

    /// "Under 500 KB / 1 MB / …" choices (binary units, so they also pass sites that count 1 MB as 1,000,000 bytes).
    public static let sizeLimits: [Int64] = [200, 500, 1024, 2048, 5120, 10240].map { Int64($0) * 1024 }

    public static func canCompress(_ url: URL) -> Bool {
        switch FileKind(url: url) {
        case .image, .pdf: return true
        default: return false
        }
    }

    /// Writes a smaller "<name> Compressed" copy; throws `noSavings` (and removes it) if it isn't smaller.
    public static func compress(_ url: URL, quality: Double? = nil) throws -> CompressionResult {
        if quality == nil, let limit = defaultLimit { return try compress(url, under: limit) }
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

    // MARK: - Size limit

    /// Writes a "<name> Compressed" copy no bigger than `limit` bytes, keeping as much quality as fits.
    /// Images lower JPEG quality first, then shrink; PDFs are optimized, then turned into page images if needed.
    public static func compress(_ url: URL, under limit: Int64) throws -> CompressionResult {
        let originalSize = url.fileSize
        guard originalSize > limit else { throw FileAppError.alreadyUnder(limit) }

        let data: Data
        let fileExtension: String
        switch FileKind(url: url) {
        case .image:
            data = try imageData(url, under: limit)
            fileExtension = "jpg"
        case .pdf:
            data = try pdfData(url, under: limit)
            fileExtension = "pdf"
        default:
            throw FileAppError.unsupported("Compressing \(url.pathExtension.uppercased())")
        }
        let output = OutputNaming.url(for: url, suffix: "Compressed", fileExtension: fileExtension)
        do { try data.write(to: output) } catch { throw FileAppError.writeFailed(output) }
        return CompressionResult(output: output, originalSize: originalSize, compressedSize: Int64(data.count))
    }

    /// JPEG (what upload forms accept): the best quality that fits, shrinking the image only when even
    /// low quality is too big.
    static func imageData(_ url: URL, under limit: Int64) throws -> Data {
        var image = try ImageFile.load(url)
        let minQuality = 0.3
        for _ in 0..<12 {
            let smallest = try ImageFile.data(image, type: .jpeg, quality: minQuality)
            if smallest.count <= limit {
                if let top = try? ImageFile.data(image, type: .jpeg, quality: 0.92), top.count <= limit { return top }
                // Highest quality that still fits.
                var best = smallest
                var low = minQuality, high = 0.92
                for _ in 0..<6 {
                    let mid = (low + high) / 2
                    let data = try ImageFile.data(image, type: .jpeg, quality: mid)
                    if data.count <= limit { best = data; low = mid } else { high = mid }
                }
                return best
            }
            // Bytes scale with pixel count: shrink by the square root of the overshoot (a little extra to converge).
            let scale = min(0.9, max(0.35, (Double(limit) / Double(smallest.count)).squareRoot() * 0.95))
            let size = CGSize(width: (Double(image.width) * scale).rounded(), height: (Double(image.height) * scale).rounded())
            guard max(size.width, size.height) >= 64, let smaller = Resizer.resize(image, to: size) else { break }
            image = smaller
        }
        throw FileAppError.cannotReach(limit)
    }

    /// PDFKit's optimizer first (keeps text selectable); then pages as JPEG images at falling resolution.
    static func pdfData(_ url: URL, under limit: Int64) throws -> Data {
        if let document = PDFDocument(url: url), !document.isLocked,
           let data = document.dataRepresentation(options: [
               PDFDocumentWriteOption.saveImagesAsJPEGOption: true,
               PDFDocumentWriteOption.optimizeImagesForScreenOption: true,
           ]), data.count <= limit {
            return data
        }
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted || document.isUnlocked else {
            throw FileAppError.unreadable(url)
        }
        let steps: [(dpi: CGFloat, quality: Double)] = [
            (150, 0.75), (150, 0.6), (120, 0.55), (110, 0.45), (96, 0.4), (80, 0.35), (72, 0.3), (60, 0.25), (50, 0.2),
        ]
        for step in steps {
            let data = try rasterized(document, dpi: step.dpi, quality: step.quality)
            if data.count <= limit { return data }
        }
        throw FileAppError.cannotReach(limit)
    }

    /// Every page drawn to a JPEG at `dpi`, placed on a page of the original size.
    static func rasterized(_ document: CGPDFDocument, dpi: CGFloat, quality: Double) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw FileAppError.unsupported("Writing PDF") }

        for number in 1...max(document.numberOfPages, 1) {
            guard let page = document.page(at: number) else { continue }
            let crop = page.getBoxRect(.cropBox)
            let size = page.rotationAngle % 180 != 0 ? CGSize(width: crop.height, height: crop.width) : crop.size
            var mediaBox = CGRect(origin: .zero, size: size)
            let pixels = CGSize(width: max(1, (size.width * dpi / 72).rounded()), height: max(1, (size.height * dpi / 72).rounded()))
            guard let bitmap = ImageFile.makeContext(width: Int(pixels.width), height: Int(pixels.height)) else { continue }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(origin: .zero, size: pixels))
            bitmap.interpolationQuality = .high
            bitmap.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pixels), rotate: 0, preserveAspectRatio: true))
            bitmap.drawPDFPage(page)
            guard let image = bitmap.makeImage() else { continue }
            // A JPEG-backed CGImage is embedded as-is (DCT), so the PDF holds exactly these bytes.
            let jpeg = try ImageFile.data(image, type: .jpeg, quality: quality)
            guard let provider = CGDataProvider(data: jpeg as CFData),
                  let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { continue }

            let info = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)]
            pdf.beginPDFPage(info as CFDictionary)
            pdf.draw(embedded, in: mediaBox)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }
}
