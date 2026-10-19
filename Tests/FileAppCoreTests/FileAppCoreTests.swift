import AppKit
import CoreGraphics
import CoreText
import ImageIO
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import FileAppCore

@Suite struct OutputNamingTests {
    let source = URL(fileURLWithPath: "/tmp/Page 001.pdf")

    @Test func changesExtension() {
        let url = OutputNaming.url(for: source, fileExtension: "jpg", exists: { _ in false })
        #expect(url.lastPathComponent == "Page 001.jpg")
    }

    @Test func appendsSuffix() {
        let jpg = URL(fileURLWithPath: "/tmp/Page 001 Cropped.jpg")
        let url = OutputNaming.url(for: jpg, suffix: "With Background", fileExtension: "png", exists: { _ in false })
        #expect(url.lastPathComponent == "Page 001 Cropped With Background.png")
    }

    @Test func neverOverwrites() {
        let taken: Set<String> = ["Page 001.jpg", "Page 001 2.jpg"]
        let url = OutputNaming.url(for: source, fileExtension: "jpg", exists: { taken.contains($0.lastPathComponent) })
        #expect(url.lastPathComponent == "Page 001 3.jpg")
    }

    @Test func neverReturnsSource() {
        let png = URL(fileURLWithPath: "/tmp/a.png")
        let url = OutputNaming.url(for: png, fileExtension: "png", exists: { _ in false })
        #expect(url.lastPathComponent == "a 2.png")
    }
}

@Suite struct RingGeometryTests {
    let ring = RingGeometry(segmentCount: 8, innerRadius: 60, outerRadius: 160)
    let center = CGPoint(x: 170, y: 170)

    @Test func centerAndOutside() {
        #expect(ring.hit(center, center: center) == .center)
        #expect(ring.hit(CGPoint(x: 170, y: 0), center: center) == .outside)
    }

    @Test func segmentsRunClockwiseFromTop() {
        #expect(ring.hit(CGPoint(x: 170, y: 60), center: center) == .segment(0))   // 12 o'clock
        #expect(ring.hit(CGPoint(x: 280, y: 170), center: center) == .segment(2))  // 3 o'clock
        #expect(ring.hit(CGPoint(x: 170, y: 280), center: center) == .segment(4))  // 6 o'clock
        #expect(ring.hit(CGPoint(x: 60, y: 170), center: center) == .segment(6))   // 9 o'clock
    }

    @Test func segmentZeroWrapsAroundTop() {
        // Slightly left of 12 o'clock is still segment 0 (it straddles the top).
        #expect(ring.hit(CGPoint(x: 160, y: 60), center: center) == .segment(0))
    }
}

@Suite struct CropMathTests {
    let imageSize = CGSize(width: 2550, height: 3300)

    @Test func fitSquareInPortraitImage() {
        let rect = CropMath.fit(aspect: 1, imageSize: imageSize)
        let pixels = CropMath.pixelRect(rect, imageSize: imageSize)
        #expect(abs(pixels.width - 2550) <= 1)
        #expect(abs(pixels.height - 2550) <= 1)
    }

    @Test func freeDragBottomEdge() {
        let rect = CropMath.drag(.bottom, start: CropMath.unit, translation: CGSize(width: 0, height: -0.25), aspect: nil, imageSize: imageSize)
        #expect(abs(rect.maxY - 0.75) < 1e-9)
        #expect(abs(rect.width - 1) < 1e-9)
    }

    @Test func lockedAspectStaysInBounds() {
        let start = CropMath.fit(aspect: 1, imageSize: imageSize)
        let rect = CropMath.drag(.bottomRight, start: start, translation: CGSize(width: 0.5, height: 0.5), aspect: 1, imageSize: imageSize)
        #expect(rect.maxX <= 1 + 1e-9)
        #expect(rect.maxY <= 1 + 1e-9)
        let pixels = CropMath.pixelRect(rect, imageSize: imageSize)
        #expect(abs(pixels.width - pixels.height) <= 1)
    }

