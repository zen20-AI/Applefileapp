import AppKit
import Foundation
import PDFKit

/// One page in an edited page list: a page of a PDF (or a whole image) plus extra rotation.
public struct PageRef: Hashable, Sendable {
    public var source: URL
    /// Page index in `source`; ignored for images.
    public var index: Int
    /// Extra clockwise rotation in degrees (multiples of 90).
    public var rotation: Int

    public init(source: URL, index: Int = 0, rotation: Int = 0) {
        self.source = source
        self.index = index
        self.rotation = rotation
    }
}

/// How to cut a page list into several PDFs.
public enum SplitMode: Equatable, Sendable {
    /// One file per page.
    case everyPage
    /// Consecutive chunks of this many pages.
    case every(Int)
    /// Page ranges such as "1-3, 5, 8-" — one file per range.
    case ranges(String)
}

/// Page-level PDF work: listing, rebuilding (reorder / rotate / delete), extracting and splitting.
public enum PDFPages {
    /// Every page of the given PDFs and images, in order.
    public static func pages(of urls: [URL]) throws -> [PageRef] {
        try urls.flatMap { url -> [PageRef] in
            switch FileKind(url: url) {
            case .pdf:
                guard let document = PDFDocument(url: url) else { throw FileAppError.unreadable(url) }
                return (0..<document.pageCount).map { PageRef(source: url, index: $0) }
            case .image:
                return [PageRef(source: url)]
            default:
                return []
            }
        }
    }

    public static func pageCount(of url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    /// Writes the pages, in order, as one PDF named after `name` ("<name> <suffix>.pdf").
    @discardableResult
    public static func write(_ pages: [PageRef], name: URL, suffix: String) throws -> URL {
        let output = OutputNaming.url(for: name, suffix: suffix, fileExtension: "pdf")
        try write(pages, to: output)
        return output
    }

    public static func write(_ pages: [PageRef], to output: URL) throws {
        guard !pages.isEmpty else { throw FileAppError.unsupported("An empty PDF") }
        var cache = DocumentCache()
        let document = PDFDocument()
        for ref in pages {
            document.insert(try cache.page(for: ref), at: document.pageCount)
        }
        guard document.write(to: output) else { throw FileAppError.writeFailed(output) }
    }

    /// Splits the pages into several PDFs inside a new "<name> Split" folder.
    /// A split that yields a single group writes just that one file next to the source.
    public static func split(_ pages: [PageRef], mode: SplitMode, name: URL) throws -> [URL] {
        let groups = try groups(pageCount: pages.count, mode: mode)
        guard groups.count > 1 else {
            let only = groups.first ?? []
            return [try write(only.map { pages[$0] }, name: name, suffix: label(for: only))]
        }

        let folder = try makeFolder(for: name, suffix: "Split")
        let base = name.deletingPathExtension().lastPathComponent
        return try groups.map { group in
            let output = folder.appendingPathComponent("\(base) \(label(for: group))").appendingPathExtension("pdf")
            try write(group.map { pages[$0] }, to: output)
            return output
        }
    }

    /// Splits a file as-is.
    public static func split(_ url: URL, mode: SplitMode) throws -> [URL] {
        try split(pages(of: [url]), mode: mode, name: url)
    }

    // MARK: - Ranges

    /// Zero-based page groups for a split. Throws for ranges that don't make sense.
    public static func groups(pageCount: Int, mode: SplitMode) throws -> [[Int]] {
        guard pageCount > 0 else { throw FileAppError.unsupported("Splitting an empty PDF") }
        switch mode {
        case .everyPage:
            return (0..<pageCount).map { [$0] }
        case .every(let size):
            let size = max(1, size)
            return stride(from: 0, to: pageCount, by: size).map { Array($0..<min($0 + size, pageCount)) }
        case .ranges(let text):
            return try parseRanges(text, pageCount: pageCount).map { Array($0) }
        }
    }

    /// Parses "1-3, 5, 8-" (1-based, open-ended allowed) into zero-based ranges.
    public static func parseRanges(_ text: String, pageCount: Int) throws -> [ClosedRange<Int>] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw RangeError.empty }

        return try parts.map { part in
            let bounds = part.replacingOccurrences(of: "–", with: "-")
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let lower: Int, upper: Int
            switch bounds.count {
            case 1:
                guard let page = Int(bounds[0]) else { throw RangeError.invalid(part) }
                lower = page; upper = page
            case 2:
                guard let first = bounds[0].isEmpty ? 1 : Int(bounds[0]),
                      let last = bounds[1].isEmpty ? pageCount : Int(bounds[1]) else { throw RangeError.invalid(part) }
                lower = first; upper = last
            default:
                throw RangeError.invalid(part)
            }
            guard lower >= 1, upper <= pageCount, lower <= upper else {
                throw RangeError.outOfBounds(part, pageCount: pageCount)
            }
            return (lower - 1)...(upper - 1)
        }
    }

    public enum RangeError: LocalizedError, Equatable {
        case empty
        case invalid(String)
        case outOfBounds(String, pageCount: Int)

        public var errorDescription: String? {
            switch self {
            case .empty: return "Enter page ranges, like 1-3, 5"
            case .invalid(let part): return "“\(part)” isn't a page range"
            case .outOfBounds(let part, let count): return "“\(part)” is outside pages 1–\(count)"
            }
        }
    }

    // MARK: - Helpers

    /// "Page 4" or "Pages 1-3" (1-based).
    static func label(for group: [Int]) -> String {
        guard let first = group.first, let last = group.last else { return "Pages" }
        let contiguous = group == Array(first...last)
        if group.count == 1 { return "Page \(first + 1)" }
        return contiguous ? "Pages \(first + 1)-\(last + 1)" : "Pages"
    }

    private static func makeFolder(for name: URL, suffix: String) throws -> URL {
        let directory = OutputNaming.destinationDirectory ?? name.deletingLastPathComponent()
        let base = name.deletingPathExtension().lastPathComponent + " " + suffix
        var folder = directory.appendingPathComponent(base, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = directory.appendingPathComponent("\(base) \(counter)", isDirectory: true)
            counter += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Opens each source once and hands out page copies (so sources are never modified).
    private struct DocumentCache {
        private var documents: [URL: PDFDocument] = [:]

        mutating func page(for ref: PageRef) throws -> PDFPage {
            let page: PDFPage
            if FileKind(url: ref.source) == .pdf {
                let document = try documents[ref.source] ?? {
                    guard let document = PDFDocument(url: ref.source) else { throw FileAppError.unreadable(ref.source) }
                    return document
                }()
                documents[ref.source] = document
                guard let original = document.page(at: ref.index), let copy = original.copy() as? PDFPage else {
                    throw FileAppError.unreadable(ref.source)
                }
                page = copy
            } else {
                let image = try ImageFile.load(ref.source)
                guard let imagePage = PDFPage(image: NSImage(cgImage: image, size: image.size)) else {
                    throw FileAppError.unreadable(ref.source)
                }
                page = imagePage
            }
            page.rotation = ((page.rotation + ref.rotation) % 360 + 360) % 360
            return page
        }
    }
}
