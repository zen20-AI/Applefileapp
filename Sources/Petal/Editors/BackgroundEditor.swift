import AppKit
import FileAppCore
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPreset: Identifiable {
    let id: String
    let colors: [CGColor]
    var isGradient: Bool { colors.count > 1 }

    var fill: BackgroundFill {
        isGradient ? .gradient(colors, angle: -45) : .solid(colors[0])
    }

    var swatch: AnyShapeStyle {
        if isGradient {
            return AnyShapeStyle(LinearGradient(
                colors: colors.map { Color(cgColor: $0) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(Color(cgColor: colors[0]))
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    static let gradients: [BackgroundPreset] = [
        .init(id: "sunset", colors: [rgb(0xFF7A3D), rgb(0xFF5FA2), rgb(0xFFD25E)]),
        .init(id: "cloud", colors: [rgb(0xFFFFFF), rgb(0xBFD9FF)]),
        .init(id: "candy", colors: [rgb(0xFFE15E), rgb(0xFF6FB1), rgb(0x6FA8FF)]),
        .init(id: "blush", colors: [rgb(0xFBE3F2), rgb(0xD9C8FF)]),
        .init(id: "rose", colors: [rgb(0xFFB6D9), rgb(0xE35DB0)]),
        .init(id: "dusk", colors: [rgb(0xF5A142), rgb(0x8E3B76), rgb(0x1E1B3A)]),
        .init(id: "sky", colors: [rgb(0xC9E8FF), rgb(0x5BA7F7)]),
        .init(id: "ocean", colors: [rgb(0x5EE7DF), rgb(0x2F80ED)]),
        .init(id: "frost", colors: [rgb(0xFFFFFF), rgb(0xE6E9F0)]),
    ]

    private static let solidHexes: [UInt32] = [
        0xFFFFFF, 0xF4D35E, 0x9BC53D, 0x2E8B57, 0x2A9D8F, 0x48CAE4, 0x3A86FF, 0x1D3557, 0x8E7DFF,
    ]

    static let solids: [BackgroundPreset] = solidHexes.map { hex in
        BackgroundPreset(id: String(hex, radix: 16), colors: [rgb(hex)])
    }
}

struct BackgroundEditor: View {
    let image: CGImage
    let onSave: (CGImage) -> Void
    let onClose: () -> Void

    @State private var preview: CGImage
    @State private var rendered: NSImage?
    @State private var selectedPreset = BackgroundPreset.gradients[0].id
    @State private var fill: BackgroundFill = BackgroundPreset.gradients[0].fill
    @State private var customColor = Color.blue
    @State private var padding: Double
    @State private var corners: Double
    @State private var shadow: Double = 24
    @State private var ratio: CanvasRatio = .auto

    private let maxPadding: Double
    private let maxCorners: Double

    init(image: CGImage, onSave: @escaping (CGImage) -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.onSave = onSave
        self.onClose = onClose
        let shortSide = Double(min(image.width, image.height))
        maxPadding = max(shortSide * 0.6, 50)
        maxCorners = max(shortSide * 0.25, 20)
        _padding = State(initialValue: (shortSide * 0.12).rounded())
        _corners = State(initialValue: (shortSide * 0.03).rounded())
        _preview = State(initialValue: Self.downsampled(image, maxSide: 900))
    }

    private var previewScale: CGFloat { CGFloat(preview.width) / CGFloat(image.width) }

    private var options: BackgroundOptions {
        BackgroundOptions(fill: fill, padding: padding, cornerRadius: corners, shadow: shadow, ratio: ratio)
    }

    var body: some View {
        EditorScaffold(title: "Add BG", onClose: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                    if let rendered {
                        Image(nsImage: rendered)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                .frame(height: 300)

                HStack(alignment: .top, spacing: 12) {
                    Text("Background")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.label)
                        .frame(width: 78, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(BackgroundPreset.gradients) { swatch($0) }
                            Button(action: pickBackgroundImage) {
                                Image(systemName: "photo")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.ink.opacity(0.7))
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surfaceStrong))
                            }
                            .buttonStyle(.plain)
                            .help("Use an image as the background")
                        }
                        HStack(spacing: 8) {
                            ForEach(BackgroundPreset.solids) { swatch($0) }
                            ColorPicker("", selection: $customColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 26)
                        }
                    }
                }

                ValueSlider(title: "Padding", value: $padding, range: 0...maxPadding)
                ValueSlider(title: "Corners", value: $corners, range: 0...maxCorners)
                ValueSlider(title: "Shadow", value: $shadow, range: 0...120)

                HStack {
                    Text("Ratio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.label)
                    Spacer()
                    PillPicker(options: CanvasRatio.allCases, title: \.label, selection: $ratio)
                }
            }
        } footer: {
            HStack {
                Button("Reset", action: reset)
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Save with Background") {
                    if let result = BackgroundRenderer.render(image, options: options) { onSave(result) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: rerender)
        .onChange(of: padding) { rerender() }
        .onChange(of: corners) { rerender() }
        .onChange(of: shadow) { rerender() }
        .onChange(of: ratio) { rerender() }
        .onChange(of: selectedPreset) { rerender() }
        .onChange(of: customColor) {
            selectedPreset = "custom"
            fill = .solid(NSColor(customColor).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 1, alpha: 1))
            rerender()
        }
    }

    private func swatch(_ preset: BackgroundPreset) -> some View {
        let selected = preset.id == selectedPreset
        return Button {
            fill = preset.fill
            selectedPreset = preset.id
        } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(preset.swatch)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func rerender() {
        if let result = BackgroundRenderer.render(preview, options: options, scale: previewScale) {
            rendered = result.nsImage
        }
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let background = try? ImageFile.load(url) else { return }
        fill = .image(background)
        selectedPreset = "image:\(url.path)"
        rerender()
    }

    private func reset() {
        let shortSide = Double(min(image.width, image.height))
        padding = (shortSide * 0.12).rounded()
        corners = (shortSide * 0.03).rounded()
        shadow = 24
        ratio = .auto
        fill = BackgroundPreset.gradients[0].fill
        selectedPreset = BackgroundPreset.gradients[0].id
        rerender()
    }

    static func downsampled(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = Int(CGFloat(image.width) * scale), height = Int(CGFloat(image.height) * scale)
        guard let ctx = ImageFile.makeContext(width: width, height: height) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }
}
