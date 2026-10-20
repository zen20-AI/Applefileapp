import AppKit
import FileAppCore
import SwiftUI

struct ManagerView: View {
    let coordinator: AppCoordinator
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var navigation: ManagerNavigation
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.section }, set: { if let s = $0 { navigation.section = s } })) {
                ForEach(ManagerSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch navigation.section {
                case .workspace: WorkspaceView(coordinator: coordinator, workspace: workspace)
                case .history: HistoryView(history: history, workspace: workspace, navigation: navigation)
                case .automation: AutomationView(watcher: .shared, settings: settings)
                case .settings: SettingsView(settings: settings)
                case .about: AboutView(history: history)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground(material: .underWindowBackground))
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: navigation.section)
        }
        .tint(Theme.accent)
    }

    private func badge(for section: ManagerSection) -> Int {
        switch section {
        case .workspace: return workspace.files.count
        case .history: return history.entries.count
        default: return 0
        }
    }
}

// MARK: - Workspace

struct WorkspaceView: View {
    let coordinator: AppCoordinator
    @ObservedObject var workspace: WorkspaceModel
    @State private var isTargeted = false

    private var targets: [URL] { workspace.targets }

    var body: some View {
        VStack(spacing: 0) {
            if workspace.files.isEmpty {
                dropZone
            } else {
                fileList
            }
            Divider()
            statusBar
        }
        .dropDestination(for: URL.self) { urls, _ in
            withAnimation(Theme.spring) { workspace.add(urls) }
            return !urls.isEmpty
        } isTargeted: { targeted in withAnimation(Theme.snappy) { isTargeted = targeted } }
        .navigationTitle("Workspace")
        .toolbar { toolbar }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(isTargeted ? 0.18 : 0.08))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isTargeted ? 1.12 : 1)
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accentGradient)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(y: isTargeted ? 4 : 0)
            }
            .padding(.bottom, 4)
            Text(isTargeted ? "Release to add" : "Drop files or folders here")
                .font(.title2.weight(.semibold))
                .contentTransition(.opacity)
            Text("Images, PDFs and documents. Then convert, compress, resize, merge, split or edit them in one go.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Add Files…") { workspace.chooseFiles() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 6]))
                .foregroundStyle(isTargeted ? Theme.accent : Color.secondary.opacity(0.3))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isTargeted ? Theme.accent.opacity(0.05) : .clear))
                .padding(24))
    }

    private var fileList: some View {
        List(selection: $workspace.selection) {
            ForEach(workspace.files) { file in
                FileRow(file: file, thumbnail: workspace.thumbnails[file.url])
                    .tag(file.url)
                    .onDrag { NSItemProvider(object: file.url as NSURL) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .contextMenu { rowMenu(file) }
            }
            .onDelete { offsets in
                workspace.remove(Set(offsets.map { workspace.files[$0].url }))
            }
            .onMove { from, to in workspace.move(from: from, to: to) }
        }
        .onDeleteCommand { withAnimation(Theme.spring) { workspace.remove(workspace.selection) } }
        .animation(Theme.spring, value: workspace.files.map(\.url))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 3).padding(4)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ file: WorkspaceFile) -> some View {
        Button("Open") { NSWorkspace.shared.open(file.url) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        if file.kind == .pdf || file.kind == .image {
            Button("Organize Pages…") { coordinator.organizePages(menuTargets(file)) }
        }
        if file.kind == .pdf {
            Button("Split into Single Pages") { coordinator.splitPages(menuTargets(file)) }
        }
        if TextRecognizer.canRecognize(file.url) {
            Button("Copy Text") { coordinator.copyText(menuTargets(file)) }
        }
        Button("Rename…") { coordinator.rename(menuTargets(file)) }
        Divider()
        Button("Remove from List") { workspace.remove(Set(menuTargets(file))) }
        Button("Move to Trash", role: .destructive) { withAnimation(Theme.spring) { workspace.trash(menuTargets(file)) } }
    }

    /// Context-menu actions apply to the selection when the clicked row is in it, otherwise to that row.
    private func menuTargets(_ file: WorkspaceFile) -> [URL] {
        workspace.selection.contains(file.url) ? workspace.targets : [file.url]
    }

    private var statusBar: some View {
        HStack {
            Text("\(workspace.files.count) files · \(ByteFormatter.string(workspace.totalSize))")
                .contentTransition(.numericText())
            if !workspace.selection.isEmpty {
                Text("· \(workspace.selection.count) selected")
            }
            Spacer()
            Text(workspace.selection.isEmpty ? "Actions apply to all files · drag rows out to share" : "Actions apply to the selection")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { workspace.chooseFiles() } label: { Label("Add Files", systemImage: "plus") }
                .help("Add files or folders")
            Button { workspace.remove(workspace.selection.isEmpty ? Set(workspace.files.map(\.url)) : workspace.selection) } label: {
                Label("Remove", systemImage: "minus")
            }
            .help("Remove the selection (or everything) from the list")
            .disabled(workspace.files.isEmpty)
            Menu {
                ForEach(WorkspaceModel.SortOrder.allCases) { order in
                    Button(order.title) { withAnimation(Theme.spring) { workspace.sort(by: order) } }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort the list (it sets the merge order)")
            .disabled(workspace.files.count < 2)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(OutputFormat.allCases) { format in
                    Button(format.label) { coordinator.perform(.convert(format), on: targets) }
                        .disabled(!targets.contains { Converter.isAvailable(format, for: $0) })
                }
            } label: {
                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Convert to another format")

            Menu {
                Button("Best Quality") { coordinator.compress(targets, limit: nil) }
                Divider()
                ForEach(Compressor.sizeLimits, id: \.self) { limit in
                    Button(String(localized: "Under \(ByteFormatter.limit(limit))")) { coordinator.compress(targets, limit: limit) }
                }
            } label: {
                Label("Compress", systemImage: Tool.compress.symbol)
            } primaryAction: {
                coordinator.perform(.tool(.compress), on: targets)
            }
            .help("Make images, PDFs and videos smaller · hold the arrow to pick a size limit")
            .disabled(!Tool.compress.isAvailable(for: targets))

            Menu {
                toolButton(.resize)
                toolButton(.cutOut)
                Button { coordinator.stripMetadata(targets) } label: {
                    Label("Remove Metadata", systemImage: "location.slash")
                }
                .disabled(!Tool.metadata.isAvailable(for: targets))
                toolButton(.animate)
                Divider()
                ForEach([Tool.crop, .edit, .annotate, .redact, .addBackground, .metadata]) { tool in
                    toolButton(tool)
                }
            } label: {
                Label("Image", systemImage: "photo")
            }
            .help("Resize, cut out, animate or edit images")
            .disabled(!targets.contains { FileKind(url: $0) == .image })

            Menu {
                Button { coordinator.merge(targets) } label: {
                    Label("Merge into One PDF", systemImage: Tool.merge.symbol)
                }
                .disabled(!Tool.merge.isAvailable(for: targets))
                Button { coordinator.organizePages(targets) } label: {
                    Label("Organize Pages…", systemImage: Tool.pages.symbol)
                }
                .disabled(!Tool.pages.isAvailable(for: targets))
                Button { coordinator.splitPages(targets) } label: {
                    Label("Split into Single Pages", systemImage: Tool.split.symbol)
                }
                .disabled(!targets.contains { FileKind(url: $0) == .pdf })
                Divider()
                toolButton(.secure, title: String(localized: "Password, Watermark, Numbers, Sign…"))
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            .help("Merge, organize, split, protect or sign PDFs (merging follows list order)")
            .disabled(!Tool.pages.isAvailable(for: targets))

            Button { coordinator.copyText(targets) } label: {
                Label("Copy Text", systemImage: Tool.copyText.symbol)
            }
            .help("Read the text in images and PDFs (Thai and English, on this Mac)")
            .disabled(!Tool.copyText.isAvailable(for: targets))

            Button { coordinator.rename(targets) } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
            .help("Rename files from a pattern, e.g. “Trip {n}”")
            .disabled(targets.isEmpty)

            Button { coordinator.showRing(for: targets) } label: {
                Label("Ring", systemImage: "circle.hexagongrid.circle")
            }
            .help("Open the radial ring for these files")
            .disabled(targets.isEmpty)
        }
    }

    private func toolButton(_ tool: Tool, title: String? = nil) -> some View {
        Button { coordinator.perform(.tool(tool), on: targets) } label: {
            Label(title ?? tool.title, systemImage: tool.symbol)
        }
        .disabled(!tool.isAvailable(for: targets))
    }
}

struct FileRow: View {
    let file: WorkspaceFile
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc")
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path.abbreviatingWithTilde)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Text(file.url.pathExtension.uppercased())
                .font(.caption.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.opacity(0.15)))
                .foregroundStyle(Theme.accent)
            Text(ByteFormatter.string(file.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var navigation: ManagerNavigation
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [HistoryEntry] {
        guard !search.isEmpty else { return history.entries }
        return history.entries.filter { entry in
            entry.action.localizedCaseInsensitiveContains(search)
                || entry.outputs.contains { $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
                || entry.sources.contains { $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView("No History Yet", systemImage: "clock",
                                       description: Text("Files you convert or edit will show up here."))
            } else {
                List {
                    ForEach(filtered) { entry in
                        HistoryRow(entry: entry, onAddToWorkspace: {
                            workspace.add(entry.outputs)
                            navigation.section = .workspace
                        }, onRemove: { history.remove([entry.id]) })
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $search, placement: .toolbar, prompt: "Search files or actions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { history.pruneMissing() } label: { Label("Clean Up", systemImage: "sparkles") }
                    .help("Remove entries whose files no longer exist")
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear", systemImage: "trash") }
                    .help("Clear all history (files are kept)")
                    .disabled(history.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("This only clears the list. Your files stay where they are.")
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let onAddToWorkspace: () -> Void
    let onRemove: () -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(entry.outputs, id: \.self) { url in
                let exists = FileManager.default.fileExists(atPath: url.path)
                HStack {
                    Image(systemName: exists ? "doc.fill" : "questionmark.folder")
                        .foregroundStyle(exists ? Theme.accent : .secondary)
                    Text(url.lastPathComponent)
                        .strikethrough(!exists)
                        .foregroundStyle(exists ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if exists {
                        Button("Open") { NSWorkspace.shared.open(url) }
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } else {
                        Text("Missing").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.link)
                .onDrag { NSItemProvider(object: url as NSURL) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.action).font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                Button("Reveal All in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(entry.outputs.filter { FileManager.default.fileExists(atPath: $0.path) })
                }
                Button("Add Results to Workspace", action: onAddToWorkspace)
                Divider()
                Button("Remove from History", action: onRemove)
            }
        }
    }

    private var summary: String {
        var parts = ["\(entry.sources.count) in → \(entry.outputs.count) out"]
        if entry.failures > 0 { parts.append("\(entry.failures) failed") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { settings.launchAtLogin = launchAtLogin }
                Toggle("Always show Dock icon", isOn: $settings.showDockIcon)
                Toggle("Reveal results in Finder after saving", isOn: $settings.revealAfterSaving)
                Toggle("Keep new results on the Shelf", isOn: $settings.shelfCollectsResults)
            }

            LanguageSection()

            Section {
                FolderAccessList(access: .shared)
                HStack {
                    Button("Allow All") { FolderAccess.shared.requestAll() }
                        .disabled(FolderAccess.shared.allGranted)
                    Button("Full Disk Access…") { FolderAccess.shared.openFullDiskAccessSettings() }
                }
            } header: {
                Text("Folder Access")
            } footer: {
                Text("Lets Petal read and save files in these folders without asking each time. For external drives and everything else, add Petal under Full Disk Access.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show the ring when dragging files", isOn: $settings.ringEnabled)
                LabeledContent("Drag distance before it opens") {
                    HStack {
                        Slider(value: $settings.activationDistance, in: 8...120, step: 4)
                            .frame(width: 200)
                        Text("\(Int(settings.activationDistance)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                .disabled(!settings.ringEnabled)
            } header: {
                Text("Drag Ring")
            } footer: {
                Text("Hold a dragged file over the hub to switch between the Convert and Tools rings.")
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                Picker("Save results", selection: $settings.useCustomFolder) {
                    Text("Next to the original").tag(false)
                    Text("In a folder").tag(true)
                }
                if settings.useCustomFolder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(settings.customFolderPath.isEmpty ? "None chosen" : settings.customFolderPath.abbreviatingWithTilde)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Choose…") { settings.chooseCustomFolder() }
                        }
                    }
                }
            }

            Section("Quality") {
                LabeledContent("JPG / HEIC conversion") {
                    qualitySlider($settings.lossyQuality, range: 0.5...1)
                }
                Picker("Compress to", selection: $settings.compressLimit) {
                    Text("Best quality").tag(Int64(0))
                    Divider()
                    ForEach(Compressor.sizeLimits, id: \.self) { limit in
                        Text(String(localized: "Under \(ByteFormatter.limit(limit))")).tag(limit)
                    }
                }
                if settings.compressLimit == 0 {
                    LabeledContent("Compression") {
                        qualitySlider($settings.compressQuality, range: 0.2...0.9)
                    }
                }
                Picker("Video compression", selection: $settings.videoQualityRaw) {
                    ForEach(MediaMaker.VideoQuality.allCases, id: \.rawValue) { quality in
                        Text(quality.label).tag(quality.rawValue)
                    }
                }
                Picker("PDF → image resolution", selection: $settings.pdfDPI) {
                    Text("72 dpi (screen)").tag(72.0)
                    Text("150 dpi").tag(150.0)
                    Text("300 dpi (print)").tag(300.0)
                    Text("600 dpi").tag(600.0)
                }
            }

            UpdatesSection()

            Section {
                Button("Restore Defaults") { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func qualitySlider(_ value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range, step: 0.05).frame(width: 200)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").monospacedDigit().frame(width: 50, alignment: .trailing)
        }
    }
}

struct UpdatesSection: View {
    @ObservedObject private var updater = Updater.shared
    @State private var automatic = Updater.shared.automaticallyChecks

    var body: some View {
        Section {
            if updater.isConfigured {
                Toggle("Check for updates automatically", isOn: $automatic)
                    .onChange(of: automatic) { updater.automaticallyChecks = automatic }
                LabeledContent("Last checked") {
                    Text(updater.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                        .foregroundStyle(.secondary)
                }
                Button("Check for Updates Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } else {
                Text("Updates are turned off in this build (no update feed configured).")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Updates")
        }
    }
}

// MARK: - About

struct AboutView: View {
    @ObservedObject var history: HistoryStore

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                Text("Petal").font(.largeTitle.weight(.bold))
                Text(version).foregroundStyle(.secondary)
                Text("\(history.totalOutputs) files created so far")
                    .font(.callout)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 12) {
                    tip("hand.draw", "Drag any file", "Start dragging a file from Finder and the ring appears beside the pointer. Drop it on a petal.")
                    tip("circle.hexagongrid.circle", "Switch rings", "Hold the file over the hub for half a second to flip between Convert and Tools.")
                    tip("tray.full", "Work in batches", "Use the Workspace to convert, compress, resize, merge or split many files at once. Right-click a PDF to organize its pages.")
                    tip("lock.shield", "Originals are safe", "Results are always saved as new files. Nothing is overwritten or uploaded.")
                    tip("text.viewfinder", "Read text anywhere", "Copy Text reads Thai and English from photos, screenshots and scanned PDFs — all on this Mac.")
                    tip("bolt", "Let it run by itself", "Automation watches folders, adds ⌥⌘P for Finder and Quick Actions on right-click.")
                }
                .padding(20)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }

    private func tip(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    var abbreviatingWithTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}
