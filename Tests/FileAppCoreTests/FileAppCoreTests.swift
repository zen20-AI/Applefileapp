import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import FileAppCore

final class OutputNamingTests: XCTestCase {
    let source = URL(fileURLWithPath: "/tmp/Page 001.pdf")

    func testChangesExtension() {
        let url = OutputNaming.url(for: source, fileExtension: "jpg", exists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "Page 001.jpg")
    }

    func testAppendsSuffix() {
        let jpg = URL(fileURLWithPath: "/tmp/Page 001 Cropped.jpg")
        let url = OutputNaming.url(for: jpg, suffix: "With Background", fileExtension: "png", exists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "Page 001 Cropped With Background.png")
    }

    func testNeverOverwrites() {
        let taken: Set<String> = ["Page 001.jpg", "Page 001 2.jpg"]
        let url = OutputNaming.url(for: source, fileExtension: "jpg", exists: { taken.contains($0.lastPathComponent) })
        XCTAssertEqual(url.lastPathComponent, "Page 001 3.jpg")
    }

    func testNeverReturnsSource() {
        let png = URL(fileURLWithPath: "/tmp/a.png")
        let url = OutputNaming.url(for: png, fileExtension: "png", exists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "a 2.png")
    }
}

final class RingGeometryTests: XCTestCase {
    let ring = RingGeometry(segmentCount: 8, innerRadius: 60, outerRadius: 160)
    let center = CGPoint(x: 170, y: 170)

    func testCenterAndOutside() {
        XCTAssertEqual(ring.hit(center, center: center), .center)
        XCTAssertEqual(ring.hit(CGPoint(x: 170, y: 0), center: center), .outside)
    }

    func testSegmentsRunClockwiseFromTop() {
        XCTAssertEqual(ring.hit(CGPoint(x: 170, y: 60), center: center), .segment(0))   // 12 o'clock
        XCTAssertEqual(ring.hit(CGPoint(x: 280, y: 170), center: center), .segment(2))  // 3 o'clock
        XCTAssertEqual(ring.hit(CGPoint(x: 170, y: 280), center: center), .segment(4))  // 6 o'clock
        XCTAssertEqual(ring.hit(CGPoint(x: 60, y: 170), center: center), .segment(6))   // 9 o'clock
    }

    func testSegmentZeroWrapsAroundTop() {
        // Slightly left of 12 o'clock is still segment 0 (it straddles the top).
        XCTAssertEqual(ring.hit(CGPoint(x: 160, y: 60), center: center), .segment(0))
    }
}

final class CropMathTests: XCTestCase {
    let imageSize = CGSize(width: 2550, height: 3300)

    func testFitSquareInPortraitImage() {
        let rect = CropMath.fit(aspect: 1, imageSize: imageSize)
        let pixels = CropMath.pixelRect(rect, imageSize: imageSize)
        XCTAssertEqual(pixels.width, 2550, accuracy: 1)
        XCTAssertEqual(pixels.height, 2550, accuracy: 1)
    }

    func testFreeDragBottomEdge() {
        let rect = CropMath.drag(.bottom, start: CropMath.unit, translation: CGSize(width: 0, height: -0.25), aspect: nil, imageSize: imageSize)
        XCTAssertEqual(rect.maxY, 0.75, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 1, accuracy: 1e-9)
    }

    func testLockedAspectStaysInBounds() {
        let start = CropMath.fit(aspect: 1, imageSize: imageSize)
        let rect = CropMath.drag(.bottomRight, start: start, translation: CGSize(width: 0.5, height: 0.5), aspect: 1, imageSize: imageSize)
        XCTAssertLessThanOrEqual(rect.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(rect.maxY, 1 + 1e-9)
        let pixels = CropMath.pixelRect(rect, imageSize: imageSize)
        XCTAssertEqual(pixels.width, pixels.height, accuracy: 1)
    }

    func testMoveIsClamped() {
        let start = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let rect = CropMath.drag(.move, start: start, translation: CGSize(width: 1, height: -1), aspect: nil, imageSize: imageSize)
        XCTAssertEqual(rect, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }
}

final class BackgroundRendererTests: XCTestCase {
    func testAutoRatioAddsPadding() {
        let size = BackgroundRenderer.canvasSize(for: CGSize(width: 100, height: 50), padding: 10, ratio: nil)
        XCTAssertEqual(size, CGSize(width: 120, height: 70))
    }

    func testFixedRatioGrowsShortSide() {
        let size = BackgroundRenderer.canvasSize(for: CGSize(width: 100, height: 50), padding: 10, ratio: 1)
        XCTAssertEqual(size, CGSize(width: 120, height: 120))
    }

    func testRenderProducesCanvas() throws {
        let ctx = try XCTUnwrap(ImageFile.makeContext(width: 40, height: 20))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try XCTUnwrap(ctx.makeImage())
        let options = BackgroundOptions(fill: .solid(CGColor(gray: 1, alpha: 1)), padding: 5, cornerRadius: 4, shadow: 3, ratio: .square)
        let result = try XCTUnwrap(BackgroundRenderer.render(image, options: options))
        XCTAssertEqual(result.width, 50)
        XCTAssertEqual(result.height, 50)
    }
}

final class FormatTests: XCTestCase {
    func testFileKinds() {
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.JPG")), .image)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.pdf")), .pdf)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.docx")), .document)
        XCTAssertEqual(FileKind(url: URL(fileURLWithPath: "/a.zip")), .other)
    }

    func testSameFormatIsNotOffered() {
        let jpg = URL(fileURLWithPath: "/a.jpeg")
        XCTAssertFalse(Converter.isAvailable(.jpg, for: jpg))
        XCTAssertTrue(Converter.isAvailable(.png, for: jpg))
        XCTAssertTrue(Converter.isAvailable(.pdf, for: jpg))
        XCTAssertFalse(Converter.isAvailable(.docx, for: jpg))
        XCTAssertTrue(Converter.isAvailable(.docx, for: URL(fileURLWithPath: "/a.pdf")))
    }

    func testImageRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ctx = try XCTUnwrap(ImageFile.makeContext(width: 64, height: 32))
        ctx.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let png = dir.appendingPathComponent("Page 001.png")
        try ImageFile.write(try XCTUnwrap(ctx.makeImage()), to: png, type: .png)

        let outputs = try Converter.convert(png, to: .jpg)
        XCTAssertEqual(outputs.map(\.lastPathComponent), ["Page 001.jpg"])
        let loaded = try ImageFile.load(outputs[0])
        XCTAssertEqual(loaded.width, 64)
        XCTAssertEqual(loaded.height, 32)

        let pdf = try Converter.convert(png, to: .pdf)
        XCTAssertEqual(pdf.map(\.lastPathComponent), ["Page 001.pdf"])
        let pages = try Converter.convert(pdf[0], to: .png)
        XCTAssertEqual(pages.map(\.lastPathComponent), ["Page 001 2.png"])
    }
}
