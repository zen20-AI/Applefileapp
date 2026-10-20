import AppKit
import Combine
import FileAppCore
import QuickLookThumbnailing
import SwiftUI

/// Files parked for later: drop them in, drag them out to Mail, LINE or another folder whenever you're ready.
@MainActor
final class ShelfModel: ObservableObject {
    static let shared = ShelfModel()

    @Published private(set) var items: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: "shelfItems") ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter(Self.exists)
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { url in Self.exists(url) && !items.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        guard !new.isEmpty else { return }
        withAnimation(Theme.spring) { items.insert(contentsOf: new, at: 0) }
        save()
    }

    func remove(_ url: URL) {
        withAnimation(Theme.spring) { items.removeAll { $0 == url } }
        save()
    }

    func clear() {
        withAnimation(Theme.spring) { items.removeAll() }
        save()
    }

    /// Forgets files that were moved or deleted since they were shelved.
    func prune() {
        let kept = items.filter(Self.exists)
        guard kept.count != items.count else { return }
        items = kept
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: "shelfItems")
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// A small glass panel at the right edge of the screen that floats over every app.
@MainActor
final class ShelfController {
    static let width: CGFloat = 260
    private static let rowHeight: CGFloat = 46
    private static let maxRows = 7

    let model = ShelfModel.shared
    /// Opens the ring for the shelved files.
    var onRing: (([URL]) -> Void)?
    private(set) var isVisible = false
    private var subscription: AnyCancellable?

    private lazy var panel: NSPanel = {
        let panel = ShelfPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 200))
        let host = NSHostingView(rootView: ShelfView(
            model: model,
            settings: .shared,
            onRing: { [weak self] in self?.onRing?(self?.model.items ?? []) },
            onClose: { [weak self] in self?.hide() }))
        // The panel sets the size (it grows with the list); SwiftUI just fills it.
        host.sizingOptions = []
        panel.contentView = host
        subscription = model.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in MainActor.assumeIsolated { self?.fit(count: items.count) } }
        return panel
    }()

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.prune()
        let panel = self.panel
        if !isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            let height = Self.height(for: model.items.count)
            panel.setFrame(CGRect(x: visible.maxX - Self.width - 12, y: visible.midY - height / 2,
                                  width: Self.width, height: height), display: true)
        }
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    /// Adds files and makes sure the shelf is on screen.
    func add(_ urls: [URL]) {
        model.add(urls)
        if !model.items.isEmpty { show() }
    }

    /// Grows or shrinks with its contents, keeping the top edge where it is.
    private func fit(count: Int) {
        guard isVisible else { return }
        var frame = panel.frame
        let height = Self.height(for: count)
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: true)
    }

    private static func height(for count: Int) -> CGFloat {
        let header: CGFloat = 50
        let padding: CGFloat = 20
        let body = count == 0 ? 120 : CGFloat(min(count, maxRows)) * rowHeight + 8
        return header + body + padding
    }
}

/// Never takes focus from the app you're working in, but still accepts drops and drags.
private final class ShelfPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var settings: AppSettings
    let onRing: () -> Void
    let onClose: () -> Void
    @State private var isTargeted = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 6) {
            header
            if model.items.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.items, id: \.self) { url in
                            ShelfRow(url: url) { model.remove(url) }
                                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isTargeted ? Theme.accent.opacity(0.14) : Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.glassEdge), lineWidth: isTargeted ? 1.5 : 1)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(4)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            model.add(files)
            return !files.isEmpty
        } isTargeted: { targeted in withAnimation(Theme.snappy) { isTargeted = targeted } }
        .animation(Theme.spring, value: model.items)
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Drag this handle to take every file at once.
            DragAllHandle(urls: model.items)
                .frame(width: 30, height: 30)
                .help("Drag to take all files")
            VStack(alignment: .leading, spacing: 0) {
                Text("Shelf").font(.system(size: 13, weight: .bold, design: .rounded))
                Text(model.items.isEmpty ? String(localized: "Empty") : String(localized: "\(model.items.count) files"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.label)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            ShelfButton(symbol: "circle.hexagongrid", title: String(localized: "Open the ring for these files"), action: onRing)
                .disabled(model.items.isEmpty)
            ShelfButton(symbol: copied ? "checkmark" : "doc.on.doc",
                        title: String(localized: "Copy files (paste into Mail, LINE or Finder)")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(model.items as [NSURL])
                withAnimation(Theme.snappy) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(Theme.snappy) { copied = false } }
            }
            .disabled(model.items.isEmpty)
            Menu {
                Toggle("Keep new results here", isOn: $settings.shelfCollectsResults)
                Divider()
                Button("Clear Shelf", role: .destructive) { model.clear() }
                    .disabled(model.items.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.surfaceStrong))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            ShelfButton(symbol: "xmark", title: String(localized: "Hide Shelf"), action: onClose)
        }
        .frame(height: 38)
        .padding(.horizontal, 2)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.accentGradient)
                .contentTransition(.symbolEffect(.replace))
            Text("Drop files here")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.8))
            Text("Keep them handy, then drag them out wherever you need them.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundStyle(isTargeted ? Theme.accent : Theme.hairline))
    }
}

private struct ShelfRow: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Thumbnail(url: url)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteFormatter.string(url.fileSize))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.label)
            }
            Spacer(minLength: 0)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.label)
                }
                .buttonStyle(.plain)
                .help("Remove from Shelf (the file stays where it is)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.surfaceStrong : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Shelf", action: onRemove)
        }
        .help("Drag out to use it · double-click to open")
    }
}

/// Quick Look thumbnail (falls back to the Finder icon).
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: 64, height: 64),
                    scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    image = thumbnail.nsImage
                }
            }
    }
}

private struct ShelfButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? Color.white : Theme.ink.opacity(0.75))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovering ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceStrong)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering = $0 && isEnabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A stack of file icons you can drag to take every shelved file in one go.
private struct DragAllHandle: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> DragAllView { DragAllView() }

    func updateNSView(_ view: DragAllView, context: Context) {
        view.urls = urls
    }
}

private final class DragAllView: NSView, NSDraggingSource {
    var urls: [URL] = [] {
        didSet { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let accent = NSColor(red: 0.10, green: 0.74, blue: 0.60, alpha: 1)
        if urls.isEmpty {
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let symbol = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            symbol?.isTemplate = true
            NSColor.secondaryLabelColor.set()
            symbol?.draw(in: rect.insetBy(dx: 7, dy: 8), from: .zero, operation: .sourceOver, fraction: 0.7)
            return
        }
        // Up to three icons fanned out, newest on top.
        for (index, url) in urls.prefix(3).enumerated().reversed() {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(index) * 2.5
            icon.draw(in: CGRect(x: rect.minX + offset, y: rect.minY + offset, width: rect.width - 5, height: rect.height - 5))
        }
        if urls.count > 1 {
            let badge = "\(urls.count)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: NSColor.white]
            let size = badge.size(withAttributes: attrs)
            let badgeRect = CGRect(x: bounds.maxX - size.width - 6, y: bounds.minY, width: size.width + 6, height: 11)
            accent.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 5.5, yRadius: 5.5).fill()
            badge.draw(at: CGPoint(x: badgeRect.minX + 3, y: badgeRect.minY + (11 - size.height) / 2), withAttributes: attrs)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty else { return }
        let start = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 6)) * 4
            item.setDraggingFrame(CGRect(x: start.x - 16 + offset, y: start.y - 16 - offset, width: 32, height: 32), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy // never moves the original out from under you
    }
}