    @Test func moveIsClamped() {
        let start = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let rect = CropMath.drag(.move, start: start, translation: CGSize(width: 1, height: -1), aspect: nil, imageSize: imageSize)
        #expect(rect == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }
}

@Suite struct BackgroundRendererTests {
    @Test func autoRatioAddsPadding() {
        let size = BackgroundRenderer.canvasSize(for: CGSize(width: 100, height: 50), padding: 10, ratio: nil)
        #expect(size == CGSize(width: 120, height: 70))
    }

    @Test func fixedRatioGrowsShortSide() {
        let size = BackgroundRenderer.canvasSize(for: CGSize(width: 100, height: 50), padding: 10, ratio: 1)
        #expect(size == CGSize(width: 120, height: 120))
    }

    @Test func renderProducesCanvas() throws {
        let image = try solidImage(width: 40, height: 20)
        let options = BackgroundOptions(fill: .solid(CGColor(gray: 1, alpha: 1)), padding: 5, cornerRadius: 4, shadow: 3, ratio: .square)
        let result = try #require(BackgroundRenderer.render(image, options: options))
        #expect(result.width == 50)
        #expect(result.height == 50)
    }
}

/// Tests that write files share one serialized suite so the global output folder stays predictable.
@Suite(.serialized) struct FileOutputTests {
    @Test func fileKinds() {
        #expect(FileKind(url: URL(fileURLWithPath: "/a.JPG")) == .image)
        #expect(FileKind(url: URL(fileURLWithPath: "/a.pdf")) == .pdf)
        #expect(FileKind(url: URL(fileURLWithPath: "/a.docx")) == .document)
        #expect(FileKind(url: URL(fileURLWithPath: "/a.zip")) == .other)
    }

    @Test func sameFormatIsNotOffered() {
        let jpg = URL(fileURLWithPath: "/a.jpeg")
        #expect(!Converter.isAvailable(.jpg, for: jpg))
        #expect(Converter.isAvailable(.png, for: jpg))
        #expect(Converter.isAvailable(.pdf, for: jpg))
        #expect(!Converter.isAvailable(.docx, for: jpg))
        #expect(Converter.isAvailable(.docx, for: URL(fileURLWithPath: "/a.pdf")))
    }

    @Test func imageRoundTrip() throws {
        try withTemporaryDirectory { dir in
            let png = dir.appendingPathComponent("Page 001.png")
            try ImageFile.write(try solidImage(width: 64, height: 32), to: png, type: .png)

            let outputs = try Converter.convert(png, to: .jpg)
            #expect(outputs.map(\.lastPathComponent) == ["Page 001.jpg"])
            let loaded = try ImageFile.load(outputs[0])
            #expect(loaded.width == 64)
            #expect(loaded.height == 32)

            let pdf = try Converter.convert(png, to: .pdf)
            #expect(pdf.map(\.lastPathComponent) == ["Page 001.pdf"])
            let pages = try Converter.convert(pdf[0], to: .png)
            #expect(pages.map(\.lastPathComponent) == ["Page 001 2.png"])
        }
    }

    @Test func resizeTargetSizes() {
        let size = CGSize(width: 4000, height: 3000)
        #expect(Resizer.targetSize(for: size, mode: .percent(0.5)) == CGSize(width: 2000, height: 1500))
        #expect(Resizer.targetSize(for: size, mode: .maxSide(1000)) == CGSize(width: 1000, height: 750))
        // Never upscales when fitting.
        #expect(Resizer.targetSize(for: CGSize(width: 300, height: 200), mode: .maxSide(1000)) == CGSize(width: 300, height: 200))
    }

    @Test func resizeWritesSmallerCopy() throws {
        try withTemporaryDirectory { dir in
            let png = dir.appendingPathComponent("Shot.png")
            try ImageFile.write(try solidImage(width: 200, height: 100), to: png, type: .png)
            let output = try Resizer.resize(png, mode: .maxSide(50))
            #expect(output.lastPathComponent == "Shot Resized.png")
            let loaded = try ImageFile.load(output)
            #expect(loaded.width == 50)
            #expect(loaded.height == 25)
        }
    }

