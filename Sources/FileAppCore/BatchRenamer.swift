import Foundation

/// Renames many files from one pattern, e.g. "Trip {n}" → "Trip 01.jpg", "Trip 02.jpg".
///
/// Tokens: `{name}` original name, `{n}` counter, `{date}` modification date (yyyy-MM-dd), `{ext}` extension.
public struct RenamePattern: Equatable, Sendable {
    public var template: String
    public var start: Int
    /// Minimum digits for `{n}`; 0 picks enough digits for the whole batch.
    public var digits: Int

    public init(template: String, start: Int = 1, digits: Int = 0) {
        self.template = template
        self.start = start
        self.digits = digits
    }
}

public enum BatchRenamer {
    /// New URLs, in the same order and folders. Names that would clash get " 2", " 3", …
    public static func preview(_ urls: [URL], pattern: RenamePattern,
                               exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [URL] {
        let width = pattern.digits > 0 ? pattern.digits : String(pattern.start + urls.count - 1).count
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let template = pattern.template.contains("{n}") || urls.count == 1 ? pattern.template : pattern.template + " {n}"

        var taken = Set<String>()
        let sources = Set(urls.map { $0.standardizedFileURL.path })
        return urls.enumerated().map { offset, url in
            let number = String(pattern.start + offset)
            let padded = String(repeating: "0", count: max(0, width - number.count)) + number
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            var base = template
                .replacingOccurrences(of: "{name}", with: url.deletingPathExtension().lastPathComponent)
                .replacingOccurrences(of: "{n}", with: padded)
                .replacingOccurrences(of: "{date}", with: formatter.string(from: modified))
                .replacingOccurrences(of: "{ext}", with: url.pathExtension)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespaces)
            if base.isEmpty { base = url.deletingPathExtension().lastPathComponent }

            let directory = url.deletingLastPathComponent()
            func candidate(_ name: String) -> URL {
                let file = directory.appendingPathComponent(name)
                return url.pathExtension.isEmpty ? file : file.appendingPathExtension(url.pathExtension)
            }
            var result = candidate(base)
            var counter = 2
            // Clashes with other files (not ones being renamed in this batch) or with earlier new names.
            while taken.contains(result.path.lowercased())
                    || (result.standardizedFileURL != url.standardizedFileURL
                        && !sources.contains(result.standardizedFileURL.path) && exists(result)) {
                result = candidate("\(base) \(counter)")
                counter += 1
            }
            taken.insert(result.path.lowercased())
            return result
        }
    }

    /// Renames in place and returns the new URLs. Uses temporary names first so swaps (A↔B) work.
    public static func rename(_ urls: [URL], pattern: RenamePattern) throws -> [URL] {
        let targets = preview(urls, pattern: pattern)
        let manager = FileManager.default
        var staged: [(source: URL, temp: URL, target: URL)] = []
        var done = 0
        do {
            for (source, target) in zip(urls, targets) where source.standardizedFileURL != target.standardizedFileURL {
                let temp = source.deletingLastPathComponent().appendingPathComponent(".petal-rename-\(UUID().uuidString)")
                try manager.moveItem(at: source, to: temp)
                staged.append((source, temp, target))
            }
            for item in staged {
                try manager.moveItem(at: item.temp, to: item.target)
                done += 1
            }
        } catch {
            // Put back whatever still has a temporary name.
            for item in staged.dropFirst(done) { try? manager.moveItem(at: item.temp, to: item.source) }
            throw error
        }
        return targets
    }
}
