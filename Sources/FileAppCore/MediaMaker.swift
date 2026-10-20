import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images → animated GIF or slideshow video, and smaller copies of videos.
public enum MediaMaker {
    // MARK: - GIF

    /// Writes "<first> Animation.gif", looping forever.
    public static func makeGIF(_ urls: [URL], frameDelay: Double = 0.5, maxSide: Int = 800) throws -> URL {
        let images = urls.filter { FileKind(url: $0) == .image }
        guard let first = images.first else { throw FileAppError.unsupported("Making a GIF from these files") }
        let output = OutputNaming.url(for: first, suffix: "Animation", fileExtension: "gif")
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
            throw FileAppError.writeFailed(output)
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
        for url in images {
            CGImageDestinationAddImage(destination, try ImageFile.load(url, maxPixelSize: maxSide), frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw FileAppError.writeFailed(output) }
        return output
    }

    // MARK: - Slideshow

    /// Writes "<first> Slideshow.mp4" (H.264), each image shown for `secondsPerImage`, letterboxed on black.
    public static func makeVideo(_ urls: [URL], secondsPerImage: Double = 2, maxSide: Int = 1920) throws -> URL {
        let images = urls.filter { FileKind(url: $0) == .image }
        guard let first = images.first else { throw FileAppError.unsupported("Making a video from these files") }
        let firstImage = try ImageFile.load(first, maxPixelSize: maxSide)
        // H.264 wants even dimensions.
        let width = firstImage.width / 2 * 2, height = firstImage.height / 2 * 2
        let output = OutputNaming.url(for: first, suffix: "Slideshow", fileExtension: "mp4")

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FileAppError.writeFailed(output) }
        writer.startSession(atSourceTime: .zero)

        let timescale: CMTimeScale = 600
        let frameTime = CMTime(seconds: secondsPerImage, preferredTimescale: timescale)
        var time = CMTime.zero
        var lastBuffer: CVPixelBuffer?
        for (index, url) in images.enumerated() {
            let image = index == 0 ? firstImage : try ImageFile.load(url, maxPixelSize: maxSide)
            guard let buffer = pixelBuffer(for: image, width: width, height: height, pool: adaptor.pixelBufferPool) else {
                throw FileAppError.writeFailed(output)
            }
            try append(buffer, at: time, to: adaptor, input: input, writer: writer)
            lastBuffer = buffer
            time = time + frameTime
        }
        // Hold the last image for its full duration.
        if let lastBuffer {
            try append(lastBuffer, at: time - CMTime(value: 1, timescale: timescale), to: adaptor, input: input, writer: writer)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: time)

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? FileAppError.writeFailed(output) }
        return output
    }

    private static func append(_ buffer: CVPixelBuffer, at time: CMTime, to adaptor: AVAssetWriterInputPixelBufferAdaptor,
                               input: AVAssetWriterInput, writer: AVAssetWriter) throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? FileAppError.unsupported("Writing video") }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw writer.error ?? FileAppError.unsupported("Writing video")
        }
    }

    private static func pixelBuffer(for image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: ImageFile.sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                                   width: size.width, height: size.height))
        return buffer
    }

    // MARK: - Video compression

    public enum VideoQuality: String, CaseIterable, Sendable {
        case small, p720, p1080

        var preset: String {
            switch self {
            case .small: return AVAssetExportPresetMediumQuality
            case .p720: return AVAssetExportPreset1280x720
            case .p1080: return AVAssetExportPreset1920x1080
            }
        }

        public var label: String {
            switch self {
            case .small: return "Smallest"
            case .p720: return "720p"
            case .p1080: return "1080p"
            }
        }
    }

    public static func canCompressVideo(_ url: URL) -> Bool { FileKind(url: url) == .video }

    /// Writes "<name> Compressed.mp4" (H.264).
    public static func compressVideo(_ url: URL, quality: VideoQuality = .p720) throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: quality.preset) else {
            throw FileAppError.unsupported("Compressing this video")
        }
        let output = OutputNaming.url(for: url, suffix: "Compressed", fileExtension: "mp4")
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        guard session.status == .completed else { throw session.error ?? FileAppError.writeFailed(output) }
        return output
    }
}
