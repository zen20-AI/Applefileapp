import AppKit
import FileAppCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Pages of one or more PDFs / images being reordered, rotated, deleted, extracted or split.
@MainActor
final class PagesModel: ObservableObject {
    struct Page: Identifiable, Equatable {
        let id = UUID()
        var ref: PageRef
    }

    @Published var pages: [Page] = []
    @Published var selection: Set<UUID> = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// The page being dragged to a new position.
    @Published var dragging: UUID? {
        didSet { if dragging != nil { watchDragEnd() } }
    }
    /// Output files are named after the first source.
    private(set) var name: URL
    private var anchor: UUID?

    init(urls: [URL]) throws {
        name = urls[0]
        try add(urls)
    }

    var refs: [PageRef] { pages.map(\.ref) }
    var selectedRefs: [PageRef] { pages.filter { selection.contains($0.id) }.map(\.ref) }
    var sources: Set<URL> { Set(pages.map(\.ref.source)) }

    func add(_ urls: [URL], at index: Int? = nil) throws {
        let added = try PDFPages.pages(of: urls.filter(PDFMerger.canMerge)).map { Page(ref: $0) }
        if pages.isEmpty, let first = added.first { name = first.ref.source }
        pages.insert(contentsOf: added, at: min(index ?? pages.count, pages.count))
        loadThumbnails(for: added.map(\.ref))
    }

    func thumbnail(for ref: PageRef) -> NSImage? { thumbnails[Self.key(ref)] }

    // MARK: Selection (click, ⌘-click toggles, ⇧-click extends)

    func click(_ page: Page, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let from = pages.firstIndex(where: { $0.id == anchor }),
           let to = pages.firstIndex(of: page) {
            selection = Set(pages[min(from, to)...max(from, to)].map(\.id))
        } else if modifiers.contains(.command) {
            if selection.contains(page.id) { selection.remove(page.id) } else { selection.insert(page.id) }
            anchor = page.id
        } else {
            selection = selection == [page.id] ? [] : [page.id]
            anchor = page.id
        }
    }

    func selectAll() { selection = Set(pages.map(\.id)) }

    /// The selection, or every page when nothing is selected.
    private var targetIDs: Set<UUID> { selection.isEmpty ? Set(pages.map(\.id)) : selection }

    // MARK: Editing

    func rotate(by degrees: Int) {
        let ids = targetIDs
        for index in pages.indices where ids.contains(pages[index].id) {
            // Rotation keeps accumulating so the animation always turns the short way; the writer normalises it.
            pages[index].ref.rotation += degrees
        }
    }

    func deleteSelection() {
        pages.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == target }) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }

    func reverse() { pages.reverse() }

    /// A drag dropped outside the grid never reaches a drop delegate, so clear it once the mouse is up.
    private func watchDragEnd() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.dragging != nil else { return timer.invalidate() }
                if NSEvent.pressedMouseButtons == 0 {
                    self.dragging = nil
                    timer.invalidate()
                }
            }
        }
    }

    // MARK: Thumbnails

    private static func key(_ ref: PageRef) -> String { "\(ref.source.path)#\(ref.index)" }

    private func loadThumbnails(for refs: [PageRef]) {
        let missing = refs.filter { thumbnails[Self.key($0)] == nil }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var documents: [URL: PDFDocument] = [:]
            for ref in missing {
                let image: NSImage?
                if FileKind(url: ref.source) == .pdf {
                    let document = documents[ref.source] ?? PDFDocument(url: ref.source)
                    documents[ref.source] = document
                    image = document?.page(at: ref.index)?.thumbnail(of: CGSize(width: 260, height: 260), for: .cropBox)
                } else {
                    image = NSImage(contentsOf: ref.source)
                }
                guard let image else { continue }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.thumbnails[Self.key(ref)] = image }
                }
            }
        }
    }
}

// MARK: - Editor

/// "Pages": a grid of page thumbnails to drag into order, rotate, delete, extract or split.
struct PagesEditor: View {
    @ObservedObject var model: PagesModel
    let onSave: ([PageRef], URL) -> Void
    let onExtract: ([PageRef], URL) -> Void
    let onSplit: ([PageRef], SplitMode, URL) -> Void
    let onClose: () -> Void

