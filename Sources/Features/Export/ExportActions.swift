import Foundation
import UIKit
import Photos

enum ExportError: LocalizedError {
    case photosDenied
    case encodeFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .photosDenied: return "Lustra needs permission to add photos. You can allow it in Settings."
        case .encodeFailed: return "The photo could not be prepared for saving."
        case .saveFailed(let m): return "The photo could not be saved. \(m)"
        }
    }
}

/// Saving and sharing a finished image. Each function reports success only when the system confirms it.
enum ExportActions {
    static func jpegData(_ image: UIImage, quality: CGFloat = 0.95) throws -> Data {
        guard let data = image.jpegData(compressionQuality: quality) else { throw ExportError.encodeFailed }
        return data
    }

    /// Writes the image to a temporary JPEG file with a readable name and returns its URL.
    static func temporaryFile(for image: UIImage, title: String) throws -> URL {
        let data = try jpegData(image)
        let safe = title.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -")).inverted).joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        let name = "Lustra-" + (safe.isEmpty ? "photo" : safe) + ".jpg"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lustra-export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func clearTemporaryFiles() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lustra-export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Adds the photo to the library. Needs add-only access.
    static func saveToPhotos(_ image: UIImage) async throws {
        let data = try jpegData(image)
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw ExportError.photosDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw ExportError.saveFailed(error.localizedDescription)
        }
    }
}

/// Presents the Files "save to" sheet and reports whether the person saved.
@MainActor
final class FilesExporter: NSObject, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func export(fileURL: URL) async -> Bool {
        guard let presenter = AdsPresenter.topViewController() else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            continuation = c
            let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        continuation?.resume(returning: !urls.isEmpty)
        continuation = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation?.resume(returning: false)
        continuation = nil
    }
}

/// Presents the system share sheet and reports whether the person completed a share.
@MainActor
enum ShareSheet {
    static func present(fileURL: URL, sourceView: UIView? = nil) async -> Bool {
        guard let presenter = AdsPresenter.topViewController() else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            controller.completionWithItemsHandler = { _, completed, _, _ in
                c.resume(returning: completed)
            }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = sourceView ?? presenter.view
                let bounds = presenter.view.bounds
                popover.sourceRect = CGRect(x: bounds.midX, y: bounds.maxY - 80, width: 1, height: 1)
                popover.permittedArrowDirections = [.down, .up]
            }
            presenter.present(controller, animated: true)
        }
    }
}
