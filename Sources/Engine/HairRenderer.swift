import Foundation
import CoreGraphics

/// The per-photo data that does not depend on the hair matte: the pixels, lightness, fine detail and chroma.
/// Built once per photo and size, then shared by every matte edit and every look.
final class PhotoPlanes {
    let width: Int
    let height: Int
    let rgba: [UInt8]
    /// Lab lightness, 0...100.
    let lightness: [Float]
    /// Lightness minus its local average: strands, shine, texture.
    let detail: [Float]
    /// Lab chroma, 0...~130.
    let chroma: [Float]

    init(image: RGBAImage) {
        width = image.width
        height = image.height
        rgba = image.pixels
        let n = image.width * image.height
        var L = [Float](repeating: 0, count: n)
        var C = [Float](repeating: 0, count: n)
        image.pixels.withUnsafeBufferPointer { p in
            L.withUnsafeMutableBufferPointer { lp in
                C.withUnsafeMutableBufferPointer { cp in
                    let lpp = lp.baseAddress!, cpp = cp.baseAddress!
                    let w = image.width
                    DispatchQueue.concurrentPerform(iterations: image.height) { y in
                        for x in 0..<w {
                            let i = y * w + x
                            let lab = ColorMath.lab(r: p[i * 4], g: p[i * 4 + 1], b: p[i * 4 + 2])
                            lpp[i] = lab.L
                            cpp[i] = (lab.a * lab.a + lab.b * lab.b).squareRoot()
                        }
                    }
                }
            }
        }
        lightness = L
        chroma = C
        // Detail scale follows the photo size so strands look the same at any resolution.
        let r = max(2, Int((Float(max(image.width, image.height)) / 380).rounded()))
        let base = PlaneOps.boxBlur(Plane(width: image.width, height: image.height, data: L), radius: r)
        var d = [Float](repeating: 0, count: n)
        for i in 0..<n { d[i] = L[i] - base.data[i] }
        detail = d
    }

    var longSide: Int { max(width, height) }
}

/// Measurements of the hair that the recolouring needs.
struct HairStats: Equatable {
    var pixelCount: Int = 0
    /// Share of the photo covered by hair (matte sum / pixels).
    var coverage: Float = 0
    var medianL: Float = 35
    var p05L: Float = 15
    var p95L: Float = 55
    var meanChroma: Float = 8
    /// Median lightness of grey-looking strands (light, no chroma).
    var grayMedianL: Float = 60
    /// Share of hair pixels that look grey or white.
    var grayShare: Float = 0
    /// Bounding box (fractions of the photo) of hair with matte above 0.15. Zero size when there is no hair.
    var minX: Float = 0
    var maxX: Float = 0
    var minY: Float = 0
    var maxY: Float = 0
    /// Top and bottom rows of the hair mass (fractions), the 0 and 1 of the root-to-tip axis.
    var top: Float = 0
    var bottom: Float = 1
    /// Horizontal centre of the hair mass (fraction).
    var centerX: Float = 0.5

    var hasHair: Bool { pixelCount > 40 }
}

/// A photo plus a hair matte, ready to render looks. Cheap to rebuild when only the matte changes.
final class HairContext {
    let planes: PhotoPlanes
    let matte: Plane
    let stats: HairStats
    /// Pixel rows and columns that can contain hair, so loops skip the rest.
    private let rowRange: ClosedRange<Int>
    private let colRange: ClosedRange<Int>

    var width: Int { planes.width }
    var height: Int { planes.height }

    init(planes: PhotoPlanes, matte: Plane) {
        precondition(matte.width == planes.width && matte.height == planes.height, "matte and photo sizes differ")
        self.planes = planes
        self.matte = matte
        let s = HairContext.measure(planes: planes, matte: matte)
        self.stats = s
        if s.hasHair {
            let y0 = max(0, Int(s.minY * Float(planes.height)) - 2)
            let y1 = min(planes.height - 1, Int(s.maxY * Float(planes.height)) + 2)
            let x0 = max(0, Int(s.minX * Float(planes.width)) - 2)
            let x1 = min(planes.width - 1, Int(s.maxX * Float(planes.width)) + 2)
            rowRange = y0...max(y0, y1)
            colRange = x0...max(x0, x1)
        } else {
            rowRange = 0...0
            colRange = 0...0
        }
    }

    // MARK: Measuring

