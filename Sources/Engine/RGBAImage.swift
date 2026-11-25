import Foundation
import CoreGraphics
import UIKit

/// An 8-bit RGBA image (sRGB, alpha always 255) held in memory, the working format of the engine.
struct RGBAImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8) = (0, 0, 0)) {
        self.width = max(1, width)
        self.height = max(1, height)
        var p = [UInt8](repeating: 255, count: self.width * self.height * 4)
        for i in 0..<(self.width * self.height) {
            p[i * 4] = fill.0
            p[i * 4 + 1] = fill.1
            p[i * 4 + 2] = fill.2
        }
        self.pixels = p
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws the image upright into an sRGB RGBA buffer whose longest side is at most `maxSide`.
    init?(cgImage: CGImage, maxSide: Int) {
        let sw = cgImage.width, sh = cgImage.height
        guard sw > 0, sh > 0 else { return nil }
        let scale = min(1.0, Double(maxSide) / Double(max(sw, sh)))
        let w = max(1, Int((Double(sw) * scale).rounded()))
        let h = max(1, Int((Double(sh) * scale).rounded()))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: RGBAImage.colorSpace, bitmapInfo: info
            ) else { return false }
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // The photo was composited over white, so alpha is fully opaque.
        var i = 3
        while i < buffer.count { buffer[i] = 255; i += 4 }
        self.width = w
        self.height = h
        self.pixels = buffer
    }

    /// Reads a UIImage, applying its orientation, with the longest side at most `maxSide`.
    init?(uiImage: UIImage, maxSide: Int) {
        guard let upright = RGBAImage.upright(uiImage) else { return nil }
        self.init(cgImage: upright, maxSide: maxSide)
    }

    /// A CGImage with the orientation baked in.
    static func upright(_ image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else {
            if let ci = image.ciImage {
                return CIContext().createCGImage(ci, from: ci.extent)
            }
            return nil
        }
        if image.imageOrientation == .up { return cg }
        let size = image.size
        let w = Int(size.width * image.scale), h = Int(size.height * image.scale)
        guard w > 0, h > 0 else { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return drawn.cgImage
    }

    func cgImage() -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: RGBAImage.colorSpace, bitmapInfo: info, provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }

    func uiImage() -> UIImage? {
        guard let cg = cgImage() else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// A smaller copy, longest side at most `maxSide`. Returns self when already small enough.
    func resized(maxSide: Int) -> RGBAImage {
        let longest = max(width, height)
        guard longest > maxSide, let cg = cgImage(), let out = RGBAImage(cgImage: cg, maxSide: maxSide) else { return self }
        return out
    }

    /// Luma (0...1) as a Plane, used as the guide for edge snapping.
    func lumaPlane() -> Plane {
        var out = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(pixels[i * 4]), g = Float(pixels[i * 4 + 1]), b = Float(pixels[i * 4 + 2])
            out[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        }
        return Plane(width: width, height: height, data: out)
    }

    /// Crop (in pixels, clamped) as a new image.
    func cropped(_ rect: CGRect) -> RGBAImage? {
        let x0 = max(0, Int(rect.minX.rounded(.down))), y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up))), y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        let w = x1 - x0, h = y1 - y0
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let srcStart = ((y0 + y) * width + x0) * 4
            let dstStart = y * w * 4
            for k in 0..<(w * 4) { out[dstStart + k] = pixels[srcStart + k] }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }
}
