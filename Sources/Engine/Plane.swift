import Foundation
import Accelerate

/// A single-channel Float image. Values are usually 0...1 (mattes, masks) but any range is allowed.
struct Plane: Equatable {
    var width: Int
    var height: Int
    var data: [Float]

    init(width: Int, height: Int, fill: Float = 0) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.data = [Float](repeating: fill, count: self.width * self.height)
    }

    init(width: Int, height: Int, data: [Float]) {
        self.width = max(1, width)
        self.height = max(1, height)
        precondition(data.count == self.width * self.height, "Plane data size mismatch")
        self.data = data
    }

    var count: Int { width * height }

    subscript(x: Int, y: Int) -> Float {
        get { data[y * width + x] }
        set { data[y * width + x] = newValue }
    }

    /// Mean of all values.
    var mean: Float {
        guard !data.isEmpty else { return 0 }
        var m: Float = 0
        vDSP_meanv(data, 1, &m, vDSP_Length(data.count))
        return m
    }

    /// Sum of all values.
    var sum: Float {
        guard !data.isEmpty else { return 0 }
        var s: Float = 0
        vDSP_sve(data, 1, &s, vDSP_Length(data.count))
        return s
    }

    mutating func clamp01() {
        for i in 0..<data.count { data[i] = min(1, max(0, data[i])) }
    }
}

enum PlaneOps {
    /// Moving-average blur with clamped edges. O(n), independent of the radius.
    static func boxBlur(_ src: Plane, radius r: Int) -> Plane {
        guard r > 0 else { return src }
        let w = src.width, h = src.height
        var tmp = [Float](repeating: 0, count: w * h)
        var out = [Float](repeating: 0, count: w * h)
        let norm = 1 / Float(2 * r + 1)
        src.data.withUnsafeBufferPointer { s in
            tmp.withUnsafeMutableBufferPointer { t in
                let tp = t.baseAddress!
                DispatchQueue.concurrentPerform(iterations: h) { y in
                    let row = y * w
                    var sum: Float = 0
                    for k in -r...r { sum += s[row + min(max(k, 0), w - 1)] }
                    for x in 0..<w {
                        tp[row + x] = sum * norm
                        let add = min(x + r + 1, w - 1)
                        let sub = max(x - r, 0)
                        sum += s[row + add] - s[row + sub]
                    }
                }
            }
        }
        // Vertical pass: slide a running row sum so memory access stays sequential.
        tmp.withUnsafeBufferPointer { t in
            out.withUnsafeMutableBufferPointer { o in
                var colSum = [Float](repeating: 0, count: w)
                for k in -r...r {
                    let yy = min(max(k, 0), h - 1)
                    for x in 0..<w { colSum[x] += t[yy * w + x] }
                }
                for y in 0..<h {
                    for x in 0..<w { o[y * w + x] = colSum[x] * norm }
                    let add = min(y + r + 1, h - 1)
                    let sub = max(y - r, 0)
                    for x in 0..<w { colSum[x] += t[add * w + x] - t[sub * w + x] }
                }
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// Bilinear resample to a new size.
    static func resize(_ src: Plane, width: Int, height: Int) -> Plane {
        let nw = max(1, width), nh = max(1, height)
        if nw == src.width && nh == src.height { return src }
        var out = [Float](repeating: 0, count: nw * nh)
        let sw = src.width, sh = src.height
        let sx = Float(sw) / Float(nw)
        let sy = Float(sh) / Float(nh)
        src.data.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                let op = o.baseAddress!
                DispatchQueue.concurrentPerform(iterations: nh) { y in
                    let fy = (Float(y) + 0.5) * sy - 0.5
                    let y0 = max(0, min(sh - 1, Int(floorf(fy))))
                    let y1 = min(sh - 1, y0 + 1)
                    let wy = min(max(fy - Float(y0), 0), 1)
                    for x in 0..<nw {
                        let fx = (Float(x) + 0.5) * sx - 0.5
                        let x0 = max(0, min(sw - 1, Int(floorf(fx))))
                        let x1 = min(sw - 1, x0 + 1)
                        let wx = min(max(fx - Float(x0), 0), 1)
                        let a = s[y0 * sw + x0] * (1 - wx) + s[y0 * sw + x1] * wx
                        let b = s[y1 * sw + x0] * (1 - wx) + s[y1 * sw + x1] * wx
                        op[y * nw + x] = a * (1 - wy) + b * wy
                    }
                }
            }
        }
        return Plane(width: nw, height: nh, data: out)
    }

    /// Guided filter (He et al.) with a grey guide, used to snap a coarse matte to real hair edges.
    static func guidedFilter(guide: Plane, input: Plane, radius: Int, eps: Float) -> Plane {
        precondition(guide.width == input.width && guide.height == input.height)
        let n = guide.count
        let w = guide.width, h = guide.height
        let meanI = boxBlur(guide, radius: radius)
        let meanP = boxBlur(input, radius: radius)
        var ii = [Float](repeating: 0, count: n)
        var ip = [Float](repeating: 0, count: n)
        for i in 0..<n {
            ii[i] = guide.data[i] * guide.data[i]
            ip[i] = guide.data[i] * input.data[i]
        }
        let corrI = boxBlur(Plane(width: w, height: h, data: ii), radius: radius)
        let corrIP = boxBlur(Plane(width: w, height: h, data: ip), radius: radius)
        var a = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let varI = corrI.data[i] - meanI.data[i] * meanI.data[i]
            let covIP = corrIP.data[i] - meanI.data[i] * meanP.data[i]
            let ai = covIP / (varI + eps)
            a[i] = ai
            b[i] = meanP.data[i] - ai * meanI.data[i]
        }
        let meanA = boxBlur(Plane(width: w, height: h, data: a), radius: radius)
        let meanB = boxBlur(Plane(width: w, height: h, data: b), radius: radius)
        var q = [Float](repeating: 0, count: n)
        for i in 0..<n {
            q[i] = min(1, max(0, meanA.data[i] * guide.data[i] + meanB.data[i]))
        }
        return Plane(width: w, height: h, data: q)
    }

    /// Blur then boost, so a refined matte cannot spread far from the model's estimate.
    static func softDilate(_ src: Plane, radius: Int) -> Plane {
        var p = boxBlur(src, radius: radius)
        for i in 0..<p.data.count { p.data[i] = min(1, p.data[i] * 4) }
        return p
    }

    @inline(__always) static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        if e0 == e1 { return x < e0 ? 0 : 1 }
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
