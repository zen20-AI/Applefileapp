import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var action: String
    var sources: [URL]
    var outputs: [URL]
    var failures: Int = 0
}

/// Remembers what the app produced so the Manager can reveal, open or clean it up later.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 500

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Petal", isDirectory: true).appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    var recentOutputs: [URL] {
        Array(entries.lazy.flatMap(\.outputs).prefix(6))
    }

    var totalOutputs: Int { entries.reduce(0) { $0 + $1.outputs.count } }

    func record(action: String, sources: [URL], outputs: [URL], failures: Int = 0) {
        guard !outputs.isEmpty || failures > 0 else { return }
        entries.insert(HistoryEntry(action: action, sources: sources, outputs: outputs, failures: failures), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        persist()
    }

    func remove(_ ids: Set<HistoryEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// Drops entries whose outputs have all been deleted or moved.
    func pruneMissing() {
        entries.removeAll { entry in
            !entry.outputs.isEmpty && entry.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
        }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("History: \(error.localizedDescription)")
        }
    }
}
