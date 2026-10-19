import FileAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The radial menu: free-floating glass petals around a hub showing the file.
struct RingView: View {
    @ObservedObject var model: RingModel

    /// Space between neighbouring petals, in points (constant from hub to rim).
    private let petalSpacing: CGFloat = 12
    private let rounding: CGFloat = 18

    var body: some View {
        let geometry = model.geometry
        ZStack {
            disc

            ZStack {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    petal(item, index: index, geometry: geometry)
                }
            }
            .id(model.mode)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.82).combined(with: .opacity),
                removal: .scale(scale: 1.08).combined(with: .opacity)))

            hub(geometry: geometry)
        }
        .frame(width: RingModel.diameter, height: RingModel.diameter)
        .scaleEffect(model.isPresented ? 1 : 0.88)
        .opacity(model.isPresented ? 1 : 0)
        .animation(Theme.spring, value: model.isPresented)
        .contentShape(Circle())
        .onDrop(of: [.fileURL], delegate: RingDropDelegate(model: model))
        .onContinuousHover { phase in
            guard model.interaction == .click else { return }
            switch phase {
            case .active(let location): model.updateHover(location)
            case .ended: model.updateHover(nil)
            }
        }
        .gesture(SpatialTapGesture().onEnded { model.tap(at: $0.location) })
        .animation(Theme.snappy, value: model.hover)
    }

    /// No backdrop: just a practically invisible disc so clicks and drops between petals still land here.
    private var disc: some View {
        Circle().fill(Color.black.opacity(0.01))
    }

    private func petal(_ item: RingItem, index: Int, geometry: RingGeometry) -> some View {
        let angles = geometry.angles(of: index)
        let highlighted = model.hover == .segment(index) && item.enabled
        let shape = RingSegmentShape(
            startAngle: angles.start,
            endAngle: angles.end,
            edgeInset: petalSpacing / 2 + rounding / 2,
            innerRadius: geometry.innerRadius + 10 + rounding / 2,
            outerRadius: geometry.outerRadius - rounding / 2)

        let mid = geometry.midAngle(of: index)
        let direction = CGSize(width: cos(mid), height: sin(mid))
        let labelRadius = (geometry.innerRadius + geometry.outerRadius) / 2 + 4
        let labelPosition = CGPoint(
            x: model.center.x + direction.width * labelRadius,
            y: model.center.y + direction.height * labelRadius)
        // Hovered petals lean outward; on appear they slide out from the hub.
        let push: CGFloat = highlighted ? 7 : (model.isPresented ? 0 : -26)

        return ZStack {
            GlassPetal(shape: shape, rounding: rounding, highlighted: highlighted)

            VStack(spacing: 4) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .symbolEffect(.bounce, value: highlighted)
                }
                Text(item.symbol == nil ? item.title : item.title.uppercased())
                    .font(.system(size: item.symbol == nil ? 14 : 9, weight: item.symbol == nil ? .semibold : .bold, design: .rounded))
                    .tracking(item.symbol == nil ? 0.2 : 0.5)
            }
            .foregroundStyle(highlighted ? Color.white : Theme.ink.opacity(0.82))
            .shadow(color: highlighted ? .clear : Color(nsColor: .windowBackgroundColor).opacity(0.6), radius: 2)
            .position(labelPosition)
        }
        .frame(width: RingModel.diameter, height: RingModel.diameter)
        .offset(x: direction.width * push, y: direction.height * push)
        .opacity(model.isPresented ? (item.enabled ? 1 : 0.3) : 0)
        .animation(Theme.spring.delay(model.isPresented ? Double(index) * 0.018 : 0), value: model.isPresented)
        .allowsHitTesting(false)
    }

    private func hub(geometry: RingGeometry) -> some View {
        let size = geometry.innerRadius * 2 - 4
        let highlighted = model.hover == .center
        let hoveredItem: RingItem? = {
            if case .segment(let index) = model.hover, model.items.indices.contains(index) { return model.items[index] }
            return nil
        }()

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.88)
                .overlay(Circle().fill(Color.white.opacity(highlighted ? 0.16 : 0.06)))
                .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            Circle()
                .trim(from: 0, to: model.hubFlipProgress ? 1 : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
                .animation(model.hubFlipProgress ? .linear(duration: RingModel.hubFlipDelay) : .easeOut(duration: 0.15),
                           value: model.hubFlipProgress)

            VStack(spacing: 3) {
                if let item = hoveredItem {
                    Text(item.enabled ? "Drop to" : "Not for")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.label)
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(item.enabled ? Theme.accent : Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    if let icon = model.fileIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 30, height: 30)
                            .overlay(alignment: .topTrailing) {
                                if model.urls.count > 1 {
                                    Text("\(model.urls.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(Capsule().fill(Theme.accent))
                                        .offset(x: 6, y: -4)
                                }
                            }
                    }
                    Text(model.hubTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                modeIndicator(highlighted: highlighted)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .transition(.opacity)
            .id(hoveredItem?.id ?? "idle")
        }
        .frame(width: size, height: size)
        .scaleEffect(highlighted ? 1.06 : 1)
        .allowsHitTesting(false)
    }

    private func modeIndicator(highlighted: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach([RingMode.convert, .tools], id: \.self) { mode in
                Capsule()
                    .fill(model.mode == mode ? Theme.accent : Theme.ink.opacity(highlighted ? 0.35 : 0.18))
                    .frame(width: model.mode == mode ? 14 : 5, height: 5)
            }
        }
        .animation(Theme.spring, value: model.mode)
    }
}

