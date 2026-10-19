import AppKit
import FileAppCore
import Foundation
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case compress, resize, cutOut, copyText, edit, crop, annotate, redact, addBackground, metadata
    case animate, merge, pages, split, secure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: return String(localized: "Compress")
        case .resize: return String(localized: "Resize")
        case .cutOut: return String(localized: "Cut Out")
        case .copyText: return String(localized: "Copy Text")
        case .edit: return String(localized: "Edit")
        case .crop: return String(localized: "Crop")
        case .annotate: return String(localized: "Annotate")
        case .redact: return String(localized: "Redact")
        case .addBackground: return String(localized: "Add BG")
        case .metadata: return String(localized: "Metadata")
        case .animate: return String(localized: "GIF / Video")
        case .merge: return String(localized: "Merge PDF")
        case .pages: return String(localized: "Pages")
        case .split: return String(localized: "Split PDF")
        case .secure: return String(localized: "PDF Tools")
        }
    }

    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .cutOut: return "person.crop.rectangle"
        case .copyText: return "text.viewfinder"
        case .edit: return "slider.horizontal.3"
        case .crop: return "crop"
        case .annotate: return "pencil.tip.crop.circle"
        case .redact: return "eye.slash"
        case .addBackground: return "photo.on.rectangle"
        case .metadata: return "tag"
        case .animate: return "play.rectangle.on.rectangle"
        case .merge: return "doc.on.doc"
        case .pages: return "rectangle.stack"
        case .split: return "scissors"
        case .secure: return "lock.doc"
        }
    }

    /// Tools that need several files (merge, animate) or that only make sense alone.
    func isAvailable(for urls: [URL]) -> Bool {
        switch self {
        case .merge: return urls.filter(PDFMerger.canMerge).count > 1
        case .animate: return urls.filter { FileKind(url: $0) == .image }.count > 1
        default: return urls.contains(where: isAvailable(for:))
        }
    }

    func isAvailable(for url: URL) -> Bool {
        let kind = FileKind(url: url)
        switch self {
        case .compress: return Compressor.canCompress(url) || kind == .video
        case .copyText: return TextRecognizer.canRecognize(url)
        case .merge, .pages: return PDFMerger.canMerge(url)
        case .split: return kind == .pdf && PDFPages.pageCount(of: url) > 1
        case .secure: return kind == .pdf
        default: return kind == .image
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

        convertItems = Self.applicable(OutputFormat.allCases.map { format in
            RingItem(
                id: format.id,
                title: format.label,
                symbol: nil,
                action: .convert(format),
                enabled: urls.contains { Converter.isAvailable(format, for: $0) })
        })
        toolItems = Self.applicable(Tool.allCases.map { tool in
            RingItem(
                id: tool.id,
                title: tool.title,
                symbol: tool.symbol,
                action: .tool(tool),
                enabled: tool.isAvailable(for: urls))
        })

        // Images, PDFs and videos open on the tools ring; documents are about converting.
        let hasTools = toolItems.contains(where: \.enabled)
        let hasFormats = convertItems.contains(where: \.enabled)
        mode = hasTools && (urls.allSatisfy { FileKind(url: $0) != .document } || !hasFormats) ? .tools : .convert
    }

    /// Keeps the ring small: only petals that work for these files (all of them, dimmed, if none do).
    private static func applicable(_ items: [RingItem]) -> [RingItem] {
        let enabled = items.filter(\.enabled)
        return enabled.isEmpty ? items : enabled
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
