import Foundation
import CoreGraphics
import Vision

/// One face found in the photo. `rect` is in fractions of the photo with the origin at the top left.
struct FaceInfo: Equatable, Identifiable {
    var id: Int
    var rect: CGRect
    var area: CGFloat { rect.width * rect.height }
}

/// Something worth telling the person before they spend time on a photo.
enum PhotoHint: Equatable {
    case noFace
    case multipleFaces(Int)
    case blurry
    case lowLight
    case smallFace
    case hairHidden
    case noHairFound
    case lowResolution

    /// Short text for the hint banner.
    var message: String {
        switch self {
        case .noFace:
            return "No face found. Hair is still detected, but a photo that shows the face works best."
        case .multipleFaces(let n):
            return "\(n) faces found. Tap a face to choose whose hair to colour."
        case .blurry:
            return "This photo looks blurry, so hair edges may be soft. A sharper photo gives a cleaner result."
        case .lowLight:
            return "This photo is dark. Colours look truer in good light."
        case .smallFace:
            return "The face is small in this photo. Move closer for a cleaner hair edge."
        case .hairHidden:
            return "Little hair is visible, maybe because of a hat or hood. Try a photo that shows the hair."
        case .noHairFound:
            return "We could not find hair in this photo. Try another photo, or paint the hair area with Refine."
        case .lowResolution:
            return "This photo is small, so the result will be small too."
        }
    }

    /// True for hints that mean the result will probably look wrong.
    var isWarning: Bool {
        switch self {
        case .noHairFound, .hairHidden, .blurry: return true
        default: return false
        }
    }
}

struct PhotoAnalysis: Equatable {
    var faces: [FaceInfo] = []
    var selectedFace: Int? = nil
    var sharpness: Float = 0
    var meanLuma: Float = 0.5
    var hairCoverage: Float = 0
    var hints: [PhotoHint] = []
}

enum FaceAnalyzer {
    /// Finds faces with Vision. Never throws: a failure means "no faces".
    static func detectFaces(in image: CGImage) -> [FaceInfo] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        var faces: [FaceInfo] = []
        for o in observations {
            let b = o.boundingBox
            // Vision uses a bottom-left origin.
            let rect = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            faces.append(FaceInfo(id: 0, rect: rect))
        }
        faces.sort { $0.area > $1.area }
        for i in faces.indices { faces[i].id = i }
        return faces
    }

    /// Variance of a Laplacian on a small luma copy. Low values mean a soft or blurry photo.
    static func sharpness(of image: RGBAImage, region: CGRect? = nil) -> Float {
        var source = image
        if let region = region, let crop = image.cropped(CGRect(
            x: region.minX * CGFloat(image.width), y: region.minY * CGFloat(image.height),
            width: region.width * CGFloat(image.width), height: region.height * CGFloat(image.height))) {
            source = crop
        }
        source = source.resized(maxSide: 360)
        let w = source.width, h = source.height
        guard w > 4, h > 4 else { return 0 }
        let luma = source.lumaPlane().data.map { $0 * 255 }
        var sum: Double = 0
        var sumSq: Double = 0
        var n = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let lap = luma[i - w] + luma[i + w] + luma[i - 1] + luma[i + 1] - 4 * luma[i]
                sum += Double(lap)
                sumSq += Double(lap * lap)
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = sum / Double(n)
        return Float(sumSq / Double(n) - mean * mean)
    }

    static func meanLuma(of image: RGBAImage) -> Float {
        let small = image.resized(maxSide: 128)
        let plane = small.lumaPlane()
        return plane.mean
    }

    /// Builds the list of hints for a photo.
    static func hints(faces: [FaceInfo], selected: Int?, sharpness: Float, meanLuma: Float, hairCoverage: Float, longSide: Int) -> [PhotoHint] {
        var hints: [PhotoHint] = []
        if faces.isEmpty { hints.append(.noFace) }
        let significant = faces.filter { f in (faces.first.map { f.area > $0.area * 0.3 } ?? false) }
        if significant.count > 1 { hints.append(.multipleFaces(significant.count)) }
        if sharpness < 18 { hints.append(.blurry) }
        if meanLuma < 0.2 { hints.append(.lowLight) }
        if let s = selected, s < faces.count, faces[s].rect.height < 0.1 { hints.append(.smallFace) }
        if longSide < 700 { hints.append(.lowResolution) }
        if hairCoverage < 0.003 {
            hints.append(.noHairFound)
        } else if let s = selected, s < faces.count, hairCoverage < Float(faces[s].area) * 0.45 {
            hints.append(.hairHidden)
        }
        return hints
    }
}
