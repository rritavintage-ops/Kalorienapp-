import UIKit

enum ImageProcessor {
    /// Longest edge recommended for vision models; larger images only add latency and cost.
    static let uploadMaxDimension: CGFloat = 1568
    static let thumbnailMaxDimension: CGFloat = 320

    /// Downscales (and normalizes orientation of) an image so its longest edge is at most `maxDimension` pixels.
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > 0 else { return image }
        let factor = min(1, maxDimension / longest)
        let target = CGSize(width: max(1, (pixelSize.width * factor).rounded()), height: max(1, (pixelSize.height * factor).rounded()))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG sent to the scan backend.
    static func uploadJPEG(from image: UIImage) throws -> Data {
        let resizedImage = resized(image, maxDimension: uploadMaxDimension)
        for quality in [0.8, 0.6, 0.4] {
            if let data = resizedImage.jpegData(compressionQuality: quality), data.count <= MealScanAPI.maximumImageBytes {
                return data
            }
        }
        throw MealScanError.imageTooLarge
    }

    /// Small JPEG stored with scanned entries.
    static func thumbnailJPEG(from image: UIImage) -> Data? {
        resized(image, maxDimension: thumbnailMaxDimension).jpegData(compressionQuality: 0.7)
    }

    /// A generated "plate" photo used by UI tests (the simulator has no camera).
    static func samplePlateImage() -> UIImage {
        let size = CGSize(width: 900, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 90, y: 90, width: 720, height: 720))
            UIColor(red: 0.85, green: 0.62, blue: 0.36, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 230, y: 220, width: 260, height: 190))
            UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 420, y: 380, width: 250, height: 220))
            UIColor(red: 0.30, green: 0.60, blue: 0.28, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 250, y: 470, width: 170, height: 150))
        }
    }
}
