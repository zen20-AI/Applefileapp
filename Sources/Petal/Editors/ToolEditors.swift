import AppKit
import FileAppCore
import PDFKit
import SwiftUI

// MARK: - Copy Text (OCR result)

/// Shows recognised text, already copied to the clipboard, ready to tweak and copy again.
struct TextResultView: View {
    let source: URL
    @State var text: String
    let onSave: (String) -> Void
    let onClose: () -> Void
    @State private var copied = true

    var body: some View {
        EditorScaffold(title: String(localized: "Text from \(source.lastPathComponent)"), onClose: onClose) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
                .onChange(of: text) { copied = false }
        } footer: {
            HStack {
                Label(copied ? "Copied to clipboard" : "\(text.count) characters",
                      systemImage: copied ? "checkmark.circle.fill" : "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? Theme.accent : Theme.label)
                    .contentTransition(.opacity)
                Spacer()
                Button("Save as Text") { onSave(text) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(Theme.snappy) { copied = true }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - GIF / Video

struct AnimateEditor: View {
    enum Kind: String, CaseIterable { case gif = "GIF", video = "Video" }

    let urls: [URL]
    let onCreate: (Kind, Double, Int) -> Void
    let onClose: () -> Void

    @State private var kind: Kind = .gif
    @State private var seconds = 0.6
    @State private var maxSide = 800

    var body: some View {
        EditorScaffold(title: String(localized: "Animate \(urls.count) Images"), onClose: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                PillPicker(options: Kind.allCases, title: \.rawValue, selection: $kind)
                    .frame(maxWidth: .infinity)
                ValueSlider(title: String(localized: "Per image"), value: $seconds, range: 0.1...5, unit: "s",
                            format: { String(format: "%.1f", $0) })
                HStack(spacing: 8) {
                    Text("Size").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.label)
                        .frame(width: 78, alignment: .leading)
                    PillPicker(options: [480, 800, 1280, 1920], title: { "\($0) px" }, selection: $maxSide)
                }
                Text(String(localized: "Total \(String(format: "%.1f", seconds * Double(urls.count))) s · images play in list order."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        } footer: {
            HStack {
                Button("Cancel", action: onClose).buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(kind == .gif ? "Make GIF" : "Make Video") { onCreate(kind, seconds, maxSide) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: kind) { maxSide = kind == .gif ? 800 : 1920 }
    }
}

// MARK: - PDF Tools

enum PDFToolRequest {
    case lock(String), unlock(String)
    case watermark(String, Double)
    case number(PDFTools.NumberPosition, ofTotal: Bool)
    case sign(CGImage, page: Int, rect: CGRect)
}

/// Passwords, watermark, page numbers and signatures for one PDF.
struct PDFToolsEditor: View {
    enum Tab: String, CaseIterable {
        case password, watermark, numbers, sign

        var title: String {
            switch self {
            case .password: return String(localized: "Password")
            case .watermark: return String(localized: "Watermark")
            case .numbers: return String(localized: "Numbers")
            case .sign: return String(localized: "Sign")
            }
        }
    }

    let url: URL
    let onApply: (PDFToolRequest) -> Void
    let onClose: () -> Void

    @State private var tab: Tab = .password
    @State private var password = ""
    @State private var watermark = String(localized: "CONFIDENTIAL")
    @State private var opacity = 0.18
    @State private var position: PDFTools.NumberPosition = .bottomCenter
    @State private var ofTotal = false
    @StateObject private var signature = SignatureModel()
    private let locked: Bool

    init(url: URL, onApply: @escaping (PDFToolRequest) -> Void, onClose: @escaping () -> Void) {
        self.url = url
        self.onApply = onApply
        self.onClose = onClose
        locked = PDFTools.isLocked(url)
        _tab = State(initialValue: locked ? .password : .watermark)
    }

    var body: some View {
        EditorScaffold(title: url.lastPathComponent, onClose: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                PillPicker(options: locked ? [Tab.password] : Tab.allCases, title: \.title, selection: $tab)
                    .frame(maxWidth: .infinity)
                Group {
                    switch tab {
                    case .password: passwordTab
                    case .watermark: watermarkTab
                    case .numbers: numbersTab
                    case .sign: SignTab(url: url, model: signature)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        } footer: {
            HStack {
                Text(footnote).font(.system(size: 11)).foregroundStyle(Theme.label)
                Spacer()
                Button(actionTitle, action: apply)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
            }
        }
    }

    private var passwordTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(locked ? "This PDF is protected. Enter its password to save an unlocked copy."
                        : "Save a copy that asks for this password when opened.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink.opacity(0.75))
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(apply)
        }
    }

    private var watermarkTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Watermark text", text: $watermark).textFieldStyle(.roundedBorder)
            ValueSlider(title: String(localized: "Opacity"), value: $opacity, range: 0.05...0.6, unit: "%",
                        format: { String(Int(($0 * 100).rounded())) })
            Text(watermark.isEmpty ? " " : watermark)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(width: 220)
                .foregroundStyle(Color.gray.opacity(min(1, opacity * 1.6)))
                .rotationEffect(.degrees(-30))
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                .clipped()
        }
    }

    private var numbersTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Position", selection: $position) {
                Text("Bottom center").tag(PDFTools.NumberPosition.bottomCenter)
                Text("Bottom right").tag(PDFTools.NumberPosition.bottomRight)
                Text("Bottom left").tag(PDFTools.NumberPosition.bottomLeft)
                Text("Top right").tag(PDFTools.NumberPosition.topRight)
            }
            Toggle("Show the total (“3 / 12”)", isOn: $ofTotal)
        }
        .font(.system(size: 12))
    }

    private var actionTitle: String {
        switch tab {
        case .password: return locked ? String(localized: "Unlock") : String(localized: "Lock")
        case .watermark: return String(localized: "Add Watermark")
        case .numbers: return String(localized: "Add Numbers")
        case .sign: return String(localized: "Sign")
        }
    }

    private var footnote: String {
        tab == .sign ? String(localized: "Draw, then drag the signature into place.")
                     : String(localized: "Saved as a new file — the original stays as it is.")
    }

    private var canApply: Bool {
        switch tab {
        case .password: return !password.isEmpty
        case .watermark: return !watermark.trimmingCharacters(in: .whitespaces).isEmpty
        case .numbers: return true
        case .sign: return signature.image != nil
        }
    }

    private func apply() {
        guard canApply else { return }
        switch tab {
        case .password: onApply(locked ? .unlock(password) : .lock(password))
        case .watermark: onApply(.watermark(watermark, opacity))
        case .numbers: onApply(.number(position, ofTotal: ofTotal))
        case .sign:
            guard let image = signature.image else { return }
            signature.remember()
            onApply(.sign(image, page: signature.page, rect: signature.placement))
        }
    }
}

// MARK: Signature

@MainActor
final class SignatureModel: ObservableObject {
    @Published var strokes: [[CGPoint]] = []
    @Published var page = 0
    /// Normalised placement on the page (origin bottom-left).
    @Published var placement = CGRect(x: 0.58, y: 0.06, width: 0.32, height: 0.1)
    @Published private(set) var image: CGImage?
    /// Height ÷ width of the chosen page, to keep the signature's proportions when placing it.
    var pageAspect: CGFloat = 1.294 { didSet { fitPlacementToImage() } }
    private static let padSize = CGSize(width: 300, height: 110)

    init() {
        if let data = UserDefaults.standard.data(forKey: "lastSignature"),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            fitPlacementToImage()
        }
    }

    func clear() {
        strokes = []
        image = nil
    }

    func render() {
        image = Self.render(strokes)
        fitPlacementToImage()
    }

    func remember() {
        guard let image else { return }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) { UserDefaults.standard.set(data as Data, forKey: "lastSignature") }
    }

    private func fitPlacementToImage() {
        guard let image else { return }
        let aspect = CGFloat(image.height) / CGFloat(image.width)
        placement.size.height = placement.width * aspect / max(pageAspect, 0.1)
        placement.origin.y = min(placement.origin.y, max(0, 1 - placement.height))
    }

    /// Strokes → a tight, transparent, high-resolution image.
    private static func render(_ strokes: [[CGPoint]]) -> CGImage? {
        let points = strokes.flatMap { $0 }
        guard points.count > 1 else { return nil }
        let pad: CGFloat = 6
        let minX = points.map(\.x).min()! - pad, maxX = points.map(\.x).max()! + pad
        let minY = points.map(\.y).min()! - pad, maxY = points.map(\.y).max()! + pad
        let scale: CGFloat = 4
        let width = Int((maxX - minX) * scale), height = Int((maxY - minY) * scale)
        guard width > 0, height > 0, let ctx = ImageFile.makeContext(width: width, height: height) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // View coordinates grow downwards.
        ctx.translateBy(x: -minX, y: maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.1, blue: 0.3, alpha: 1))
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 1 {
            ctx.addLines(between: stroke)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    static var padFrame: CGSize { padSize }
}

private struct SignTab: View {
    let url: URL
    @ObservedObject var model: SignatureModel
    @State private var pageImage: NSImage?
    @State private var pageCount = 1
    @State private var drawing = false
    @State private var dragStart: CGRect?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Draw your signature").font(.system(size: 12, weight: .semibold))
                pad
                HStack {
                    Button("Clear") { model.clear() }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Stepper("Page \(model.page + 1) of \(pageCount)", value: $model.page, in: 0...max(0, pageCount - 1))
                        .font(.system(size: 11))
                }
                ValueSlider(title: String(localized: "Size"), value: Binding(
                    get: { model.placement.width * 100 },
                    set: { width in
                        let ratio = model.placement.height / max(model.placement.width, 0.01)
                        model.placement.size = CGSize(width: width / 100, height: width / 100 * ratio)
                    }), range: 10...80, unit: "%")
            }
            .frame(width: SignatureModel.padFrame.width)
            preview
        }
        .onAppear(perform: loadPage)
        .onChange(of: model.page) { loadPage() }
    }

