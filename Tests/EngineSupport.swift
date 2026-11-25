import XCTest
import UIKit
@testable import Lustra

/// A synthetic head-and-hair picture: skin-toned face, brown hair with strand texture, grey background.
enum Synthetic {
    static let size = (w: 400, h: 500)

    /// Returns the image and a matching hair matte (an ellipse behind and above the face).
    static func portrait() -> (RGBAImage, Plane) {
        let w = size.w, h = size.h
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var matte = Plane(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                // Background: soft grey gradient.
                var r: Float = 150 + Float(y) * 0.05, g: Float = 152, b: Float = 156
                let fx = Float(x) - 200, fy = Float(y) - 210
                let hairD = (fx * fx) / (150 * 150) + ((fy + 20) * (fy + 20)) / (190 * 190)
                let faceD = (fx * fx) / (85 * 85) + ((fy - 40) * (fy - 40)) / (115 * 115)
                if hairD < 1 {
                    // Hair: dark brown, vertical strands, a lighter sheen band.
                    let strand = sinf(Float(x) * 1.7) * 0.5 + sinf(Float(x) * 0.43 + Float(y) * 0.01) * 0.5
                    let sheen = max(0, 1 - abs(Float(y) - 90) / 40)
                    let v = 52 + strand * 16 + sheen * 55
                    r = v * 1.15; g = v * 0.82; b = v * 0.6
                    matte[x, y] = hairD > 0.9 ? max(0, (1 - hairD) / 0.1) : 1
                }
                if faceD < 1 {
                    r = 224; g = 178; b = 150
                    matte[x, y] = 0
                }
                px[i] = UInt8(min(255, max(0, r)))
                px[i + 1] = UInt8(min(255, max(0, g)))
                px[i + 2] = UInt8(min(255, max(0, b)))
            }
        }
        return (RGBAImage(width: w, height: h, pixels: px), matte)
    }

    static func context() -> (HairContext, RGBAImage, Plane) {
        let (img, matte) = portrait()
        let planes = PhotoPlanes(image: img)
        return (HairContext(planes: planes, matte: matte), img, matte)
    }

    static func meanLab(_ image: RGBAImage, matte: Plane, threshold: Float = 0.9) -> (L: Float, a: Float, b: Float) {
        var L: Double = 0, a: Double = 0, b: Double = 0, n = 0
        for i in 0..<(image.width * image.height) where matte.data[i] > threshold {
            let lab = ColorMath.lab(r: image.pixels[i * 4], g: image.pixels[i * 4 + 1], b: image.pixels[i * 4 + 2])
            L += Double(lab.L); a += Double(lab.a); b += Double(lab.b); n += 1
        }
        guard n > 0 else { return (0, 0, 0) }
        return (Float(L / Double(n)), Float(a / Double(n)), Float(b / Double(n)))
    }
}
