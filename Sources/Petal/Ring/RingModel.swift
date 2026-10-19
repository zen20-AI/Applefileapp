import AppKit
import FileAppCore
import Foundation
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case compress, resize, metadata, edit, annotate, addBackground, crop, redact, merge, pages, split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .resize: return "Resize"
        case .merge: return "Merge PDF"
        case .pages: return "Pages"
        case .split: return "Split PDF"
        case .metadata: return "Metadata"
        case .edit: return "Edit"
        case .annotate: return "Annotate"
        case .addBackground: return "Add BG"
        case .crop: return "Crop"
        case .redact: return "Redact"
        }
    }

    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .merge: return "doc.on.doc"
        case .pages: return "rectangle.stack"
        case .split: return "scissors"
        case .metadata: return "tag"
        case .edit: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .addBackground: return "photo.on.rectangle"
        case .crop: return "crop"
        case .redact: return "eye.slash"
        }
    }

    /// Merging needs at least two inputs; everything else needs one eligible file.
    func isAvailable(for urls: [URL]) -> Bool {
        if self == .merge { return urls.filter(PDFMerger.canMerge).count > 1 }
        return urls.contains(where: isAvailable(for:))
    }

    func isAvailable(for url: URL) -> Bool {
        switch self {
        case .compress: return Compressor.canCompress(url)
        case .merge, .pages: return PDFMerger.canMerge(url)
        case .split: return FileKind(url: url) == .pdf && PDFPages.pageCount(of: url) > 1
        default: return FileKind(url: url) == .image
        }
    }
}

enum RingAction: Equatable {
    case convert(OutputFormat)
    case tool(Tool)
}

struct RingItem: Identifiable {
    let id: String
    let title: String
    let symbol: String?
    let action: RingAction
    let enabled: Bool
}

enum RingMode {
    case convert, tools

    var toggled: RingMode { self == .convert ? .tools : .convert }
}

enum RingInteraction {
    /// Opened by a file drag: segments are drop targets, the hub flips modes on hover.
    case drag
    /// Opened from the menu bar: segments are buttons, clicking the hub flips modes.
    case click
}

@MainActor
final class RingModel: ObservableObject {
    static let diameter: CGFloat = 340
    /// How long a dragged file must rest on the hub to flip rings.
    static let hubFlipDelay: TimeInterval = 0.5

    @Published private(set) var urls: [URL] = []
    @Published var mode: RingMode = .tools
    @Published private(set) var hover: RingHit = .outside
    @Published private(set) var convertItems: [RingItem] = []
    @Published private(set) var toolItems: [RingItem] = []
    @Published private(set) var hubFlipProgress = false
    /// Drives the petals' staggered pop-in each time the ring appears.
    @Published var isPresented = false
    /// Icon of the (first) dragged file, shown in the hub.
    @Published private(set) var fileIcon: NSImage?
    private(set) var interaction: RingInteraction = .drag

    var onAction: ((RingAction, [URL]) -> Void)?
    var onDismiss: (() -> Void)?

    private var hubTimer: Timer?

    var items: [RingItem] { mode == .convert ? convertItems : toolItems }

    var geometry: RingGeometry {
        RingGeometry(segmentCount: items.count, innerRadius: 62, outerRadius: Self.diameter / 2 - 8)
    }

    var center: CGPoint { CGPoint(x: Self.diameter / 2, y: Self.diameter / 2) }

    var hubTitle: String {
        if case .segment(let index) = hover, items.indices.contains(index) {
            return items[index].title
        }
        let size = urls.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteFormatter.string(size)
    }

    func configure(urls: [URL], interaction: RingInteraction) {
        self.urls = urls
        self.interaction = interaction
        fileIcon = urls.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        hover = .outside
        cancelHubTimer()

        convertItems = OutputFormat.allCases.map { format in
            RingItem(
                id: format.id,
                title: format.label,
                symbol: nil,
                action: .convert(format),
                enabled: urls.contains { Converter.isAvailable(format, for: $0) })
        }
        toolItems = Tool.allCases.map { tool in
            RingItem(
                id: tool.id,
                title: tool.title,
                symbol: tool.symbol,
                action: .tool(tool),
                enabled: tool.isAvailable(for: urls))
        }

        // Images open on the tools ring; everything else is mostly about converting.
        let allImages = urls.allSatisfy { FileKind(url: $0) == .image }
        mode = allImages ? .tools : .convert
    }

    func updateHover(_ point: CGPoint?) {
        let hit = point.map { geometry.hit($0, center: center) } ?? .outside
        guard hit != hover else { return }
        hover = hit
        if case .segment(let index) = hit, items.indices.contains(index), items[index].enabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if hit == .center, interaction == .drag {
            startHubTimer()
        } else {
            cancelHubTimer()
        }
    }

    /// Runs the hovered segment's action. Returns false when nothing actionable is under the pointer.
    @discardableResult
    func commit() -> Bool {
        cancelHubTimer()
        guard case .segment(let index) = hover, items.indices.contains(index), items[index].enabled else {
            return false
        }
        onAction?(items[index].action, urls)
        return true
    }

    func tap(at point: CGPoint) {
        switch geometry.hit(point, center: center) {
        case .center:
            withAnimation(Theme.spring) { mode = mode.toggled }
        case .segment:
            updateHover(point)
            commit()
        case .outside:
            onDismiss?()
        }
    }

    // Spring-loaded hub: hovering the center during a drag flips between Convert and Tools.
    private func startHubTimer() {
        cancelHubTimer()
        hubFlipProgress = true
        hubTimer = Timer.scheduledTimer(withTimeInterval: Self.hubFlipDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hover == .center else { return }
                withAnimation(Theme.spring) { self.mode = self.mode.toggled }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                self.hubFlipProgress = false
            }
        }
    }

    private func cancelHubTimer() {
        hubTimer?.invalidate()
        hubTimer = nil
        hubFlipProgress = false
    }
}
