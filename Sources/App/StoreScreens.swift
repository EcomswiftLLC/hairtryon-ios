#if DEBUG
import SwiftUI
import UIKit

/// Store captures: the real editor and export screens on the bundled sample photos, in a state that looks like finished work,
/// with no hints banner. `-lsScreen shot-<name>` opens one. Nothing here draws UI of its own: each capture is the real view
/// and every picture is rendered by the real engine. DEBUG builds only.
enum StoreScreens {
    /// Names of the store captures, in slide order. CI saves each one under exactly this name.
    static let names: [String] = [
        "home-filled", "editor-colour", "editor-ombre", "editor-balayage", "editor-highlights",
        "compare-grid", "refine", "before-after", "looks", "export",
    ]

    /// TODO(main session): set this to `{ AnyView(HomeView(debugFilled: true)) }` once HomeView has a filled debug state,
    /// for example in LustraApp.init under `#if DEBUG`. Until then the capture shows a note instead of breaking the build.
    @MainActor static var homeFilledProvider: (() -> AnyView)? = nil

    @MainActor @ViewBuilder
    static func view(for name: String) -> some View {
        if name == "home-filled" {
            if let provider = homeFilledProvider {
                provider()
            } else {
                Text("Home capture is not connected yet")
                    .font(LS.Font.callout)
                    .foregroundStyle(LS.Palette.mist)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .apScreen()
            }
        } else {
            DebugEditorHost(spec: spec(for: name))
        }
    }

    static func spec(for name: String) -> DebugEditorSpec {
        var s = DebugEditorSpec()
        s.hideHints = true
        switch name {
        case "editor-colour":
            s.tool = .colour
            s.primary = "Copper"
            s.samplePreference = 0
        case "editor-ombre":
            s.tool = .style
            s.style = .ombre
            s.primary = "Espresso"
            s.secondary = "Honey"
            s.samplePreference = 1
        case "editor-balayage":
            s.tool = .style
            s.style = .balayage
            s.primary = "Chestnut"
            s.secondary = "Golden blonde"
            s.samplePreference = 2
        case "editor-highlights":
            s.tool = .style
            s.style = .highlights
            s.primary = "Dark brown"
            s.secondary = "Champagne"
            s.samplePreference = 3
        case "compare-grid":
            s.tool = .compare
            s.samplePreference = 0
        case "refine":
            s.tool = .refine
            s.samplePreference = 1
        case "before-after":
            s.split = true
            s.primary = "Lavender"
            s.samplePreference = 2
        case "looks":
            s.tool = .looks
            s.savedLooks = true
            s.samplePreference = 0
        case "export":
            s.showExport = true
            s.primary = "Rose gold"
            s.samplePreference = 2
        default:
            break
        }
        return s
    }
}
#endif
