import CoreGraphics

public enum CropAspect: String, CaseIterable, Identifiable {
    case free, square, wide, tall, standard, portrait

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .tall: return "9:16"
        case .standard: return "4:3"
        case .portrait: return "3:4"
        }
    }

    /// Width / height in pixels, or nil for a free crop.
    public var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .tall: return 9.0 / 16.0
        case .standard: return 4.0 / 3.0
        case .portrait: return 3.0 / 4.0
        }
    }
}

public enum CropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
}

/// Crop rectangles are normalized (0...1) with a top-left origin.
public enum CropMath {
    public static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Converts a pixel aspect ratio into the equivalent ratio in normalized space.
    public static func normalizedAspect(_ ratio: CGFloat, imageSize: CGSize) -> CGFloat {
        ratio * imageSize.height / imageSize.width
    }

    public static func drag(
        _ handle: CropHandle,
        start: CGRect,
        translation: CGSize,
        aspect: CGFloat?,
        imageSize: CGSize,
        minSize: CGFloat = 0.03
    ) -> CGRect {
        if handle == .move {
            let x = min(max(start.minX + translation.width, 0), 1 - start.width)
            let y = min(max(start.minY + translation.height, 0), 1 - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height)
        }

        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if handle.movesLeft { minX = min(max(start.minX + translation.width, 0), maxX - minSize) }
        if handle.movesRight { maxX = max(min(start.maxX + translation.width, 1), minX + minSize) }
        if handle.movesTop { minY = min(max(start.minY + translation.height, 0), maxY - minSize) }
        if handle.movesBottom { maxY = max(min(start.maxY + translation.height, 1), minY + minSize) }
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard let aspect else { return free }
        let a = normalizedAspect(aspect, imageSize: imageSize)
        var w = free.width, h = free.height
        switch handle {
        case .left, .right: h = w / a
        case .top, .bottom: w = h * a
        default: if w / h > a { h = w / a } else { w = h * a }
        }

        // Room available on the side the rect grows towards (edge handles grow symmetrically).
        let maxW = handle.movesLeft ? start.maxX : handle.movesRight ? 1 - start.minX : 2 * min(start.midX, 1 - start.midX)
        let maxH = handle.movesTop ? start.maxY : handle.movesBottom ? 1 - start.minY : 2 * min(start.midY, 1 - start.midY)
        let scale = min(1, maxW / w, maxH / h)
        w *= scale
        h *= scale

        let x = handle.movesLeft ? start.maxX - w : handle.movesRight ? start.minX : start.midX - w / 2
        let y = handle.movesTop ? start.maxY - h : handle.movesBottom ? start.minY : start.midY - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The largest rect with the given pixel aspect ratio, centered on `rect` and kept inside the image.
    public static func fit(aspect: CGFloat, imageSize: CGSize, around rect: CGRect = unit) -> CGRect {
        let a = normalizedAspect(aspect, imageSize: imageSize)
        var w: CGFloat = 1
        var h = w / a
        if h > 1 {
            h = 1
            w = h * a
        }
        return clamp(CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    /// Resizes around the current center to the given pixel size.
    public static func resize(_ rect: CGRect, toPixels size: CGSize, imageSize: CGSize) -> CGRect {
        let w = min(max(size.width / imageSize.width, 0.01), 1)
        let h = min(max(size.height / imageSize.height, 0.01), 1)
        return clamp(CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    /// Shifts a rect back inside the unit square without changing its size.
    public static func clamp(_ rect: CGRect) -> CGRect {
        let w = min(rect.width, 1), h = min(rect.height, 1)
        let x = min(max(rect.minX, 0), 1 - w)
        let y = min(max(rect.minY, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    public static func pixelRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        let pixels = CGRect(
            x: rect.minX * imageSize.width,
            y: rect.minY * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        ).integral
        return pixels.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
