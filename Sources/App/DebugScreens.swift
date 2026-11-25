#if DEBUG
import SwiftUI
import UIKit

/// Debug builds can open an editor screen directly, on a bundled sample photo, so CI can take screenshots without tapping
/// through the app: `xcrun simctl launch <device> com.ecomswift.lustra -lsScreen editor-ombre`.
/// None of this exists in Release builds. The real hair detection runs, so a screenshot shows the real result.
enum DebugScreens {
    static var requested: String? {
        guard let value = UserDefaults.standard.string(forKey: "lsScreen"), !value.isEmpty else { return nil }
        return value
    }

    /// The screens this file draws. Everything else (home, onboarding, settings, export) belongs to other files.
    static let editorNames: [String] = [
        "editor-colour", "editor-ombre", "editor-balayage", "editor-highlights", "editor-finish",
        "editor-refine", "compare-grid", "before-after", "looks", "hints",
    ]

    static func handles(_ name: String) -> Bool {
        name.hasPrefix("shot-") || name == "editor" || editorNames.contains(name)
    }

    @MainActor @ViewBuilder
    static func view(for screen: String) -> some View {
        if screen.hasPrefix("shot-") {
            StoreScreens.view(for: String(screen.dropFirst("shot-".count)))
        } else {
            DebugEditorHost(spec: DebugEditorSpec.named(screen))
        }
    }
}

/// What a debug or store screen shows: which tool is open, which look is applied, which photo is used.
struct DebugEditorSpec {
    var tool: EditorTool = .colour
    var primary: String = "Copper"
    var secondary: String? = nil
    var style: HairStyleKind = .solid
    var split = false
    var hints: [PhotoHint]? = nil
    var samplePreference = 0
    var savedLooks = false
    var hideHints = false
    var showExport = false
    var tune: (inout HairLook) -> Void = { _ in }

    static func named(_ screen: String) -> DebugEditorSpec {
        var s = DebugEditorSpec()
        switch screen {
        case "editor-ombre":
            s.tool = .style
            s.style = .ombre
            s.primary = "Chestnut"
            s.secondary = "Honey"
        case "editor-balayage":
            s.tool = .style
            s.style = .balayage
            s.primary = "Dark brown"
            s.secondary = "Golden blonde"
        case "editor-highlights":
            s.tool = .style
            s.style = .highlights
            s.primary = "Chestnut"
            s.secondary = "Champagne"
        case "editor-finish":
            s.tool = .finish
            s.primary = "Rose gold"
            s.tune = { look in
                look.shine = 0.6
                look.smooth = 0.3
                look.definition = 0.25
            }
        case "editor-refine":
            s.tool = .refine
        case "compare-grid":
            s.tool = .compare
        case "before-after":
            s.split = true
            s.primary = "Lavender"
        case "looks":
            s.tool = .looks
            s.savedLooks = true
        case "hints":
            s.hints = [.blurry, .multipleFaces(2)]
        default:
            break
        }
        return s
    }
}

/// Opens a sample photo with the real hair service, then shows the editor (or an error when detection is unavailable).
struct DebugEditorHost: View {
    let spec: DebugEditorSpec

