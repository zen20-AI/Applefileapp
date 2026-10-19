import FileAppCore
import SwiftUI

struct CropEditor: View {
    let image: CGImage
    let onSave: (CGImage) -> Void
    let onClose: () -> Void

    @State private var rect = CropMath.unit
    @State private var aspect: CropAspect = .free
    @State private var dragHandle: CropHandle?
    @State private var dragStartRect = CropMath.unit
    @State private var widthText = ""
    @State private var heightText = ""

    private var imageSize: CGSize { image.size }

    var body: some View {
        EditorScaffold(title: "Crop Image", onClose: onClose) {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    canvas(in: proxy.size)
                }
                .frame(minHeight: 380)

                HStack {
                    Text("Aspect ratio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.label)
                    Spacer()
                    PillPicker(options: CropAspect.allCases, title: \.label, selection: $aspect)
                }

                HStack(spacing: 8) {
                    sizeField("W", text: $widthText)
                    sizeField("H", text: $heightText)
                    Text("px")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                    Spacer()
                }
            }
        } footer: {
            HStack {
                Button("Reset") { reset() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Apply") {
                    if let cropped = ImageCompositor.crop(image, to: rect) { onSave(cropped) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: syncFields)
        .onChange(of: rect) { syncFields() }
        .onChange(of: aspect) {
            if let ratio = aspect.ratio {
                rect = CropMath.fit(aspect: ratio, imageSize: imageSize, around: rect)
            }
        }
    }

    private func canvas(in container: CGSize) -> some View {
        let frame = fittedRect(for: imageSize, in: container)
        let crop = CGRect(
            x: frame.minX + rect.minX * frame.width,
            y: frame.minY + rect.minY * frame.height,
            width: rect.width * frame.width,
            height: rect.height * frame.height)

        return ZStack(alignment: .topLeading) {
            Image(nsImage: image.nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)

            // Dim everything outside the crop.
            Path { path in
                path.addRect(frame)
                path.addRect(crop)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(Theme.accent, lineWidth: 2)
                .frame(width: crop.width, height: crop.height)
                .offset(x: crop.minX, y: crop.minY)

            ForEach(handleMarks(for: crop)) { mark in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(width: mark.size.width, height: mark.size.height)
                    .position(mark.point)
            }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragHandle == nil {
                        dragHandle = handle(at: value.startLocation, crop: crop)
                        dragStartRect = rect
                    }
                    guard let handle = dragHandle, frame.width > 0, frame.height > 0 else { return }
                    let translation = CGSize(
                        width: value.translation.width / frame.width,
                        height: value.translation.height / frame.height)
                    rect = CropMath.drag(handle, start: dragStartRect, translation: translation, aspect: aspect.ratio, imageSize: imageSize)
                }
                .onEnded { _ in dragHandle = nil }
        )
    }

    private struct HandleMark: Identifiable {
        let id: Int
        let point: CGPoint
        let size: CGSize
    }

    private func handleMarks(for crop: CGRect) -> [HandleMark] {
        let corner = CGSize(width: 12, height: 12)
        let horizontal = CGSize(width: 18, height: 6)
        let vertical = CGSize(width: 6, height: 18)
        return [
            HandleMark(id: 0, point: CGPoint(x: crop.minX, y: crop.minY), size: corner),
            HandleMark(id: 1, point: CGPoint(x: crop.midX, y: crop.minY), size: horizontal),
            HandleMark(id: 2, point: CGPoint(x: crop.maxX, y: crop.minY), size: corner),
            HandleMark(id: 3, point: CGPoint(x: crop.maxX, y: crop.midY), size: vertical),
            HandleMark(id: 4, point: CGPoint(x: crop.maxX, y: crop.maxY), size: corner),
            HandleMark(id: 5, point: CGPoint(x: crop.midX, y: crop.maxY), size: horizontal),
            HandleMark(id: 6, point: CGPoint(x: crop.minX, y: crop.maxY), size: corner),
            HandleMark(id: 7, point: CGPoint(x: crop.minX, y: crop.midY), size: vertical),
        ]
    }

    private func handle(at point: CGPoint, crop: CGRect) -> CropHandle? {
        let tolerance: CGFloat = 14
        let nearLeft = abs(point.x - crop.minX) < tolerance
        let nearRight = abs(point.x - crop.maxX) < tolerance
        let nearTop = abs(point.y - crop.minY) < tolerance
        let nearBottom = abs(point.y - crop.maxY) < tolerance
        let insideX = point.x > crop.minX - tolerance && point.x < crop.maxX + tolerance
        let insideY = point.y > crop.minY - tolerance && point.y < crop.maxY + tolerance

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: break
        }
        if nearTop && insideX { return .top }
        if nearBottom && insideX { return .bottom }
        if nearLeft && insideY { return .left }
        if nearRight && insideY { return .right }
        if crop.contains(point) { return .move }
        return nil
    }

    private func sizeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.label)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 72)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                .onSubmit(applyFields)
        }
    }

    private func syncFields() {
        let pixels = CropMath.pixelRect(rect, imageSize: imageSize)
        widthText = String(Int(pixels.width))
        heightText = String(Int(pixels.height))
    }

    private func applyFields() {
        guard var width = Double(widthText), var height = Double(heightText), width > 0, height > 0 else {
            syncFields()
            return
        }
        if let ratio = aspect.ratio {
            // Keep the ratio locked: follow whichever field changed.
            let current = CropMath.pixelRect(rect, imageSize: imageSize)
            if Int(width) != Int(current.width) { height = width / ratio } else { width = height * ratio }
        }
        rect = CropMath.resize(rect, toPixels: CGSize(width: width, height: height), imageSize: imageSize)
        syncFields()
    }

    private func reset() {
        aspect = .free
        rect = CropMath.unit
    }
}
