import FileAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The radial menu: a glass disc of petals around a hub showing the file size.
struct RingView: View {
    @ObservedObject var model: RingModel

    private let petalGap: Double = 0.045
    private let rounding: CGFloat = 14

    var body: some View {
        let geometry = model.geometry
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.white.opacity(0.18)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                petal(item, index: index, geometry: geometry)
            }

            hub(geometry: geometry)
        }
        .frame(width: RingModel.diameter, height: RingModel.diameter)
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
        .animation(.easeOut(duration: 0.12), value: model.hover)
    }

    private func petal(_ item: RingItem, index: Int, geometry: RingGeometry) -> some View {
        let angles = geometry.angles(of: index)
        let highlighted = model.hover == .segment(index) && item.enabled
        let fill = highlighted ? Theme.accent : Theme.petal
        let shape = RingSegmentShape(
            startAngle: angles.start + petalGap,
            endAngle: angles.end - petalGap,
            innerRadius: geometry.innerRadius + 6 + rounding / 2,
            outerRadius: geometry.outerRadius - rounding / 2)

        let mid = geometry.midAngle(of: index)
        let labelRadius = (geometry.innerRadius + geometry.outerRadius) / 2 + 4
        let labelPosition = CGPoint(
            x: model.center.x + CGFloat(cos(mid)) * labelRadius,
            y: model.center.y + CGFloat(sin(mid)) * labelRadius)

        return ZStack {
            shape.fill(fill)
            shape.stroke(fill, style: StrokeStyle(lineWidth: rounding, lineJoin: .round))

            VStack(spacing: 4) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                }
                Text(item.title.uppercased())
                    .font(.system(size: item.symbol == nil ? 15 : 10, weight: .bold))
                    .tracking(0.4)
            }
            .foregroundStyle(highlighted ? Color.white : Theme.ink)
            .position(labelPosition)
        }
        .frame(width: RingModel.diameter, height: RingModel.diameter)
        .opacity(item.enabled ? 1 : 0.38)
        .scaleEffect(highlighted ? 1.03 : 1)
        .allowsHitTesting(false)
    }

    private func hub(geometry: RingGeometry) -> some View {
        let size = geometry.innerRadius * 2
        let highlighted = model.hover == .center
        return ZStack {
            Circle()
                .fill(Theme.hub)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            Circle()
                .trim(from: 0, to: model.hubFlipProgress ? 1 : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
                .animation(model.hubFlipProgress ? .linear(duration: 0.6) : .none, value: model.hubFlipProgress)
            VStack(spacing: 3) {
                Text(model.hubTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(model.mode == .convert ? "⇄ Tools" : "⇄ Convert")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.label.opacity(highlighted ? 1 : 0.7))
            }
            .padding(.horizontal, 10)
        }
        .frame(width: size - 8, height: size - 8)
        .scaleEffect(highlighted ? 1.05 : 1)
        .allowsHitTesting(false)
    }
}

/// An annular sector between two angles (radians, y-down, increasing clockwise).
struct RingSegmentShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .radians(endAngle), endAngle: .radians(startAngle), clockwise: true)
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
