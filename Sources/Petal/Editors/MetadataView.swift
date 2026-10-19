import FileAppCore
import ImageIO
import SwiftUI

/// Read-only view of an image's EXIF/GPS/TIFF properties, with a "remove all" action.
struct MetadataView: View {
    let url: URL
    let onStrip: () -> Void
    let onClose: () -> Void

    private struct Entry: Identifiable {
        let id: String
        let key: String
        let value: String
    }

    private struct Section: Identifiable {
        let id: String
        let entries: [Entry]
    }

    private let sections: [Section]
    private let hasLocation: Bool

    init(url: URL, onStrip: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.url = url
        self.onStrip = onStrip
        self.onClose = onClose

        let properties = ImageFile.properties(of: url)
        var general: [Entry] = []
        var groups: [Section] = []
        for key in properties.keys.sorted() {
            if let nested = properties[key] as? [String: Any] {
                let name = Self.groupName(key)
                let entries = nested.keys.sorted().map { Entry(id: "\(key).\($0)", key: $0, value: Self.describe(nested[$0])) }
                if !entries.isEmpty { groups.append(Section(id: name, entries: entries)) }
            } else {
                general.append(Entry(id: key, key: key, value: Self.describe(properties[key])))
            }
        }
        general.insert(Entry(id: "_size", key: "FileSize", value: ByteFormatter.string(url.fileSize)), at: 0)
        sections = [Section(id: "General", entries: general)] + groups
        hasLocation = properties[kCGImagePropertyGPSDictionary as String] != nil
    }

    var body: some View {
        EditorScaffold(title: "Metadata", onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if hasLocation {
                        Label("Contains location", systemImage: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red.opacity(0.75)))
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.id.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.label)
                                ForEach(section.entries) { entry in
                                    HStack(alignment: .top) {
                                        Text(entry.key)
                                            .foregroundStyle(Theme.ink.opacity(0.65))
                                            .frame(width: 170, alignment: .leading)
                                        Text(entry.value)
                                            .foregroundStyle(Theme.ink)
                                            .textSelection(.enabled)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: 12))
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            }
        } footer: {
            HStack {
                Text("Removing re-saves the image without EXIF, GPS or camera data.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                Spacer()
                Button("Remove Metadata", action: onStrip)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private static func groupName(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case let array as [Any]: return array.map { describe($0) }.joined(separator: ", ")
        case let dictionary as [String: Any]: return "\(dictionary.count) values"
        case let value?: return String(describing: value)
        case nil: return "—"
        }
    }
}