    @State private var showSplit = false
    @State private var fileTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 18)]

    private var title: String {
        let count = model.pages.count
        let files = model.sources.count
        let pages = count == 1 ? "1 page" : "\(count) pages"
        return files > 1 ? "\(pages) from \(files) files" : "\(model.name.lastPathComponent) · \(pages)"
    }

    var body: some View {
        EditorScaffold(title: title, onClose: onClose) {
            ZStack {
                if model.pages.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .opacity(fileTargeted ? 1 : 0)
            }
            .onDrop(of: [.fileURL], isTargeted: $fileTargeted) { providers in
                loadFiles(providers)
                return true
            }
            .background(shortcuts)
        } footer: {
            footer
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { offset, page in
                    PageCell(
                        number: offset + 1,
                        page: page,
                        thumbnail: model.thumbnail(for: page.ref),
                        selected: model.selection.contains(page.id),
                        dragging: model.dragging == page.id,
                        showsSource: model.sources.count > 1)
                    .onTapGesture { withAnimation(Theme.snappy) { model.click(page, modifiers: NSEvent.modifierFlags) } }
                    .onDrag {
                        model.dragging = page.id
                        return NSItemProvider(object: page.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: PageDropDelegate(target: page.id, model: model))
                    .contextMenu { menu(for: page) }
                }
            }
            .padding(4)
            .animation(Theme.spring, value: model.pages.map(\.id))
        }
        .scrollIndicators(.never)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.snappy) { model.selection.removeAll() } }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accentGradient)
            Text("Drop PDFs or images to add pages")
                .font(.system(size: 14, weight: .semibold))
            Button("Add Files…", action: addFiles)
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private func menu(for page: PagesModel.Page) -> some View {
        let applies = model.selection.contains(page.id)
        Button("Rotate Right") { select(page, keeping: applies); withAnimation(Theme.spring) { model.rotate(by: 90) } }
        Button("Rotate Left") { select(page, keeping: applies); withAnimation(Theme.spring) { model.rotate(by: -90) } }
        Divider()
        Button("Extract") { select(page, keeping: applies); onExtract(model.selectedRefs, model.name) }
        Divider()
        Button("Delete", role: .destructive) { select(page, keeping: applies); withAnimation(Theme.spring) { model.deleteSelection() } }
    }

    /// Context-menu actions apply to the selection when the clicked page is in it, otherwise to that page.
    private func select(_ page: PagesModel.Page, keeping: Bool) {
        if !keeping { model.selection = [page.id] }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "plus", help: "Add PDFs or images", action: addFiles)
            IconButton(symbol: "rotate.left", help: "Rotate left (⌘[)") { withAnimation(Theme.spring) { model.rotate(by: -90) } }
                .disabled(model.pages.isEmpty)
            IconButton(symbol: "rotate.right", help: "Rotate right (⌘])") { withAnimation(Theme.spring) { model.rotate(by: 90) } }
                .disabled(model.pages.isEmpty)
            IconButton(symbol: "arrow.up.arrow.down", help: "Reverse page order") { withAnimation(Theme.spring) { model.reverse() } }
                .disabled(model.pages.count < 2)
            IconButton(symbol: "trash", help: "Delete selected pages (⌫)") { withAnimation(Theme.spring) { model.deleteSelection() } }
                .disabled(model.selection.isEmpty)

            Text(model.selection.isEmpty ? "Click to select · drag to reorder" : "\(model.selection.count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label)
                .contentTransition(.numericText())
                .padding(.leading, 6)

            Spacer(minLength: 8)

            Button("Split…") { showSplit = true }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.pages.isEmpty)
                .popover(isPresented: $showSplit, arrowEdge: .top) {
                    SplitPanel(pageCount: model.pages.count) { mode in
                        showSplit = false
                        onSplit(model.refs, mode, model.name)
                    }
                }
            Button(model.selection.isEmpty ? "Extract" : "Extract \(model.selection.count)") {
                onExtract(model.selectedRefs, model.name)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.selection.isEmpty)
            .help("Save the selected pages as a new PDF")
            Button("Save PDF") { onSave(model.refs, model.name) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.pages.isEmpty)
        }
    }

    /// Hidden buttons that carry the editor's keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { withAnimation(Theme.snappy) { model.selectAll() } }.keyboardShortcut("a", modifiers: .command)
            Button("") { withAnimation(Theme.spring) { model.deleteSelection() } }.keyboardShortcut(.delete, modifiers: [])
            Button("") { withAnimation(Theme.spring) { model.rotate(by: -90) } }.keyboardShortcut("[", modifiers: .command)
            Button("") { withAnimation(Theme.spring) { model.rotate(by: 90) } }.keyboardShortcut("]", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .image]
        panel.prompt = "Add Pages"
        guard panel.runModal() == .OK else { return }
        insert(panel.urls)
    }

    private func loadFiles(_ providers: [NSItemProvider]) {
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { insert([url]) } }
            }
        }
    }

    private func insert(_ urls: [URL]) {
        withAnimation(Theme.spring) { try? model.add(urls) }
    }
}

