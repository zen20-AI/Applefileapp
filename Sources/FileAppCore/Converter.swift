import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Format conversion for images, PDFs and text documents.
public enum Converter {
    /// Render resolution for PDF pages (a US Letter page becomes 2550 × 3300 px).
    nonisolated(unsafe) public static var pdfRenderDPI: CGFloat = 300

    /// Encoder quality (0…1) for lossy targets such as JPG and HEIC.
    nonisolated(unsafe) public static var lossyQuality: Double = 0.9

    public static func isAvailable(_ format: OutputFormat, for url: URL) -> Bool {
        if format.matches(url) { return false }
        switch FileKind(url: url) {
        case .image, .pdf:
            if format.isImage { return ImageFile.canWrite(format.utType) }
            if format == .pdf { return true }
            return FileKind(url: url) == .pdf // docx from PDF text
        case .document:
            return format == .pdf || format == .docx
        case .other:
            return false
        }
    }

    /// Converts one file and returns the files written (a multi-page PDF yields one image per page).
    public static func convert(_ url: URL, to format: OutputFormat) throws -> [URL] {
        guard isAvailable(format, for: url) else {
            throw FileAppError.unsupported("\(url.pathExtension.uppercased()) → \(format.label)")
        }
        switch (FileKind(url: url), format) {
        case (.image, .pdf):
            return [try imageToPDF(url)]
        case (.image, _):
            let output = OutputNaming.url(for: url, fileExtension: format.fileExtension)
            try ImageFile.write(try ImageFile.load(url), to: output, type: format.utType!, quality: format.isLossy ? lossyQuality : nil)
            return [output]
        case (.pdf, .docx):
            return [try pdfToDocx(url)]
        case (.pdf, _):
            return try pdfToImages(url, format: format)
        case (.document, .pdf):
            return [try documentToPDF(url)]
        case (.document, .docx):
            let output = OutputNaming.url(for: url, fileExtension: "docx")
            try writeDocx(try readDocument(url), to: output)
            return [output]
        default:
            throw FileAppError.unsupported(format.label)
        }
    }

    // MARK: - Images

    static func imageToPDF(_ url: URL) throws -> URL {
        let image = try ImageFile.load(url)
        let dpi = (ImageFile.properties(of: url)[kCGImagePropertyDPIWidth as String] as? Double).map { CGFloat($0) } ?? 72
        let scale = 72 / max(dpi, 1)
        var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let output = OutputNaming.url(for: url, fileExtension: "pdf")
        guard let ctx = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else { throw FileAppError.writeFailed(output) }
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: mediaBox)
        ctx.endPDFPage()
        ctx.closePDF()
        return output
    }

    // MARK: - PDF

    public static func renderPage(_ page: CGPDFPage, dpi: CGFloat? = nil) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let pointSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min((dpi ?? pdfRenderDPI) / 72, 12000 / max(pointSize.width, pointSize.height))
        let width = Int((pointSize.width * scale).rounded())
        let height = Int((pointSize.height * scale).rounded())
        guard let ctx = ImageFile.makeContext(width: width, height: height) else { return nil }

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pointSize), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    static func pdfToImages(_ url: URL, format: OutputFormat) throws -> [URL] {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else {
            throw FileAppError.unreadable(url)
        }
        let count = document.numberOfPages
        var outputs: [URL] = []
        for number in 1...count {
            guard let page = document.page(at: number), let image = renderPage(page) else { continue }
            let output = OutputNaming.url(for: url, suffix: count > 1 ? "Page \(number)" : nil, fileExtension: format.fileExtension)
            try ImageFile.write(image, to: output, type: format.utType!, quality: format.isLossy ? lossyQuality : nil)
            outputs.append(output)
        }
        if outputs.isEmpty { throw FileAppError.unreadable(url) }
        return outputs
    }

    static func pdfToDocx(_ url: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw FileAppError.unreadable(url) }
        let text = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let pageText = page.attributedString {
                text.append(pageText)
            } else if let string = page.string {
                text.append(NSAttributedString(string: string))
            }
            if index < document.pageCount - 1 {
                text.append(NSAttributedString(string: "\n\u{000C}"))
            }
        }
        let output = OutputNaming.url(for: url, fileExtension: "docx")
        try writeDocx(text, to: output)
        return output
    }

    // MARK: - Documents

    static func readDocument(_ url: URL) throws -> NSAttributedString {
        do {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw FileAppError.unreadable(url)
        }
    }

    static func writeDocx(_ text: NSAttributedString, to output: URL) throws {
        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: output, options: .atomic)
    }

    /// Lays a text document out on US Letter pages with 1" margins.
    static func documentToPDF(_ url: URL) throws -> URL {
        let text = try readDocument(url)
        let output = OutputNaming.url(for: url, fileExtension: "pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else { throw FileAppError.writeFailed(output) }

        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: mediaBox.insetBy(dx: 72, dy: 72), transform: nil)
        var location = 0
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            location += visible.length
        } while location < text.length
        ctx.closePDF()
        return output
    }
}