    enum Phase {
        case loading
        case editor(EditorModel)
        case export(ExportPayload)
        case failed(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                VStack(spacing: LS.Space.m) {
                    ProgressView().tint(LS.Palette.accent)
                    Text("Finding the hair in your photo").font(LS.Font.callout).foregroundStyle(LS.Palette.mist)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .editor(let model):
                EditorView(model: model, onClose: {})
            case .export(let payload):
                ExportView(payload: payload)
            case .failed(let message):
                VStack(spacing: LS.Space.m) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(LS.Palette.danger)
                        .accessibilityHidden(true)
                    Text("Hair detection is unavailable").font(LS.Font.title(22)).foregroundStyle(LS.Palette.paper)
                        .multilineTextAlignment(.center)
                    Text(message).font(LS.Font.callout).foregroundStyle(LS.Palette.mist)
                        .multilineTextAlignment(.center)
                }
                .padding(LS.Space.l)
                .readableWidth(520)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("debug-error")
            }
        }
        .apScreen()
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        if case .loading = phase {} else { return }
        do {
            let session = try await DebugFixtures.openSession(preferred: spec.samplePreference)
            let model = DebugFixtures.makeModel(session: session, spec: spec)
            if spec.showExport {
                phase = .export(model.makeExportPayload())
            } else {
                phase = .editor(model)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Sample photos and models for development screenshots only.
enum DebugFixtures {
    /// Opens the first bundled sample (from `preferred`, wrapping around) in which hair is found. Without samples a drawn portrait is used.
    @MainActor
    static func openSession(preferred: Int) async throws -> HairSession {
        let photos = SampleLibrary.photos()
        if photos.isEmpty {
            return try await HairService.shared.open(image: fallbackPortrait())
        }
        var firstSession: HairSession? = nil
        var lastError: Error? = nil
        var index = max(0, preferred)
        let attempts = min(3, photos.count)
        for _ in 0..<attempts {
            let photo = photos[index % photos.count]
            index += 1
            guard let image = SampleLibrary.image(named: photo.name, maxPixel: 2400) else { continue }
            do {
                let session = try await HairService.shared.open(image: image)
                if firstSession == nil { firstSession = session }
                if session.analysis.hairCoverage > 0.02 { return session }
            } catch {
                lastError = error
                break
            }
        }
        if let s = firstSession { return s }
        throw lastError ?? HairEngineError.imageUnreadable
    }

    @MainActor
    static func makeModel(session: HairSession, spec: DebugEditorSpec) -> EditorModel {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lustra-debug-looks-\(UUID().uuidString).json")
        let store = LooksStore(url: file)
        var look = EditorModel.defaultLook
        if let shade = HairPalette.shade(named: spec.primary) { look.primary = shade.color }
        if let name = spec.secondary, let shade = HairPalette.shade(named: name) { look.secondary = shade.color }
        look.style = spec.style
        spec.tune(&look)
        if spec.savedLooks {
            var copper = EditorModel.defaultLook
            copper.style = .solid
            store.add(copper, name: "Copper")
            var rose = EditorModel.defaultLook
            if let s = HairPalette.shade(named: "Rose gold") { rose.primary = s.color }
            if let s = HairPalette.shade(named: "Blush pink") { rose.secondary = s.color }
            rose.style = .ombre
            store.add(rose, name: "Rose gold ombre")
            var ash = EditorModel.defaultLook
            if let s = HairPalette.shade(named: "Chestnut") { ash.primary = s.color }
            if let s = HairPalette.shade(named: "Ash blonde") { ash.secondary = s.color }
            ash.style = .balayage
            store.add(ash, name: "Ash balayage")
            store.add(look, name: "My look")
        }
        let model = EditorModel(session: session, looksStore: store, initialLook: look, initialTool: spec.tool)
        model.hideHints = spec.hideHints
        model.hintOverride = spec.hints
        model.splitMode = spec.split
        return model
    }

    /// A drawn head-and-hair picture, used only when the app has no sample photos yet.
    static func fallbackPortrait() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let wall = [UIColor(hex: 0x6E6A72).cgColor, UIColor(hex: 0x3A3740).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: wall, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Shoulders, hair behind the head, neck, face.
            UIColor(hex: 0x2B2F3A).setFill()
            cg.fillEllipse(in: CGRect(x: 90, y: 900, width: 720, height: 600))
            UIColor(hex: 0x3B2A20).setFill()
            cg.fillEllipse(in: CGRect(x: 190, y: 160, width: 520, height: 760))
            UIColor(hex: 0xD2A07F).setFill()
            cg.fill(CGRect(x: 380, y: 700, width: 140, height: 260))
            cg.fillEllipse(in: CGRect(x: 275, y: 300, width: 350, height: 470))
            UIColor(hex: 0x3B2A20).setFill()
            cg.fillEllipse(in: CGRect(x: 262, y: 250, width: 376, height: 190))
        }
    }
}
#endif