    static func measure(planes: PhotoPlanes, matte: Plane) -> HairStats {
        var s = HairStats()
        let w = planes.width, h = planes.height
        var hist = [Int](repeating: 0, count: 256)
        var grayHist = [Int](repeating: 0, count: 256)
        var count = 0, grayCount = 0
        var chromaSum: Double = 0
        var minX = w, maxX = -1, minY = h, maxY = -1
        var weightSum: Double = 0
        var xSum: Double = 0
        var rowMass = [Float](repeating: 0, count: h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let m = matte.data[i]
                if m > 0.15 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                if m > 0.5 {
                    count += 1
                    let L = planes.lightness[i]
                    let bin = min(255, max(0, Int(L * 2.55)))
                    hist[bin] += 1
                    chromaSum += Double(planes.chroma[i])
                    if planes.chroma[i] < 11 && L > 38 {
                        grayCount += 1
                        grayHist[bin] += 1
                    }
                    rowMass[y] += 1
                    weightSum += 1
                    xSum += Double(x)
                }
            }
        }
        s.pixelCount = count
        s.coverage = Float(matte.sum) / Float(max(1, w * h))
        guard count > 40 else { return s }
        func percentile(_ histogram: [Int], _ total: Int, _ q: Float) -> Float {
            let target = Int(Float(total) * q)
            var acc = 0
            for (b, c) in histogram.enumerated() {
                acc += c
                if acc >= target { return Float(b) / 2.55 }
            }
            return 50
        }
        s.medianL = percentile(hist, count, 0.5)
        s.p05L = percentile(hist, count, 0.05)
        s.p95L = percentile(hist, count, 0.95)
        s.meanChroma = Float(chromaSum / Double(count))
        s.grayShare = Float(grayCount) / Float(count)
        s.grayMedianL = grayCount > 40 ? percentile(grayHist, grayCount, 0.5) : max(s.medianL, 60)
        s.minX = Float(max(0, minX)) / Float(w)
        s.maxX = Float(min(w, maxX + 1)) / Float(w)
        s.minY = Float(max(0, minY)) / Float(h)
        s.maxY = Float(min(h, maxY + 1)) / Float(h)
        s.centerX = Float(xSum / max(1, weightSum)) / Float(w)
        // Root-to-tip axis: from the first row with real hair mass to the last.
        let rowThreshold = max(3, Float(w) * 0.004)
        var top = 0, bottom = h - 1
        while top < h - 1 && rowMass[top] < rowThreshold { top += 1 }
        while bottom > top && rowMass[bottom] < rowThreshold { bottom -= 1 }
        s.top = Float(top) / Float(h)
        s.bottom = Float(bottom + 1) / Float(h)
        if s.bottom - s.top < 0.05 { s.bottom = min(1, s.top + 0.05) }
        return s
    }

    // MARK: Rendering

    /// Applies the look to the hair and returns the whole photo. Pixels outside the matte are copied unchanged.
    func render(_ rawLook: HairLook) -> RGBAImage {
        let look = rawLook.sanitized()
        var out = planes.rgba
        guard stats.hasHair, !look.isNeutral else {
            return RGBAImage(width: width, height: height, pixels: out)
        }
        let p = RenderParameters(look: look, stats: stats, width: width, height: height)
        let w = width
        let rows = rowRange.lowerBound...rowRange.upperBound
        let c0 = colRange.lowerBound, c1 = colRange.upperBound
        planes.rgba.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let dp = dst.baseAddress!
                matte.data.withUnsafeBufferPointer { mp in
                    planes.lightness.withUnsafeBufferPointer { lp in
                        planes.detail.withUnsafeBufferPointer { dtp in
                            planes.chroma.withUnsafeBufferPointer { cp in
                                DispatchQueue.concurrentPerform(iterations: rows.count) { k in
                                    let y = rows.lowerBound + k
                                    for x in c0...c1 {
                                        let i = y * w + x
                                        let m = mp[i]
                                        if m < 0.02 { continue }
                                        let px = HairPixel.shade(
                                            p: p, x: x, y: y, matte: m,
                                            L: lp[i], detail: dtp[i], chroma: cp[i],
                                            r: src[i * 4], g: src[i * 4 + 1], b: src[i * 4 + 2]
                                        )
                                        if let px = px {
                                            dp[i * 4] = px.0
                                            dp[i * 4 + 1] = px.1
                                            dp[i * 4 + 2] = px.2
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }
}

/// Everything about a look that is constant across pixels, precomputed once per render.
struct RenderParameters {
    let look: HairLook
    let stats: HairStats
    let width: Int
    let height: Int
    let primary: (L: Float, a: Float, b: Float)
    let secondary: (L: Float, a: Float, b: Float)
    let invW: Float
    let invH: Float
    let topRow: Float
    let bottomRow: Float
    let rootSource: Float
    let sourceRange: Float
    let matteLo: Float
    let matteHi: Float
    let bboxW: Float

    init(look: HairLook, stats: HairStats, width: Int, height: Int) {
        self.look = look
        self.stats = stats
        self.width = width
        self.height = height
        primary = look.primary.lab
        secondary = look.secondary.lab
        invW = 1 / Float(width)
        invH = 1 / Float(height)
        topRow = stats.top
        bottomRow = max(stats.top + 0.05, stats.bottom)
        rootSource = look.grayCoverOnly ? stats.grayMedianL : stats.medianL
        sourceRange = max(10, stats.p95L - stats.p05L)
        let s = Float(look.edgeSoftness)
        matteLo = 0.02 + 0.12 * (1 - s)
        matteHi = 0.92 - 0.30 * s
        bboxW = max(0.05, stats.maxX - stats.minX)
    }
}

enum HairPixel {
    @inline(__always) static func hash(_ x: Int32, _ y: Int32, _ seed: UInt32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= (h >> 16)
        return Float(h & 0xFFFFFF) / Float(0x1000000)
    }

    /// Smooth value noise in 0...1.
    @inline(__always) static func noise(_ x: Float, _ y: Float, _ seed: UInt32) -> Float {
        let fx = floorf(x), fy = floorf(y)
        let ix = Int32(fx), iy = Int32(fy)
        var tx = x - fx, ty = y - fy
        tx = tx * tx * (3 - 2 * tx)
        ty = ty * ty * (3 - 2 * ty)
        let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed)
        let c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
        let top = a + (b - a) * tx
        let bot = c + (d - c) * tx
        return top + (bot - top) * ty
    }

    @inline(__always) static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        if e1 <= e0 { return x < e0 ? 0 : 1 }
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Streak mask in 0...1 for a given density. `scaleX` is the number of streaks across the photo, `scaleY` how many
    /// streak lengths fit the photo height. Streaks run along the hair, i.e. mostly vertical.
    @inline(__always) static func streaks(nx: Float, ny: Float, scaleX: Float, scaleY: Float, amount: Float, seed: UInt32) -> Float {
        let n1 = noise(nx * scaleX, ny * scaleY, seed)
        let n2 = noise(nx * scaleX * 2.3 + 17, ny * scaleY * 1.7 + 5, seed &+ 99)
        let n = 0.68 * n1 + 0.32 * n2
        // Noise values cluster around 0.5; move the threshold so that `amount` is roughly the covered share.
        let thr = 0.64 - 0.30 * amount
        return smooth(thr - 0.13, thr + 0.13, n)
    }

    /// Colours one pixel. Returns nil when the pixel is left alone.
    @inline(__always) static func shade(
        p: RenderParameters, x: Int, y: Int, matte: Float,
        L: Float, detail: Float, chroma: Float,
        r: UInt8, g: UInt8, b: UInt8
    ) -> (UInt8, UInt8, UInt8)? {
        let look = p.look
        if look.intensity < 0.001 {
            // Finishing tools only (smooth, definition): the colour stays, only the light and shade inside the hair change.
            let gain = (1 + 0.8 * Float(look.definition)) * (1 - 0.8 * Float(look.smooth))
            if abs(gain - 1) < 0.001 { return nil }
            let lab = ColorMath.lab(r: r, g: g, b: b)
            let newL = min(100, max(0, lab.L + detail * (gain - 1)))
            let rgb = ColorMath.srgb(L: newL, a: lab.a, b: lab.b)
            let a = smooth(p.matteLo, p.matteHi, matte)
            if a < 0.002 { return nil }
            let inv = 1 - a
            return (
                UInt8(min(255, max(0, Float(rgb.r) * a + Float(r) * inv + 0.5))),
                UInt8(min(255, max(0, Float(rgb.g) * a + Float(g) * inv + 0.5))),
                UInt8(min(255, max(0, Float(rgb.b) * a + Float(b) * inv + 0.5)))
            )
        }
        let nx = (Float(x) + 0.5) * p.invW
        let ny = (Float(y) + 0.5) * p.invH
        let t = min(max((ny - p.topRow) / (p.bottomRow - p.topRow), 0), 1)

        // 1. Colour field.
        var mix: Float = 0
        switch look.style {
        case .solid:
            mix = 0
        case .ombre:
            let start = Float(look.gradientStart)
            let end = min(1.02, start + 0.06 + Float(look.gradientSoftness) * (1 - start))
            mix = smooth(start, end, t)
        case .balayage:
            let amount = Float(look.streakAmount)
            // Hand-painted swaths drift sideways as they go down, like hair does, instead of running ruler-straight.
            let nxw = nx + 0.035 * (noise(ny * 2.6, 0.5, 5) - 0.5) + 0.012 * (noise(ny * 9, 3.5, 6) - 0.5)
            let s = streaks(nx: nxw, ny: ny, scaleX: 34, scaleY: 2.4, amount: amount, seed: 7)
            let ramp = smooth(Float(look.gradientStart) - 0.12, Float(look.gradientStart) + 0.30, t)
            // Streaks follow the real strand highlights a little, so they read as part of the hair.
            let follow = 0.65 + 0.35 * smooth(-6, 6, detail)
            mix = min(0.92, s * ramp * follow)
        case .highlights:
            let amount = Float(look.streakAmount)
            let nxw = nx + 0.02 * (noise(ny * 3.4, 1.5, 15) - 0.5)
            let s = streaks(nx: nxw, ny: ny, scaleX: 120, scaleY: 5.5, amount: amount * 0.75, seed: 31)
            let ramp = smooth(0.02, 0.2, t)
            let follow = 0.6 + 0.4 * smooth(-5, 5, detail)
            mix = min(1, s * ramp * follow)
        case .twoTone:
            let c = p.stats.minX + p.bboxW * Float(look.splitPosition)
            let edge = 0.012 + 0.01 * (1 - Float(look.edgeSoftness))
            mix = smooth(c - edge, c + edge, nx)
        }
        var Lt = p.primary.L + (p.secondary.L - p.primary.L) * mix
        var at = p.primary.a + (p.secondary.a - p.primary.a) * mix
        var bt = p.primary.b + (p.secondary.b - p.primary.b) * mix

        // 2. Root shadow and brightness.
        if look.rootShadow > 0.001 {
            let root = Float(look.rootShadow) * (1 - smooth(0, max(0.05, Float(look.rootDepth)), t))
            Lt *= 1 - 0.5 * root
            at *= 1 - 0.15 * root
            bt *= 1 - 0.15 * root
        }
        Lt = min(96, max(1.5, Lt + Float(look.brightness) * 22))
        // Real dye is never perfectly even: a slow, gentle variation in tone across the hair keeps the colour from looking painted.
        let variation = noise(nx * 7, ny * 2.2, 41) - 0.5
        Lt = min(96, max(1.5, Lt + variation * 7))

        // 3. Lightness: move the hair's own light and shade onto the new colour (with a lift for dark to light).
        let desiredRange = min(46, max(28, 46 - 0.45 * abs(Lt - 55)))
        // Very dark or very flat hair has little light and shade of its own; allow a stronger remap so the new colour keeps depth.
        let kcMax: Float = p.sourceRange < 26 ? 2.8 : 1.7
        let kc = min(kcMax, max(0.7, desiredRange / p.sourceRange))
        let base = L - detail
        var L1 = Lt + (base - p.rootSource) * kc
        var detailGain = min(kcMax > 2 ? 2.6 : 1.8, max(0.8, kc)) * (1 + 0.8 * Float(look.definition)) * (1 - 0.8 * Float(look.smooth))
        if look.smooth > 0.001 { detailGain = max(0.1, detailGain) }
        L1 += detail * detailGain
        // Shine: lift the lightest strands of the original and keep them nearly neutral.
        let spec = smooth(p.stats.p95L - 2, p.stats.p95L + 14, L)
        let shine = Float(look.shine)
        L1 += spec * shine * (96 - L1) * 0.5
        L1 = min(98, max(1, L1))

        // 4. Chroma follows the colour, but very dark and very light hair carries less of it.
        let lightFactor = 0.35 + 0.65 * smooth(2, 30, L1)
        let highFactor = 1 - smooth(88, 100, L1)
        let specDesat = 1 - spec * shine * 0.5
        let f = lightFactor * highFactor * specDesat * (0.9 + 0.1 * (1 - abs(variation) * 2))

        let lab = (L1, at * f, bt * f)
        let rgb = ColorMath.srgb(L: lab.0, a: lab.1, b: lab.2)

        // 5. Blend by the matte, the strength, and (for grey cover) how grey the strand is.
        var alpha = smooth(p.matteLo, p.matteHi, matte) * Float(look.intensity)
        if look.grayCoverOnly {
            let grayW = (1 - smooth(6, 14, chroma)) * smooth(34, 55, L)
            alpha *= grayW
        }
        if alpha < 0.002 { return nil }
        let inv = 1 - alpha
        let nr = Float(rgb.r) * alpha + Float(r) * inv
        let ng = Float(rgb.g) * alpha + Float(g) * inv
        let nb = Float(rgb.b) * alpha + Float(b) * inv
        return (UInt8(min(255, max(0, nr + 0.5))), UInt8(min(255, max(0, ng + 0.5))), UInt8(min(255, max(0, nb + 0.5))))
    }
}