    private var pad: some View {
        Canvas { context, _ in
            for stroke in model.strokes where stroke.count > 1 {
                var path = Path()
                path.addLines(stroke)
                context.stroke(path, with: .color(Color(red: 0.05, green: 0.1, blue: 0.3)),
                               style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: SignatureModel.padFrame.width, height: SignatureModel.padFrame.height)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 24)
        }
        .overlay {
            if model.strokes.isEmpty && model.image == nil {
                Text("Sign here").font(.system(size: 12)).foregroundStyle(Color.gray)
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !drawing { model.strokes.append([]); drawing = true }
                model.strokes[model.strokes.count - 1].append(value.location)
            }
            .onEnded { _ in
                drawing = false
                model.render()
            })
    }

    /// The page with the signature on it; drag the signature to move it.
    private var preview: some View {
        GeometryReader { proxy in
            let size = pageImage.map { fittedRect(for: $0.size, in: proxy.size).size } ?? proxy.size
            ZStack(alignment: .topLeading) {
                if let pageImage {
                    Image(nsImage: pageImage).resizable().frame(width: size.width, height: size.height)
                } else {
                    Color.white.frame(width: size.width, height: size.height)
                }
                if let image = model.image {
                    let rect = model.placement
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width * size.width, height: rect.height * size.height)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .offset(x: rect.minX * size.width, y: (1 - rect.maxY) * size.height)
                        .gesture(DragGesture()
                            .onChanged { value in
                                let start = dragStart ?? rect
                                dragStart = start
                                var moved = start
                                moved.origin.x = min(max(0, start.minX + value.translation.width / size.width), 1 - start.width)
                                moved.origin.y = min(max(0, start.minY - value.translation.height / size.height), 1 - start.height)
                                model.placement = moved
                            }
                            .onEnded { _ in dragStart = nil })
                        .help("Drag to place")
                }
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 270)
    }

