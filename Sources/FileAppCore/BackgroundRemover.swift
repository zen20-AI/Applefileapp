import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Cuts the subject out of a photo (Vision's subject lifting) and saves a transparent PNG.
public enum BackgroundRemover {
    public static func canRemove(_ url: URL) -> Bool { FileKind(url: url) == .image }

    /// Writes "<name> No Background.png".
    public static func removeBackground(_ url: URL) throws -> URL {
        let image = try ImageFile.load(url)
        let result = try cutOut(image)
        let output = OutputNaming.url(for: url, suffix: "No Background", fileExtension: "png")
        try ImageFile.write(result, to: output, type: .png)
        return output
    }

    public static func cutOut(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw FileAppError.unsupported("Finding a subject in this image")
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: ImageFile.sRGB) else {
            throw FileAppError.unsupported("Removing the background")
        }
        return cgImage
    }
}