/// One floating piece of glass: blurred backdrop, faint tint, light edge and its own shadow.
/// The petal outline is `shape` grown by `rounding / 2`, which rounds every corner.
struct GlassPetal: View {
    let shape: RingSegmentShape
    let rounding: CGFloat
    let highlighted: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
                .mask(silhouette(grow: rounding))
                .opacity(0.82)
            Rectangle()
                .fill(highlighted ? AnyShapeStyle(Theme.accentGradient.opacity(0.92)) : AnyShapeStyle(Color.white.opacity(0.07)))
                .mask(silhouette(grow: rounding))
            // 1 pt rim: the outline grown slightly, minus the outline itself.
            Rectangle().fill(Theme.glassEdge)
                .mask {
                    ZStack {
                        silhouette(grow: rounding + 2)
                        silhouette(grow: rounding).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .opacity(highlighted ? 0.6 : 1)
        }
        .compositingGroup()
        .shadow(color: highlighted ? Theme.accent.opacity(0.45) : .black.opacity(0.13),
                radius: highlighted ? 14 : 9, y: highlighted ? 2 : 4)
    }

    private func silhouette(grow: CGFloat) -> some View {
        ZStack {
            shape.fill(Color.black)
            shape.stroke(Color.black, style: StrokeStyle(lineWidth: grow, lineJoin: .round))
        }
    }
}

/// An annular sector between two angles (radians, y-down, increasing clockwise).
/// The side edges are pulled in by `edgeInset` points, so gaps between petals stay even.
struct RingSegmentShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var edgeInset: CGFloat = 0
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerTrim = Double(asin(min(1, edgeInset / outerRadius)))
        let innerTrim = Double(asin(min(1, edgeInset / innerRadius)))
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .radians(startAngle + outerTrim),
                    endAngle: .radians(endAngle - outerTrim), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .radians(endAngle - innerTrim),
                    endAngle: .radians(startAngle + innerTrim), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Routes drag-hover and drop to whichever petal is under the pointer.
struct RingDropDelegate: DropDelegate {
    let model: RingModel

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        let location = info.location
        MainActor.assumeIsolated { model.updateHover(location) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let location = info.location
        let actionable = MainActor.assumeIsolated { () -> Bool in
            model.updateHover(location)
            if case .segment(let index) = model.hover, model.items.indices.contains(index) {
                return model.items[index].enabled
            }
            return false
        }
        return DropProposal(operation: actionable ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { model.updateHover(nil) }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { model.commit() }
    }
}
