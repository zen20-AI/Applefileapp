import CoreGraphics
import Foundation
import PDFKit
import Vision

/// On-device OCR (Vision): reads text from images and PDFs, including Thai.
public enum TextRecognizer {
    public static func canRecognize(_ url: URL) -> Bool {
        let kind = FileKind(url: url)
        return kind == .image || kind == .pdf
    }

    /// Languages tried first; Vision still detects others automatically.
    nonisolated(unsafe) public static var preferredLanguages = ["th-TH", "en-US"]

    /// All text in the file, pages separated by blank lines.
    public static func text(of url: URL) throws -> String {
        switch FileKind(url: url) {
        case .image:
            return try recognize(ImageFile.load(url, maxPixelSize: 6000))
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw FileAppError.unreadable(url) }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                // Text PDFs already carry their text; only scanned pages need OCR.
                if let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), embedded.count > 20 {
                    pages.append(embedded)
                } else if let cgPage = page.pageRef, let image = Converter.renderPage(cgPage, dpi: 300) {
                    pages.append(try recognize(image))
                }
            }
            return pages.joined(separator: "\n\n")
        default:
            throw FileAppError.unsupported("Reading text from \(url.pathExtension.uppercased())")
        }
    }

    /// Writes "<name> Text.txt" and returns it with the text.
    public static func extract(_ url: URL) throws -> (output: URL, text: String) {
        let text = try text(of: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileAppError.unsupported("Finding text in \(url.lastPathComponent)")
        }
        let output = OutputNaming.url(for: url, suffix: "Text", fileExtension: "txt")
        do { try text.write(to: output, atomically: true, encoding: .utf8) } catch { throw FileAppError.writeFailed(output) }
        return (output, text)
    }

    public static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = preferredLanguages.filter(supported.contains)
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        return lines(from: observations).joined(separator: "\n")
    }

    /// Orders observations top-to-bottom, joining boxes on the same line left-to-right.
    static func lines(from observations: [VNRecognizedTextObservation]) -> [String] {
        let items = observations.compactMap { observation -> (box: CGRect, text: String)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (observation.boundingBox, text)
        }
        .sorted { $0.box.midY > $1.box.midY }

        var lines: [[(box: CGRect, text: String)]] = []
        for item in items {
            if let last = lines.last?.first, abs(last.box.midY - item.box.midY) < min(last.box.height, item.box.height) * 0.5 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}
