import Foundation
import UIKit
import CoreGraphics

/// How much detail a context holds. Sliders use `preview`, palettes and thumbnails use `thumb`, saving uses `full`.
enum DetailLevel: CaseIterable {
    case thumb, preview, full

    var maxSide: Int {
        switch self {
        case .thumb: return 360
        case .preview: return 960
        case .full: return HairSession.fullSide
        }
    }
}

/// One photo being edited: the pixels, the hair matte found by the model, and the analysis.
/// Everything here is computed on the device. Methods are safe to call from a background queue, one at a time.
final class HairSession: @unchecked Sendable {
    /// The longest side of the full-quality image the engine works on and saves.
    static let fullSide = 2048

    let source: RGBAImage
    private(set) var analysis: PhotoAnalysis
    private(set) var faces: [FaceInfo]
    /// The matte from the model after edge snapping, at `source` size, before any brush strokes.
    private(set) var baseMatte: Plane
    private let matteSource: HairMatteSource

    private var planesCache: [Int: PhotoPlanes] = [:]
    private var matteCache: [Int: Plane] = [:]
    private let lock = NSLock()

    private init(source: RGBAImage, faces: [FaceInfo], analysis: PhotoAnalysis, baseMatte: Plane, matteSource: HairMatteSource) {
        self.source = source
        self.faces = faces
        self.analysis = analysis
        self.baseMatte = baseMatte
        self.matteSource = matteSource
    }

    // MARK: Opening a photo

    /// Opens a photo: finds faces, runs the hair model, snaps the matte to real hair edges, and builds the hints.
    static func open(image: UIImage, matteSource: HairMatteSource, faceIndex: Int? = nil) throws -> HairSession {
        guard let rgba = RGBAImage(uiImage: image, maxSide: fullSide) else { throw HairEngineError.imageUnreadable }
        return try open(rgba: rgba, matteSource: matteSource, faceIndex: faceIndex)
    }

    static func open(rgba: RGBAImage, matteSource: HairMatteSource, faceIndex: Int? = nil) throws -> HairSession {
        guard let cg = rgba.cgImage() else { throw HairEngineError.imageUnreadable }
        let faces = FaceAnalyzer.detectFaces(in: cg)
        let selected: Int? = faces.isEmpty ? nil : min(max(0, faceIndex ?? 0), faces.count - 1)
        let matte = try computeMatte(rgba: rgba, faces: faces, selected: selected, matteSource: matteSource)
        let session = HairSession(
            source: rgba, faces: faces,
            analysis: PhotoAnalysis(faces: faces, selectedFace: selected),
            baseMatte: matte, matteSource: matteSource
        )
        session.refreshAnalysis()
        return session
    }

    /// Chooses another face and recomputes the matte for that person.
    func selectFace(_ index: Int) throws {
        guard index >= 0, index < faces.count else { return }
        let matte = try HairSession.computeMatte(rgba: source, faces: faces, selected: index, matteSource: matteSource)
        lock.lock()
        baseMatte = matte
        matteCache.removeAll()
        analysis.selectedFace = index
        lock.unlock()
        refreshAnalysis()
    }

    private func refreshAnalysis() {
        let selected = analysis.selectedFace
        var region: CGRect? = nil
        if let s = selected, s < faces.count { region = faces[s].rect.insetBy(dx: -faces[s].rect.width * 0.2, dy: -faces[s].rect.height * 0.2) }
        let sharp = FaceAnalyzer.sharpness(of: source, region: region)
        let luma = FaceAnalyzer.meanLuma(of: source)
        let coverage = baseMatte.sum / Float(max(1, baseMatte.count))
        var a = analysis
        a.sharpness = sharp
        a.meanLuma = luma
        a.hairCoverage = coverage
        a.hints = FaceAnalyzer.hints(
            faces: faces, selected: selected, sharpness: sharp, meanLuma: luma,
            hairCoverage: coverage, longSide: max(source.width, source.height)
        )
        analysis = a
    }

    // MARK: Contexts

    func planes(_ level: DetailLevel) -> PhotoPlanes {
        lock.lock()
        defer { lock.unlock() }
        let key = level.maxSide
        if let p = planesCache[key] { return p }
        let img = max(source.width, source.height) > key ? source.resized(maxSide: key) : source
        let p = PhotoPlanes(image: img)
        planesCache[key] = p
        return p
    }

    /// The matte for a level with brush strokes applied.
    func matte(_ level: DetailLevel, strokes: [BrushStroke]) -> Plane {
        let p = planes(level)
        lock.lock()
        let key = level.maxSide
        var base: Plane
        if let cached = matteCache[key], cached.width == p.width, cached.height == p.height {
            base = cached
        } else {
            base = PlaneOps.resize(baseMatte, width: p.width, height: p.height)
            matteCache[key] = base
        }
        lock.unlock()
        return MatteRefiner.apply(strokes, to: base)
    }

