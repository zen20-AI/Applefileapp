import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Whole-document PDF tools: passwords, watermark, page numbers and signature stamps.
///
/// Stamping redraws every page into a new PDF; text and vector art stay vector.
public enum PDFTools {
    public static func isPDF(_ url: URL) -> Bool { FileKind(url: url) == .pdf }

    public static func isLocked(_ url: URL) -> Bool {
        CGPDFDocument(url as CFURL)?.isEncrypted ?? false
    }

    // MARK: - Passwords

    /// Writes "<name> Locked.pdf", which needs `password` to open.
    public static func lock(_ url: URL, password: String) throws -> URL {
        guard !password.isEmpty else { throw FileAppError.unsupported("An empty password") }
        guard let document = PDFDocument(url: url), !document.isLocked else { throw FileAppError.unreadable(url) }
        let output = OutputNaming.url(for: url, suffix: "Locked", fileExtension: "pdf")
        let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard document.write(to: output, withOptions: options) else { throw FileAppError.writeFailed(output) }
        return output
    }

    /// Writes "<name> Unlocked.pdf" without a password.
    public static func unlock(_ url: URL, password: String) throws -> URL {
        try redraw(url, suffix: "Unlocked", password: password) { _, _, _, _ in }
    }

    public enum PasswordError: LocalizedError {
        case wrongPassword
        case locked

        public var errorDescription: String? {
            switch self {
            case .wrongPassword: return "That password didn't open the PDF"
            case .locked: return "This PDF is locked — unlock it first"
            }
        }
    }

    // MARK: - Watermark

    /// Writes "<name> Watermarked.pdf" with diagonal text across every page.
    public static func watermark(_ url: URL, text: String, opacity: Double = 0.18) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw FileAppError.unsupported("An empty watermark") }
        return try redraw(url, suffix: "Watermarked") { ctx, size, _, _ in
            let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
            let fontSize = min(diagonal / CGFloat(max(text.count, 4)) * 1.3, size.height / 4)
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: atan2(size.height, size.width))
            drawText(text, in: ctx, size: fontSize, weight: .bold,
                     color: CGColor(gray: 0.35, alpha: opacity), centeredAt: .zero)
            ctx.restoreGState()
        }
    }

    // MARK: - Page numbers

    public enum NumberPosition: String, CaseIterable, Sendable {
        case bottomCenter, bottomRight, bottomLeft, topRight
    }

    /// Writes "<name> Numbered.pdf". `ofTotal` writes "3 / 12" instead of "3".
    public static func numberPages(_ url: URL, position: NumberPosition = .bottomCenter,
                                   ofTotal: Bool = false, startAt: Int = 1) throws -> URL {
        try redraw(url, suffix: "Numbered") { ctx, size, index, count in
            let number = index + startAt
            let label = ofTotal ? "\(number) / \(count + startAt - 1)" : "\(number)"
            let fontSize = max(9, min(size.width, size.height) * 0.018)
            let margin = max(18, min(size.width, size.height) * 0.045)
            let point: CGPoint
            switch position {
            case .bottomCenter: point = CGPoint(x: size.width / 2, y: margin)
            case .bottomRight: point = CGPoint(x: size.width - margin * 1.6, y: margin)
            case .bottomLeft: point = CGPoint(x: margin * 1.6, y: margin)
            case .topRight: point = CGPoint(x: size.width - margin * 1.6, y: size.height - margin)
            }
            drawText(label, in: ctx, size: fontSize, weight: .medium, color: CGColor(gray: 0.25, alpha: 1), centeredAt: point)
        }
    }

    // MARK: - Signature

    /// Writes "<name> Signed.pdf" with `image` placed on one page.
    /// `rect` is normalised to the upright page (0…1, origin bottom-left).
    public static func stamp(_ url: URL, image: CGImage, pageIndex: Int, rect: CGRect) throws -> URL {
        try redraw(url, suffix: "Signed") { ctx, size, index, _ in
            guard index == pageIndex else { return }
            let target = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                                width: rect.width * size.width, height: rect.height * size.height)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: target)
        }
    }

    // MARK: - Redrawing

    /// Draws every page upright into a new PDF, then lets `overlay` draw on top of it.
    static func redraw(_ url: URL, suffix: String, password: String? = nil,
                       overlay: (CGContext, CGSize, Int, Int) -> Void) throws -> URL {
        guard let document = CGPDFDocument(url as CFURL) else { throw FileAppError.unreadable(url) }
        if document.isEncrypted && !document.isUnlocked {
            guard let password else { throw PasswordError.locked }
            guard document.unlockWithPassword(password) else { throw PasswordError.wrongPassword }
        }
        let output = OutputNaming.url(for: url, suffix: suffix, fileExtension: "pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(output as CFURL, mediaBox: &box, nil) else { throw FileAppError.writeFailed(output) }

        let count = document.numberOfPages
        for number in 1...max(count, 1) {
            guard let page = document.page(at: number) else { continue }
            let crop = page.getBoxRect(.cropBox)
            let size = page.rotationAngle % 180 != 0 ? CGSize(width: crop.height, height: crop.width) : crop.size
            var mediaBox = CGRect(origin: .zero, size: size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)]
            ctx.beginPDFPage(info as CFDictionary)
            ctx.saveGState()
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: mediaBox, rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            overlay(ctx, size, number - 1, count)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return output
    }

    private static func drawText(_ text: String, in ctx: CGContext, size: CGFloat, weight: NSFont.Weight,
                                 color: CGColor, centeredAt point: CGPoint) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: color) ?? .gray,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
        CTLineDraw(line, ctx)
    }
}
