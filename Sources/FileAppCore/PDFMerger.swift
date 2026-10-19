import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Combines images and PDFs, in order, into a single PDF.
public enum PDFMerger {
    public static func canMerge(_ url: URL) -> Bool {
        switch FileKind(url: url) {
        case .image, .pdf: return true
        default: return false
        }
    }

    /// Writes "<first name> Merged.pdf" (or into `OutputNaming.destinationDirectory`).
    public static func merge(_ urls: [URL]) throws -> URL {
        let inputs = urls.filter(canMerge)
        guard let first = inputs.first else { throw FileAppError.unsupported("Merging these files") }

        let merged = PDFDocument()
        for url in inputs {
            switch FileKind(url: url) {
            case .pdf:
                guard let document = PDFDocument(url: url) else { throw FileAppError.unreadable(url) }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) }
                }
            default:
                let image = try ImageFile.load(url)
                guard let page = PDFPage(image: NSImage(cgImage: image, size: image.size)) else {
                    throw FileAppError.unreadable(url)
                }
                merged.insert(page, at: merged.pageCount)
            }
        }

        let output = OutputNaming.url(for: first, suffix: "Merged", fileExtension: "pdf")
        guard merged.pageCount > 0, merged.write(to: output) else { throw FileAppError.writeFailed(output) }
        return output
    }
}
