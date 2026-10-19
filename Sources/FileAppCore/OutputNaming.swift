import Foundation

/// Builds output file names next to the source, never overwriting existing files.
///
///     Page 001.pdf  →  Page 001.jpg
///     Page 001.jpg  →  Page 001 Cropped.jpg
///     Page 001 Cropped.jpg  →  Page 001 Cropped With Background.png
public enum OutputNaming {
    /// When set, results go into this folder instead of next to the source.
    nonisolated(unsafe) public static var destinationDirectory: URL?

    public static func url(
        for source: URL,
        suffix: String? = nil,
        fileExtension: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let directory = destinationDirectory ?? source.deletingLastPathComponent()
        var base = source.deletingPathExtension().lastPathComponent
        if let suffix, !suffix.isEmpty {
            base += " " + suffix
        }

        var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var counter = 2
        while candidate == source || exists(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