    @Test func mergeCombinesPages() throws {
        try withTemporaryDirectory { dir in
            let a = dir.appendingPathComponent("A.png")
            let b = dir.appendingPathComponent("B.jpg")
            try ImageFile.write(try solidImage(width: 30, height: 30), to: a, type: .png)
            try ImageFile.write(try solidImage(width: 30, height: 60), to: b, type: .jpeg)
            let pdf = try Converter.convert(a, to: .pdf)[0]

            let output = try PDFMerger.merge([a, b, pdf, dir.appendingPathComponent("notes.zip")])
            #expect(output.lastPathComponent == "A Merged.pdf")
            #expect(PDFDocument(url: output)?.pageCount == 3)
        }
    }

    @Test func parsesPageRanges() throws {
        #expect(try PDFPages.parseRanges("1-3, 5, 8-", pageCount: 10) == [0...2, 4...4, 7...9])
        #expect(try PDFPages.parseRanges("-2; 4–4", pageCount: 5) == [0...1, 3...3])
        #expect(throws: PDFPages.RangeError.self) { try PDFPages.parseRanges("2-12", pageCount: 10) }
        #expect(throws: PDFPages.RangeError.self) { try PDFPages.parseRanges("a", pageCount: 10) }
        #expect(throws: PDFPages.RangeError.self) { try PDFPages.parseRanges(" , ", pageCount: 10) }
        #expect(try PDFPages.groups(pageCount: 5, mode: .every(2)) == [[0, 1], [2, 3], [4]])
        #expect(try PDFPages.groups(pageCount: 3, mode: .everyPage) == [[0], [1], [2]])
    }

    @Test func splitWritesFilesIntoFolder() throws {
        try withTemporaryDirectory { dir in
            let source = try makePDF(pages: 5, in: dir)
            let outputs = try PDFPages.split(source, mode: .every(2))
            #expect(outputs.map(\.lastPathComponent) == ["Doc Pages 1-2.pdf", "Doc Pages 3-4.pdf", "Doc Page 5.pdf"])
            #expect(outputs[0].deletingLastPathComponent().lastPathComponent == "Doc Split")
            #expect(outputs.map { PDFDocument(url: $0)?.pageCount } == [2, 2, 1])
            // A single range is saved next to the source.
            let single = try PDFPages.split(source, mode: .ranges("2-3"))
            #expect(single.map(\.lastPathComponent) == ["Doc Pages 2-3.pdf"])
        }
    }

    @Test func rebuildReordersAndRotates() throws {
        try withTemporaryDirectory { dir in
            let source = try makePDF(pages: 3, in: dir)
            var pages = try PDFPages.pages(of: [source])
            pages.swapAt(0, 2)
            pages[0].rotation = 90
            pages.remove(at: 1)
            let output = try PDFPages.write(pages, name: source, suffix: "Edited")
            let document = try #require(PDFDocument(url: output))
            #expect(document.pageCount == 2)
            #expect(document.page(at: 0)?.rotation == 90)
            #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 30) // was page 3 (30 wide)
            #expect(PDFDocument(url: source)?.page(at: 0)?.rotation == 0)   // source untouched
        }
    }

    @Test func destinationDirectoryOverride() throws {
        try withTemporaryDirectory { dir in
            OutputNaming.destinationDirectory = dir
            defer { OutputNaming.destinationDirectory = nil }
            let url = OutputNaming.url(for: URL(fileURLWithPath: "/elsewhere/a.png"), fileExtension: "jpg")
            #expect(url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        }
    }
}

@Suite struct MoreToolsTests {
    @Test func renamePreviewNumbersAndAvoidsClashes() throws {
        let urls = ["/x/b.jpg", "/x/a.png", "/x/c.jpg"].map { URL(fileURLWithPath: $0) }
        let taken = URL(fileURLWithPath: "/x/Trip 2.png")
        let names = BatchRenamer.preview(urls, pattern: RenamePattern(template: "Trip"), exists: { $0 == taken })
        #expect(names.map(\.lastPathComponent) == ["Trip 1.jpg", "Trip 2 2.png", "Trip 3.jpg"])
        let padded = BatchRenamer.preview(urls, pattern: RenamePattern(template: "{name}-{n}", start: 9, digits: 3), exists: { _ in false })
        #expect(padded.map(\.lastPathComponent) == ["b-009.jpg", "a-010.png", "c-011.jpg"])
    }

