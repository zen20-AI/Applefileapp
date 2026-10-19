import FileAppCore
import ImageIO
import SwiftUI

/// "Resize": scales every selected image by a percentage or to fit a maximum side.
struct ResizeEditor: View {
    enum Mode: String, CaseIterable { case percent = "Percent", maxSide = "Max Side" }

    let urls: [URL]
    let onSave: (ResizeMode) -> Void
    let onClose: () -> Void

    @State private var mode: Mode = .percent
    @State private var percent: Double = 50
    @State private var maxSide: Double = 1920
    private let firstSize: CGSize?

    init(urls: [URL], onSave: @escaping (ResizeMode) -> Void, onClose: @escaping () -> Void) {
        self.urls = urls
        self.onSave = onSave
        self.onClose = onClose
        firstSize = urls.first.flatMap { url in
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(ImageFile.pixelSize(of:))
        }
    }

    private var resizeMode: ResizeMode {
        mode == .percent ? .percent(percent / 100) : .maxSide(Int(maxSide))
    }

    var body: some View {
        EditorScaffold(title: urls.count == 1 ? "Resize Image" : "Resize \(urls.count) Images", onClose: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                PillPicker(options: Mode.allCases, title: \.rawValue, selection: $mode)
                    .frame(maxWidth: .infinity)

                if mode == .percent {
                    ValueSlider(title: "Scale", value: $percent, range: 5...200, unit: "%")
                    presets([25, 50, 75, 150], binding: $percent, suffix: "%")
                } else {
                    ValueSlider(title: "Max Side", value: $maxSide, range: 64...8000)
                    presets([640, 1280, 1920, 3840], binding: $maxSide, suffix: "px")
                }

                if let firstSize {
                    let target = Resizer.targetSize(for: firstSize, mode: resizeMode)
                    HStack {
                        Text("\(Int(firstSize.width)) × \(Int(firstSize.height))")
                        Image(systemName: "arrow.right")
                        Text("\(Int(target.width)) × \(Int(target.height)) px")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .frame(maxWidth: .infinity)
                }

                Text("Saved as “… Resized” copies — originals are never changed.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        } footer: {
            HStack {
                Button("Cancel", action: onClose)
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Resize") { onSave(resizeMode) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func presets(_ values: [Double], binding: Binding<Double>, suffix: String) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button("\(Int(value)) \(suffix)") { binding.wrappedValue = value }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }
}