/// Live reordering: the dragged page slides into place as it passes over other pages.
private struct PageDropDelegate: DropDelegate {
    let target: UUID
    let model: PagesModel

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragging = model.dragging, dragging != target else { return }
            withAnimation(Theme.spring) { model.move(dragging, before: target) }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { model.dragging = nil }
        return true
    }
}

private struct PageCell: View {
    let number: Int
    let page: PagesModel.Page
    let thumbnail: NSImage?
    let selected: Bool
    let dragging: Bool
    let showsSource: Bool
    @State private var hovering = false

    private let box = CGSize(width: 128, height: 150)

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                if let thumbnail {
                    let quarterTurned = (page.ref.rotation / 90) % 2 != 0
                    let upright = thumbnail.size
                    let turned = quarterTurned ? CGSize(width: upright.height, height: upright.width) : upright
                    let fit = fittedRect(for: turned, in: box).size
                    let drawn = quarterTurned ? CGSize(width: fit.height, height: fit.width) : fit
                    Image(nsImage: thumbnail)
                        .resizable()
                        .frame(width: drawn.width, height: drawn.height)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(hovering ? 0.28 : 0.18), radius: hovering ? 8 : 4, y: 2)
                        .rotationEffect(.degrees(Double(page.ref.rotation)))
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.surfaceStrong)
                        .frame(width: box.width * 0.75, height: box.height)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(width: box.width, height: box.height)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.16) : (hovering ? Theme.surface : .clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: selected ? 2 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white, Theme.accent)
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(spacing: 1) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selected ? Theme.accent : Theme.ink.opacity(0.7))
                    .contentTransition(.numericText())
                if showsSource {
                    Text(page.ref.source.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: box.width)
                }
            }
        }
        .opacity(dragging ? 0.35 : 1)
        .scaleEffect(hovering && !dragging ? 1.02 : 1)
        .animation(Theme.snappy, value: hovering)
        .animation(Theme.snappy, value: selected)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 16)
        }
        .buttonStyle(SecondaryButtonStyle())
        .help(help)
    }
}

// MARK: - Split

/// Popover for choosing how to split: every page, every N pages, or custom ranges.
struct SplitPanel: View {
    enum Mode: String, CaseIterable { case each = "Every Page", chunks = "Every N", ranges = "Ranges" }

    let pageCount: Int
    let onSplit: (SplitMode) -> Void

    @State private var mode: Mode = .each
    @State private var chunk = 2
    @State private var ranges = ""

    private var splitMode: SplitMode {
        switch mode {
        case .each: return .everyPage
        case .chunks: return .every(chunk)
        case .ranges: return .ranges(ranges)
        }
    }

    private var preview: Result<[[Int]], Error> {
        Result { try PDFPages.groups(pageCount: pageCount, mode: splitMode) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Split into separate PDFs")
                .font(.system(size: 13, weight: .semibold))
            PillPicker(options: Mode.allCases, title: \.rawValue, selection: $mode)

            Group {
                switch mode {
                case .each:
                    Text("One PDF for each of the \(pageCount) pages.")
                case .chunks:
                    Stepper(value: $chunk, in: 1...max(1, pageCount)) {
                        Text("\(chunk) pages per file").monospacedDigit()
                    }
                case .ranges:
                    TextField("e.g. 1-3, 5, 8-", text: $ranges)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(split)
                }
            }
            .font(.system(size: 12))
            .frame(height: 24, alignment: .leading)

            HStack {
                switch preview {
                case .success(let groups):
                    Label(groups.count == 1 ? "Creates 1 PDF" : "Creates \(groups.count) PDFs in a new folder",
                          systemImage: "doc.on.doc")
                        .foregroundStyle(Theme.label)
                case .failure(let error):
                    Label(mode == .ranges && ranges.isEmpty ? "Pages 1–\(pageCount)" : error.localizedDescription,
                          systemImage: mode == .ranges && ranges.isEmpty ? "info.circle" : "exclamationmark.triangle")
                        .foregroundStyle(mode == .ranges && ranges.isEmpty ? Theme.label : Color.orange)
                }
                Spacer()
                Button("Split", action: split)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled((try? preview.get()) == nil)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(16)
        .frame(width: 340)
    }

    private func split() {
        guard (try? preview.get()) != nil else { return }
        onSplit(splitMode)
    }
}