    @Test func renameSwapsNames() throws {
        try withTemporaryDirectory { dir in
            let a = dir.appendingPathComponent("1.txt"), b = dir.appendingPathComponent("2.txt")
            try "a".write(to: a, atomically: true, encoding: .utf8)
            try "b".write(to: b, atomically: true, encoding: .utf8)
            // b → "1", a → "2": a straight swap.
            let result = try BatchRenamer.rename([b, a], pattern: RenamePattern(template: "{n}"))
            #expect(result.map(\.lastPathComponent) == ["1.txt", "2.txt"])
            #expect(try String(contentsOf: dir.appendingPathComponent("1.txt"), encoding: .utf8) == "b")
        }
    }

    @Test func lockAndUnlock() throws {
        try withTemporaryDirectory { dir in
            let source = try makePDF(pages: 2, in: dir)
            let locked = try PDFTools.lock(source, password: "pass")
            #expect(PDFTools.isLocked(locked))
            #expect(throws: PDFTools.PasswordError.self) { try PDFTools.unlock(locked, password: "nope") }
            let unlocked = try PDFTools.unlock(locked, password: "pass")
            #expect(!PDFTools.isLocked(unlocked))
            #expect(PDFDocument(url: unlocked)?.pageCount == 2)
        }
    }

    @Test func stampsKeepPagesAndRotation() throws {
        try withTemporaryDirectory { dir in
            var pages = try PDFPages.pages(of: [try makePDF(pages: 3, in: dir)])
            pages[0].rotation = 90
            let rotated = try PDFPages.write(pages, name: dir.appendingPathComponent("R.pdf"), suffix: "X")
            let numbered = try PDFTools.numberPages(rotated, ofTotal: true)
            let watermarked = try PDFTools.watermark(numbered, text: "DRAFT")
            let document = try #require(PDFDocument(url: watermarked))
            #expect(document.pageCount == 3)
            // The 10 × 40 page turned 90° is drawn upright as 40 × 10.
            #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 40, height: 10))
            #expect(document.string?.contains("DRAFT") == true)
        }
    }

    @Test func ocrReadsRenderedText() throws {
        let ctx = try #require(ImageFile.makeContext(width: 900, height: 200))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 200))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello Petal 2026", attributes: [
            .font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black]))
        ctx.textPosition = CGPoint(x: 40, y: 70)
        CTLineDraw(line, ctx)
        let text = try TextRecognizer.recognize(try #require(ctx.makeImage()))
        #expect(text.contains("Petal"))
    }

    @Test func gifAndSlideshow() throws {
        try withTemporaryDirectory { dir in
            let urls = try (1...3).map { n -> URL in
                let url = dir.appendingPathComponent("F\(n).png")
                try ImageFile.write(try solidImage(width: 64 * n, height: 48), to: url, type: .png)
                return url
            }
            let gif = try MediaMaker.makeGIF(urls, maxSide: 100)
            #expect(gif.lastPathComponent == "F1 Animation.gif")
            #expect(CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) == 3)
            let video = try MediaMaker.makeVideo(urls, secondsPerImage: 0.5)
            #expect(video.fileSize > 0)
            #expect(FileKind(url: video) == .video)
        }
    }
}

// MARK: - Helpers

func solidImage(width: Int, height: Int) throws -> CGImage {
    let ctx = try #require(ImageFile.makeContext(width: width, height: height))
    ctx.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(ctx.makeImage())
}

/// "Doc.pdf" whose page n is (10·n) points wide, so pages can be told apart.
func makePDF(pages: Int, in dir: URL) throws -> URL {
    let document = PDFDocument()
    for n in 1...pages {
        let image = try solidImage(width: 10 * n, height: 40)
        let page = try #require(PDFPage(image: NSImage(cgImage: image, size: image.size)))
        document.insert(page, at: document.pageCount)
    }
    let url = dir.appendingPathComponent("Doc.pdf")
    #expect(document.write(to: url))
    return url
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
