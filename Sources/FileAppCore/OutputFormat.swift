import Foundation
import UniformTypeIdentifiers

/// A conversion target shown on the "Convert" ring.
public enum OutputFormat: String, CaseIterable, Identifiable {
    case png, webp, heic, jpg, avif, tiff, bmp, pdf, docx

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
    public var fileExtension: String { rawValue }

    public var utType: UTType? {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .webp: return .webP
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .avif: return UTType("public.avif")
        case .pdf: return .pdf
        case .docx: return UTType("org.openxmlformats.wordprocessingml.document")
        }
    }

    public var isImage: Bool {
        switch self {
        case .pdf, .docx: return false
        default: return true
        }
    }

    /// Lossy formats get an explicit quality when encoded.
    public var isLossy: Bool {
        switch self {
        case .jpg, .heic, .webp, .avif: return true
        default: return false
        }
    }

    /// True when `url` is already in this format (e.g. .jpeg → JPG).
    public func matches(_ url: URL) -> Bool {
        guard let source = url.contentType, let target = utType else { return false }
        return source.conforms(to: target)
    }
}
