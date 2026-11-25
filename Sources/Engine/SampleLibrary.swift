import Foundation
import UIKit
import ImageIO

/// One bundled sample photo (see Sources/Resources/Samples/samples.json and docs/store/photo-credits.md).
struct SamplePhoto: Identifiable, Equatable {
    var file: String
    var title: String
    var credit: String
    var id: String { file }
    var name: String { (file as NSString).deletingPathExtension }
}

/// The sample photos that ship inside the app, for people who want to try Lustra before using their own photo.
enum SampleLibrary {
    private static let photoExtensions = ["jpg", "jpeg", "png", "heic"]

    private static func urls(bundle: Bundle) -> [URL] {
        var found = [URL]()
        for ext in photoExtensions {
            found += bundle.urls(forResourcesWithExtension: ext, subdirectory: "Samples") ?? []
            found += bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        return found
    }

    private static func catalogEntries(bundle: Bundle) -> [SamplePhoto] {
        let candidates = [bundle.url(forResource: "samples", withExtension: "json", subdirectory: "Samples"),
                          bundle.url(forResource: "samples", withExtension: "json")]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let photos = object["photos"] as? [[String: Any]] else { continue }
            return photos.compactMap { entry in
                guard let file = entry["file"] as? String else { return nil }
                return SamplePhoto(
                    file: file,
                    title: (entry["title"] as? String) ?? (file as NSString).deletingPathExtension,
                    credit: (entry["credit"] as? String) ?? ""
                )
            }
        }
        return []
    }

    /// The samples that are really in the bundle, in the order of samples.json, then any extra files sorted by name.
    static func photos(bundle: Bundle = .main) -> [SamplePhoto] {
        let files = urls(bundle: bundle)
        let present = Set(files.map { $0.deletingPathExtension().lastPathComponent })
        let listed = catalogEntries(bundle: bundle).filter { present.contains($0.name) }
        let listedNames = Set(listed.map { $0.name })
        let extra = present.subtracting(listedNames).sorted().map { SamplePhoto(file: $0, title: $0.replacingOccurrences(of: "-", with: " ").capitalized, credit: "") }
        return listed + extra
    }

    /// Decodes a bundled sample upright, at most `maxPixel` on the long side.
    static func image(named name: String, maxPixel: Int = 2400, bundle: Bundle = .main) -> UIImage? {
        guard let url = urls(bundle: bundle).first(where: { $0.deletingPathExtension().lastPathComponent == name }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// One credit line per sample, for the Settings credits section.
    static func credits(bundle: Bundle = .main) -> [String] {
        photos(bundle: bundle).compactMap { $0.credit.isEmpty ? nil : "\($0.title): \($0.credit)" }
    }
}
