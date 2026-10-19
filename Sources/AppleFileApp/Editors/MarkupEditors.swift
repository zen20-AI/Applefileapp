import AppKit
import FileAppCore
import SwiftUI

/// Image with an overlay laid out in the image's fitted frame; reports drags in normalized coordinates.
private struct MarkupCanvas<Overlay: View>: View {
    let image: CGImage
    let onDrag: (_ start: CGPoint, _ current: CGPoint) -> Void
    let onEnd: () -> Void
    @ViewBuilder let overlay: (_ frame: CGRect) -> Overlay

    var body: some View {
        GeometryReader { proxy in
            let frame = fittedRect(for: image.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image.nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                overlay(frame)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDrag(normalize(value.startLocation, in: frame), normalize(value.location, in: frame))
                    }
                    .onEnded { _ in onEnd() }
            )
        }
    }

    private func normalize(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - frame.minX) / frame.width, 0), 1),
            y: min(max((point.y - frame.minY) / frame.height, 0), 1))
    }
}

private func denormalize(_ point: CGPoint, in frame: CGRect) -> CGPoint {
    CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
}

private func denormalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
    CGRect(
        x: frame.minX + rect.minX * frame.width,
        y: frame.minY + rect.minY * frame.height,
        width: rect.width * frame.width,
        height: rect.height * frame.height)
}

// MARK: - Annotate

struct AnnotateEditor: View {
    let image: CGImage
    let onSave: (CGImage) -> Void
    let onClose: () -> Void

    private static let palette: [Color] = [
        Color(red: 1, green: 0.23, blue: 0.19), Theme.accent, Color(red: 1, green: 0.84, blue: 0.04),
        Color(red: 0.2, green: 0.78, blue: 0.35), Color(red: 0, green: 0.48, blue: 1), .black, .white,
    ]

    @State private var strokes: [AnnotationStroke] = []
    @State private var current: AnnotationStroke?
    @State private var color: Color = Self.palette[0]
    @State private var width: Double = 6
    @State private var highlighter = false

    var body: some View {
        EditorScaffold(title: "Annotate", onClose: onClose) {
            VStack(spacing: 14) {
                MarkupCanvas(image: image, onDrag: { _, point in
                    if current == nil {
                        current = AnnotationStroke(
                            points: [],
                            color: NSColor(color).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0, alpha: 1),
                            width: CGFloat(width) / 1000 * (highlighter ? 3 : 1),
                            isHighlighter: highlighter)
                    }
                    current?.points.append(point)
                }, onEnd: {
                    if let current { strokes.append(current) }
                    current = nil
                }) { frame in
                    Canvas { context, _ in
                        for stroke in strokes + (current.map { [$0] } ?? []) where !stroke.points.isEmpty {
                            var path = Path()
                            path.addLines(stroke.points.map { denormalize($0, in: frame) })
                            if stroke.points.count == 1 { path.addLine(to: denormalize(stroke.points[0], in: frame)) }
                            let lineWidth = stroke.width * min(frame.width, frame.height)
                            context.stroke(
                                path,
                                with: .color(Color(cgColor: stroke.color).opacity(stroke.isHighlighter ? 0.4 : 1)),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(minHeight: 380)

                HStack(spacing: 10) {
                    PillPicker(options: [false, true], title: { $0 ? "Highlighter" : "Pen" }, selection: $highlighter)
                    ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, swatch in
                        Circle()
                            .fill(swatch)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(swatch == color ? Theme.ink : Color.white.opacity(0.7), lineWidth: 2))
                            .onTapGesture { color = swatch }
                    }
                    Spacer()
                }
                ValueSlider(title: "Size", value: $width, range: 2...30, unit: "")
            }
        } footer: {
            HStack {
                Button("Undo") { _ = strokes.popLast() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
                Button("Clear") { strokes.removeAll() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Save") {
                    if let result = ImageCompositor.annotate(image, strokes: strokes) { onSave(result) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(strokes.isEmpty)
            }
        }
    }
}

// MARK: - Redact

struct RedactEditor: View {
    let image: CGImage
    let onSave: (CGImage) -> Void
    let onClose: () -> Void

    @State private var rects: [CGRect] = []
    @State private var current: CGRect?
    @State private var style: RedactionStyle = .black

    var body: some View {
        EditorScaffold(title: "Redact", onClose: onClose) {
            VStack(spacing: 14) {
                MarkupCanvas(image: image, onDrag: { start, point in
                    current = CGRect(
                        x: min(start.x, point.x), y: min(start.y, point.y),
                        width: abs(point.x - start.x), height: abs(point.y - start.y))
                }, onEnd: {
                    if let current, current.width > 0.005, current.height > 0.005 { rects.append(current) }
                    current = nil
                }) { frame in
                    ForEach(Array((rects + (current.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, rect in
                        let box = denormalize(rect, in: frame)
                        Rectangle()
                            .fill(style == .black ? Color.black : Color.gray.opacity(0.85))
                            .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 1))
                            .frame(width: box.width, height: box.height)
                            .offset(x: box.minX, y: box.minY)
                    }
                    .allowsHitTesting(false)
                }
                .frame(minHeight: 400)

                HStack {
                    Text("Drag over anything you want hidden.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink.opacity(0.65))
                    Spacer()
                    PillPicker(options: RedactionStyle.allCases, title: \.label, selection: $style)
                }
            }
        } footer: {
            HStack {
                Button("Undo") { _ = rects.popLast() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
                Button("Clear") { rects.removeAll() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Save Redacted") {
                    if let result = ImageCompositor.redact(image, rects: rects, style: style) { onSave(result) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(rects.isEmpty)
            }
        }
    }
}
