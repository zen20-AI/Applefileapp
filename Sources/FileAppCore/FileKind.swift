import Foundation
import UniformTypeIdentifiers

/// Broad category of a dropped file; decides which ring actions apply.
public enum FileKind: Equatable {
    case image
    case pdf
    case document
    case other

    static let documentTypes: [UTType] = [
        .rtf, .rtfd, .plainText, .html,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("org.oasis-open.opendocument.text"),
    ].compactMap { $0 }

    public init(url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            self = .other
            return
        }
        if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image) {
            self = .image
        } else if Self.documentTypes.contains(where: { type.conforms(to: $0) }) {
            self = .document
        } else {
            self = .other
        }
    }
}

public extension URL {
    var contentType: UTType? { UTType(filenameExtension: pathExtension.lowercased()) }

    var fileSize: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
