import Foundation

/// sRGB <-> CIE Lab (D65) with lookup tables, tuned for per-pixel use on millions of pixels.
enum ColorMath {
    /// 8-bit sRGB -> linear light.
    static let decodeLUT: [Float] = (0..<256).map { i in
        let c = Float(i) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// Linear light (0...1, 4096 steps) -> 8-bit sRGB.
    static let encodeLUT: [UInt8] = (0...4096).map { i in
        let c = Float(i) / 4096
        let v = c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, Int((v * 255).rounded()))))
    }

    @inline(__always) static func encode(_ linear: Float) -> UInt8 {
        let c = min(max(linear, 0), 1)
        return encodeLUT[Int(c * 4096 + 0.5)]
    }

    static let xn: Float = 0.95047
    static let yn: Float = 1.0
    static let zn: Float = 1.08883
    static let eps: Float = 216.0 / 24389.0
    static let kappa: Float = 24389.0 / 27.0

    @inline(__always) static func fwd(_ t: Float) -> Float {
        t > eps ? cbrtf(t) : (kappa * t + 16) / 116
    }

    @inline(__always) static func inv(_ f: Float) -> Float {
        let f3 = f * f * f
        return f3 > eps ? f3 : (116 * f - 16) / kappa
    }

    /// 8-bit sRGB to Lab.
    @inline(__always) static func lab(r: UInt8, g: UInt8, b: UInt8) -> (L: Float, a: Float, b: Float) {
        let lr = decodeLUT[Int(r)], lg = decodeLUT[Int(g)], lb = decodeLUT[Int(b)]
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / xn
        let y = (0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb) / yn
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / zn
        let fx = fwd(x), fy = fwd(y), fz = fwd(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Lab to linear sRGB (unclamped).
    @inline(__always) static func linearRGB(L: Float, a: Float, b: Float) -> (r: Float, g: Float, b: Float) {
        let fy = (L + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        let x = inv(fx) * xn, y = inv(fy) * yn, z = inv(fz) * zn
        return (
            3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        )
    }

    /// Lab to 8-bit sRGB. If the colour is outside the sRGB gamut, chroma is reduced until it fits (hue and lightness are kept).
    @inline(__always) static func srgb(L: Float, a: Float, b: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        var aa = a, bb = b
        var lin = linearRGB(L: L, a: aa, b: bb)
        var tries = 0
        while tries < 6 && (lin.r < -0.002 || lin.r > 1.002 || lin.g < -0.002 || lin.g > 1.002 || lin.b < -0.002 || lin.b > 1.002) {
            aa *= 0.85
            bb *= 0.85
            lin = linearRGB(L: L, a: aa, b: bb)
            tries += 1
        }
        return (encode(lin.r), encode(lin.g), encode(lin.b))
    }

    static func lab(hex: UInt32) -> (L: Float, a: Float, b: Float) {
        lab(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    /// Relative luminance (0...1) of a hex colour.
    static func luminance(hex: UInt32) -> Float {
        let r = decodeLUT[Int((hex >> 16) & 0xFF)], g = decodeLUT[Int((hex >> 8) & 0xFF)], b = decodeLUT[Int(hex & 0xFF)]
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Hex of a Lab colour (gamut mapped).
    static func hex(L: Float, a: Float, b: Float) -> UInt32 {
        let c = srgb(L: L, a: a, b: b)
        return (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
    }
}
