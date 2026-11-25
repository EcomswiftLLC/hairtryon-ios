import Foundation
import SwiftUI

/// The looks a person saved. Stored as JSON in Application Support, on the device only.
@MainActor
final class LooksStore: ObservableObject {
    static let shared = LooksStore()

    @Published private(set) var saved: [SavedLook] = []
    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.url = base.appendingPathComponent("saved-looks.json")
        }
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let looks = try? JSONDecoder().decode([SavedLook].self, from: data) else { return }
        saved = looks
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Saves a look. A look with the same settings is replaced, not duplicated.
    @discardableResult
    func add(_ look: HairLook, name: String? = nil) -> SavedLook {
        if let existing = saved.first(where: { $0.look == look }) { return existing }
        let entry = SavedLook(name: name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? LooksStore.defaultName(for: look), look: look)
        saved.insert(entry, at: 0)
        persist()
        return entry
    }

    func remove(_ id: UUID) {
        saved.removeAll { $0.id == id }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[i].name = name.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? saved[i].name
        persist()
    }

    func contains(_ look: HairLook) -> Bool { saved.contains { $0.look == look } }

    func entry(for look: HairLook) -> SavedLook? { saved.first { $0.look == look } }

    static func defaultName(for look: HairLook) -> String {
        let colour = HairPalette.nearestName(to: look.primary)
        switch look.style {
        case .solid: return colour
        case .twoTone: return "\(colour) two-tone"
        default: return "\(colour) \(look.style.title.lowercased())"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
