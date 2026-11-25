import Foundation
import CoreML
import Vision
import CoreGraphics

enum HairEngineError: Error, LocalizedError {
    case modelMissing
    case modelOutputUnreadable
    case imageUnreadable
    case modelFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "The hair detection model is missing from this build."
        case .modelOutputUnreadable: return "The hair detection model gave an answer Lustra could not read."
        case .imageUnreadable: return "This photo could not be opened."
        case .modelFailed(let m): return "Hair detection failed: \(m)"
        }
    }
}

/// Anything that can say, for a square image, how likely each pixel is hair (0...1).
protocol HairMatteSource {
    /// `square` is the model input (any size, the source resizes it). The result may have any size, it covers the whole input.
    func hairProbability(square: CGImage) throws -> Plane
}

/// Describes how to read the Core ML model, see docs/MODEL.md.
struct HairModelInterface {
    /// Index of the hair channel when the output has several channels. nil = pick automatically (last channel).
    var hairChannel: Int? = nil
    /// Name of the output feature. nil = the first output that is a multi-array or an image.
    var outputName: String? = nil
    static let `default` = HairModelInterface()
}

/// Runs the bundled Core ML hair model through Vision (which resizes the image to the model input).
final class CoreMLHairSegmenter: HairMatteSource {
    static let modelName = "HairSegmenter"

    private let model: VNCoreMLModel
    private let interface: HairModelInterface

    init(bundle: Bundle = .main, interface: HairModelInterface = .default) throws {
        guard let url = bundle.url(forResource: CoreMLHairSegmenter.modelName, withExtension: "mlmodelc") else {
            throw HairEngineError.modelMissing
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        do {
            let ml = try MLModel(contentsOf: url, configuration: config)
            model = try VNCoreMLModel(for: ml)
        } catch {
            throw HairEngineError.modelFailed(error.localizedDescription)
        }
        self.interface = interface
    }

    func hairProbability(square: CGImage) throws -> Plane {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: square, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw HairEngineError.modelFailed(error.localizedDescription)
        }
        guard let results = request.results, !results.isEmpty else { throw HairEngineError.modelOutputUnreadable }
        for r in results {
            if let fv = r as? VNCoreMLFeatureValueObservation {
                if let name = interface.outputName, fv.featureName != name { continue }
                if let array = fv.featureValue.multiArrayValue {
                    return try CoreMLHairSegmenter.plane(from: array, hairChannel: interface.hairChannel)
                }
                if let buffer = fv.featureValue.imageBufferValue {
                    return try CoreMLHairSegmenter.plane(from: buffer)
                }
            }
            if let pb = r as? VNPixelBufferObservation {
                return try CoreMLHairSegmenter.plane(from: pb.pixelBuffer)
            }
        }
        throw HairEngineError.modelOutputUnreadable
    }

    // MARK: Output parsing

    /// Reads a hair probability plane from a multi-array shaped [H,W], [1,H,W], [H,W,C], [C,H,W], [1,H,W,C] or [1,C,H,W].
    static func plane(from array: MLMultiArray, hairChannel: Int?) throws -> Plane {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        var h = 0, w = 0, channels = 1
        var hs = 0, ws = 0, cs = 0
        switch shape.count {
        case 2:
            h = shape[0]; w = shape[1]; hs = strides[0]; ws = strides[1]
        case 3:
            if shape[0] <= 4 && shape[1] > 8 {
                channels = shape[0]; h = shape[1]; w = shape[2]; cs = strides[0]; hs = strides[1]; ws = strides[2]
            } else if shape[2] <= 4 && shape[0] > 8 {
                h = shape[0]; w = shape[1]; channels = shape[2]; hs = strides[0]; ws = strides[1]; cs = strides[2]
            } else {
                h = shape[1]; w = shape[2]; hs = strides[1]; ws = strides[2]
            }
        case 4:
            if shape[3] <= 4 && shape[1] > 8 {
                h = shape[1]; w = shape[2]; channels = shape[3]; hs = strides[1]; ws = strides[2]; cs = strides[3]
            } else {
                channels = shape[1]; h = shape[2]; w = shape[3]; cs = strides[1]; hs = strides[2]; ws = strides[3]
            }
        default:
            throw HairEngineError.modelOutputUnreadable
        }
        guard h > 0, w > 0 else { throw HairEngineError.modelOutputUnreadable }
        let channel = min(max(0, hairChannel ?? (channels - 1)), channels - 1)

        func value(_ c: Int, _ y: Int, _ x: Int) -> Float {
            let idx = c * cs + y * hs + x * ws
            switch array.dataType {
            case .float32:
                return array.dataPointer.assumingMemoryBound(to: Float.self)[idx]
            case .float16:
                return Float(array.dataPointer.assumingMemoryBound(to: Float16.self)[idx])
            case .double:
                return Float(array.dataPointer.assumingMemoryBound(to: Double.self)[idx])
            default:
                return array[idx].floatValue
            }
        }

        var out = [Float](repeating: 0, count: w * h)
        var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
        for y in 0..<h {
            for x in 0..<w {
                let v = value(channel, y, x)
                out[y * w + x] = v
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
        }
        // Logits (outside 0...1) become probabilities: softmax against the other channel for two classes, sigmoid otherwise.
        if lo < -0.01 || hi > 1.01 {
            if channels == 2 {
                let other = 1 - channel
                for y in 0..<h {
                    for x in 0..<w {
                        let a = out[y * w + x], b = value(other, y, x)
                        let m = max(a, b)
                        let ea = expf(a - m), eb = expf(b - m)
                        out[y * w + x] = ea / (ea + eb)
                    }
                }
            } else {
                for i in 0..<out.count { out[i] = 1 / (1 + expf(-out[i])) }
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// Reads a probability plane from a one-channel (8-bit or float) pixel buffer.
    static func plane(from buffer: CVPixelBuffer) throws -> Plane {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw HairEngineError.modelOutputUnreadable }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * bpr)
            switch format {
            case kCVPixelFormatType_OneComponent8:
                let p = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { out[y * w + x] = Float(p[x]) / 255 }
            case kCVPixelFormatType_OneComponent32Float:
                let p = row.assumingMemoryBound(to: Float.self)
                for x in 0..<w { out[y * w + x] = p[x] }
            case kCVPixelFormatType_OneComponent16Half:
                let p = row.assumingMemoryBound(to: Float16.self)
                for x in 0..<w { out[y * w + x] = Float(p[x]) }
            case kCVPixelFormatType_32BGRA:
                let p = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { out[y * w + x] = Float(p[x * 4 + 1]) / 255 }
            default:
                throw HairEngineError.modelOutputUnreadable
            }
        }
        return Plane(width: w, height: h, data: out)
    }
}
