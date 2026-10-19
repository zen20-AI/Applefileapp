import FileAppCore
import SwiftUI

/// "Edit": light and color adjustments plus rotate / flip.
struct AdjustEditor: View {
    let image: CGImage
    let onSave: (CGImage) -> Void
    let onClose: () -> Void

    @State private var adjustments = Adjustments()
    @State private var rendered: NSImage?
    private let preview: CGImage

    init(image: CGImage, onSave: @escaping (CGImage) -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.onSave = onSave
        self.onClose = onClose
        preview = BackgroundEditor.downsampled(image, maxSide: 900)
    }

    var body: some View {
        EditorScaffold(title: "Edit Image", onClose: onClose) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.25))
                    if let rendered {
                        Image(nsImage: rendered)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    }
                }
                .frame(height: 320)

                ValueSlider(title: "Brightness", value: $adjustments.brightness, range: -0.5...0.5, unit: "", format: percent)
                ValueSlider(title: "Contrast", value: $adjustments.contrast, range: 0.5...1.5, unit: "", format: { percent($0 - 1) })
                ValueSlider(title: "Saturation", value: $adjustments.saturation, range: 0...2, unit: "", format: { percent($0 - 1) })
                ValueSlider(title: "Exposure", value: $adjustments.exposure, range: -2...2, unit: "EV", format: { String(format: "%+.1f", $0) })

                HStack(spacing: 8) {
                    Button { adjustments.quarterTurns -= 1 } label: { Label("Rotate Left", systemImage: "rotate.left") }
                    Button { adjustments.quarterTurns += 1 } label: { Label("Rotate Right", systemImage: "rotate.right") }
                    Button { adjustments.flipped.toggle() } label: { Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    Spacer()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        } footer: {
            HStack {
                Button("Reset") { adjustments = Adjustments() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Save") {
                    if let result = ImageCompositor.adjust(image, adjustments) { onSave(result) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: rerender)
        .onChange(of: adjustments) { rerender() }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%+d%%", Int((value * 100).rounded()))
    }

    private func rerender() {
        rendered = ImageCompositor.adjust(preview, adjustments)?.nsImage
    }
}
