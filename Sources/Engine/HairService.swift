import Foundation
import UIKit

/// The one place the app opens photos. Loads the bundled hair model once and runs the heavy work off the main thread.
final class HairService: @unchecked Sendable {
    static let shared = HairService()

    private let lock = NSLock()
    private var cached: HairMatteSource?
    private var cachedError: Error?
    /// Tests and previews can replace the model.
    private var override: HairMatteSource?

    private init() {}

    func setMatteSourceForTesting(_ source: HairMatteSource?) {
        lock.lock(); override = source; lock.unlock()
    }

    /// The model runner, loaded on first use.
    func matteSource() throws -> HairMatteSource {
        lock.lock(); defer { lock.unlock() }
        if let o = override { return o }
        if let c = cached { return c }
        if let e = cachedError { throw e }
        do {
            let s = try CoreMLHairSegmenter()
            cached = s
            return s
        } catch {
            cachedError = error
            throw error
        }
    }

    /// Opens a photo and finds the hair. Runs on a background thread.
    func open(image: UIImage, faceIndex: Int? = nil) async throws -> HairSession {
        let source = try matteSource()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try HairSession.open(image: image, matteSource: source, faceIndex: faceIndex))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Chooses another face in an open session, off the main thread.
    func selectFace(_ index: Int, in session: HairSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.selectFace(index)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Renders a look on a background thread and returns a UIImage.
    func render(_ context: HairContext, look: HairLook) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: context.render(look).uiImage())
            }
        }
    }
}