    func context(_ level: DetailLevel, strokes: [BrushStroke] = []) -> HairContext {
        HairContext(planes: planes(level), matte: matte(level, strokes: strokes))
    }

    // MARK: Matte computation

    /// Output size of the square the model sees.
    private static let canvasSide = 640

    static func computeMatte(rgba: RGBAImage, faces: [FaceInfo], selected: Int?, matteSource: HairMatteSource) throws -> Plane {
        let W = rgba.width, H = rgba.height
        let longSide = Float(max(W, H))
        // The region the model looks at: around the chosen face, or the whole photo.
        var cx = Float(W) / 2, cy = Float(H) / 2
        var side = longSide
        var useWindow = false
        if let s = selected, s < faces.count {
            let r = faces[s].rect
            let fw = Float(r.width) * Float(W), fh = Float(r.height) * Float(H)
            let faceSide = max(fw * 3.4, fh * 4.2)
            if faceSide < longSide * 0.9 {
                cx = Float(r.midX) * Float(W)
                cy = Float(r.midY) * Float(H) + 0.55 * fh
                side = faceSide
                useWindow = faces.count > 1
            }
        }
        let rx = cx - side / 2, ry = cy - side / 2
        let scale = Float(canvasSide) / side

        // Draw the region into a square canvas, padding with mid grey where it leaves the photo.
        guard let cg = rgba.cgImage() else { throw HairEngineError.imageUnreadable }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSide, height: canvasSide), format: format)
        let canvas = renderer.image { ctx in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
            UIImage(cgImage: cg).draw(in: CGRect(
                x: CGFloat(-rx * scale), y: CGFloat(-ry * scale),
                width: CGFloat(Float(W) * scale), height: CGFloat(Float(H) * scale)
            ))
        }
        guard let canvasCG = canvas.cgImage else { throw HairEngineError.imageUnreadable }
        let prob = try matteSource.hairProbability(square: canvasCG)

        // Map the model answer back onto the photo.
        var out = [Float](repeating: 0, count: W * H)
        let pw = prob.width, ph = prob.height
        prob.data.withUnsafeBufferPointer { pp in
            out.withUnsafeMutableBufferPointer { op in
                let o = op.baseAddress!
                DispatchQueue.concurrentPerform(iterations: H) { y in
                    let v = (Float(y) + 0.5 - ry) * scale / Float(canvasSide) * Float(ph) - 0.5
                    if v < -1 || v > Float(ph) { return }
                    let y0 = max(0, min(ph - 1, Int(floorf(v)))), y1 = min(ph - 1, y0 + 1)
                    let wy = min(max(v - Float(y0), 0), 1)
                    for x in 0..<W {
                        let u = (Float(x) + 0.5 - rx) * scale / Float(canvasSide) * Float(pw) - 0.5
                        if u < -1 || u > Float(pw) { continue }
                        let x0 = max(0, min(pw - 1, Int(floorf(u)))), x1 = min(pw - 1, x0 + 1)
                        let wx = min(max(u - Float(x0), 0), 1)
                        let a = pp[y0 * pw + x0] * (1 - wx) + pp[y0 * pw + x1] * wx
                        let b = pp[y1 * pw + x0] * (1 - wx) + pp[y1 * pw + x1] * wx
                        o[y * W + x] = a * (1 - wy) + b * wy
                    }
                }
            }
        }
        var matte = Plane(width: W, height: H, data: out)

        // Keep other people's hair out of the picture when the model saw several faces.
        if useWindow {
            let feather = side * 0.12
            for y in 0..<H {
                let dy = min(Float(y) - ry, ry + side - Float(y))
                let wy = PlaneOps.smoothstep(0, feather, dy)
                for x in 0..<W {
                    let dx = min(Float(x) - rx, rx + side - Float(x))
                    matte.data[y * W + x] *= wy * PlaneOps.smoothstep(0, feather, dx)
                }
            }
        }
        return refine(matte: matte, rgba: rgba)
    }

    /// Sharpens the model's soft answer and snaps it to real edges with a guided filter.
    static func refine(matte: Plane, rgba: RGBAImage) -> Plane {
        var shaped = matte
        for i in 0..<shaped.data.count { shaped.data[i] = PlaneOps.smoothstep(0.12, 0.88, shaped.data[i]) }
        let long = max(rgba.width, rgba.height)
        let radius = max(3, long / 220)
        let guide = rgba.lumaPlane()
        var q = PlaneOps.guidedFilter(guide: guide, input: shaped, radius: radius, eps: 0.0012)
        // The filter may leak a little past the model's mask: do not let it spread more than a few pixels.
        let limit = PlaneOps.softDilate(shaped, radius: max(2, radius))
        for i in 0..<q.data.count {
            let v = (q.data[i] - 0.5) * 1.25 + 0.5
            q.data[i] = min(1, max(0, v)) * limit.data[i]
        }
        return q
    }
}
