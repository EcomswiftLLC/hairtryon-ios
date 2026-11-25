import XCTest
import CoreML
import Vision
import UIKit
@testable import Lustra

/// Checks the bundled Core ML hair model (see docs/MODEL.md): interface, output range, and sane coverage on portraits.
/// Portrait fixtures are read from Tests/Fixtures/*.jpg|jpeg|png (found through the source path and through the test
/// bundle); tests that need them are skipped when none are present.
final class HairModelTests: XCTestCase {

    // MARK: Helpers

    private func loadModel() throws -> MLModel {
        let bundle = Bundle(for: CoreMLHairSegmenter.self)
        guard let url = bundle.url(forResource: "HairSegmenter", withExtension: "mlmodelc") else {
            XCTFail("HairSegmenter.mlmodelc is not in the app bundle (Sources/Resources/Models/HairSegmenter.mlpackage)")
            throw HairEngineError.modelMissing
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: config)
    }

    private func fixtureURLs() -> [URL] {
        let exts: Set<String> = ["jpg", "jpeg", "png"]
        var roots: [URL] = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")]
        if let resources = Bundle(for: HairModelTests.self).resourceURL { roots.append(resources) }
        var urls: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where exts.contains(url.pathExtension.lowercased()) { urls.append(url) }
        }
        // De-duplicate by file name (the same fixture can be found twice) and sort for stable output.
        var seen = Set<String>()
        return urls.filter { seen.insert($0.lastPathComponent).inserted }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Fixtures named edge-*.jpg are deliberately hard (hats, hoods, groups, no person): only the output validity is asserted for them.
    private func isEdgeCase(_ url: URL) -> Bool { url.lastPathComponent.hasPrefix("edge-") }

    private func cgImage(at url: URL) throws -> CGImage {
        guard let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage else {
            throw HairEngineError.imageUnreadable
        }
        return cg
    }

    // MARK: Interface (docs/MODEL.md)

    func testModelInterfaceMatchesDocs() throws {
        let model = try loadModel()
        let inputs = model.modelDescription.inputDescriptions
        XCTAssertEqual(inputs.count, 1)
        let input = try XCTUnwrap(inputs["image"], "input must be named image")
        XCTAssertEqual(input.type, .image)
        let constraint = try XCTUnwrap(input.imageConstraint)
        XCTAssertEqual(constraint.pixelsWide, 512)
        XCTAssertEqual(constraint.pixelsHigh, 512)

        let outputs = model.modelDescription.outputDescriptions
        XCTAssertEqual(outputs.count, 1)
        let output = try XCTUnwrap(outputs["hair_probability"], "output must be named hair_probability")
        XCTAssertEqual(output.type, .multiArray)
        let shape = try XCTUnwrap(output.multiArrayConstraint).shape.map { $0.intValue }
        XCTAssertEqual(shape, [1, 1, 512, 512])
    }

    /// Flat grey picture: the model must answer with a valid, finite 0...1 map and (almost) no hair.
    func testGreyImageGivesValidMapWithNoHair() throws {
        let model = try loadModel()
        let size = 512
        var pixels = [UInt8](repeating: 128, count: size * size * 4)
        for i in 0..<(size * size) { pixels[i * 4 + 3] = 255 }
        let cs = CGColorSpaceCreateDeviceRGB()
        let made: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let cg = try XCTUnwrap(made)
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(cgImage: cg, pixelsWide: size, pixelsHigh: size,
                                                                                         pixelFormatType: kCVPixelFormatType_32BGRA, options: nil)])
        let out = try model.prediction(from: input)
        let array = try XCTUnwrap(out.featureValue(for: "hair_probability")?.multiArrayValue)
        XCTAssertEqual(array.shape.map { $0.intValue }, [1, 1, 512, 512])
        var lo: Float = .infinity, hi: Float = -.infinity, sum: Double = 0
        for i in 0..<array.count {
            let v = array[i].floatValue
            XCTAssertFalse(v.isNaN)
            lo = min(lo, v); hi = max(hi, v); sum += Double(v)
        }
        XCTAssertGreaterThanOrEqual(lo, 0)
        XCTAssertLessThanOrEqual(hi, 1)
        XCTAssertLessThan(sum / Double(array.count), 0.05, "a flat grey picture has no hair")
    }

    // MARK: Portraits

    /// Through the same path the app uses (Vision, scaleFill, MLMultiArray -> Plane).
    func testPortraitsHaveSaneHairCoverage() throws {
        let urls = fixtureURLs()
        try XCTSkipIf(urls.isEmpty, "No portrait fixtures in Tests/Fixtures yet")
        let segmenter = try CoreMLHairSegmenter(bundle: Bundle(for: CoreMLHairSegmenter.self))
        for url in urls {
            let cg = try cgImage(at: url)
            let plane = try segmenter.hairProbability(square: cg)
            XCTAssertEqual(plane.width, 512, url.lastPathComponent)
            XCTAssertEqual(plane.height, 512, url.lastPathComponent)

            var lo: Float = .infinity, hi: Float = -.infinity, hair = 0
            for v in plane.data {
                XCTAssertFalse(v.isNaN, url.lastPathComponent)
                lo = min(lo, v); hi = max(hi, v)
                if v >= 0.5 { hair += 1 }
            }
            XCTAssertGreaterThanOrEqual(lo, -0.001, url.lastPathComponent)
            XCTAssertLessThanOrEqual(hi, 1.001, url.lastPathComponent)

            let coverage = Float(hair) / Float(plane.count)
            if !isEdgeCase(url) {
                // Whole photo stretched to 512 (worst case for the model): hair is a few percent up to about half the frame.
                XCTAssertGreaterThan(coverage, 0.01, "\(url.lastPathComponent): hair found (coverage \(coverage))")
                XCTAssertLessThan(coverage, 0.55, "\(url.lastPathComponent): not everything is hair (coverage \(coverage))")
            }
            print("HairModelTests \(url.lastPathComponent): coverage \(coverage), min \(lo), max \(hi)")
        }
    }

    /// The hair of an upright portrait sits in the upper part of the frame: more hair in the top half than in the bottom quarter.
    func testHairIsAboveTheChinLine() throws {
        let urls = fixtureURLs()
        try XCTSkipIf(urls.isEmpty, "No portrait fixtures in Tests/Fixtures yet")
        let segmenter = try CoreMLHairSegmenter(bundle: Bundle(for: CoreMLHairSegmenter.self))
        var checked = 0
        for url in urls where !isEdgeCase(url) {
            let plane = try segmenter.hairProbability(square: try cgImage(at: url))
            let h = plane.height, w = plane.width
            var top: Float = 0, bottom: Float = 0
            for y in 0..<h {
                var row: Float = 0
                for x in 0..<w { row += plane.data[y * w + x] }
                if y < h / 2 { top += row } else if y >= h * 3 / 4 { bottom += row }
            }
            if top + bottom < 1 { continue }
            checked += 1
            XCTAssertGreaterThan(top, bottom * 0.5, "\(url.lastPathComponent): hair should be mostly in the upper half")
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
