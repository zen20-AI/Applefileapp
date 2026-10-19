import CoreGraphics
import Foundation

public enum RingHit: Equatable {
    case outside
    case center
    case segment(Int)
}

/// Hit-testing for the radial menu. Points use a y-down coordinate space (SwiftUI),
/// segment 0 is centered at 12 o'clock and indices increase clockwise.
public struct RingGeometry: Equatable {
    public var segmentCount: Int
    public var innerRadius: CGFloat
    public var outerRadius: CGFloat

    public init(segmentCount: Int, innerRadius: CGFloat, outerRadius: CGFloat) {
        self.segmentCount = segmentCount
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    public var step: Double { 2 * .pi / Double(max(segmentCount, 1)) }

    public func midAngle(of index: Int) -> Double {
        -.pi / 2 + Double(index) * step
    }

    public func angles(of index: Int) -> (start: Double, end: Double) {
        let mid = midAngle(of: index)
        return (mid - step / 2, mid + step / 2)
    }

    public func index(forAngle angle: Double) -> Int {
        var t = (angle + .pi / 2 + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if t < 0 { t += 2 * .pi }
        return min(Int(t / step), segmentCount - 1)
    }

    public func hit(_ point: CGPoint, center: CGPoint) -> RingHit {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= Double(innerRadius) { return .center }
        if distance > Double(outerRadius) || segmentCount == 0 { return .outside }
        return .segment(index(forAngle: atan2(dy, dx)))
    }
}