    private func loadPage() {
        guard let document = PDFDocument(url: url) else { return }
        pageCount = document.pageCount
        guard let page = document.page(at: model.page) else { return }
        pageImage = page.thumbnail(of: CGSize(width: 600, height: 600), for: .cropBox)
        if let size = pageImage?.size, size.width > 0 { model.pageAspect = size.height / size.width }
    }
}

// MARK: - Batch rename

struct RenameEditor: View {
    let urls: [URL]
    let onRename: (RenamePattern) -> Void
    let onClose: () -> Void

    @State private var template = String(localized: "Photo {n}")
    @State private var start = 1

    private var pattern: RenamePattern { RenamePattern(template: template, start: start) }

    var body: some View {
        EditorScaffold(title: String(localized: "Rename \(urls.count) Files"), onClose: onClose) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $template).textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    ForEach(["{name}", "{n}", "{date}"], id: \.self) { token in
                        Button(token) { template += (template.hasSuffix(" ") || template.isEmpty ? "" : " ") + token }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    Stepper("Start at \(start)", value: $start, in: 0...9999).font(.system(size: 11))
                }
                VStack(alignment: .leading, spacing: 4) {
                    let preview = BatchRenamer.preview(Array(urls.prefix(6)), pattern: pattern)
                    ForEach(Array(zip(urls.prefix(6), preview)), id: \.0) { old, new in
                        HStack(spacing: 6) {
                            Text(old.lastPathComponent).foregroundStyle(Theme.label).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.label)
                            Text(new.lastPathComponent).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    if urls.count > 6 { Text("…and \(urls.count - 6) more").foregroundStyle(Theme.label) }
                }
                .font(.system(size: 11))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                Spacer(minLength: 0)
            }
        } footer: {
            HStack {
                Text("{n} counts up · {date} is the file's date").font(.system(size: 11)).foregroundStyle(Theme.label)
                Spacer()
                Button("Rename") { onRename(pattern) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(template.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
