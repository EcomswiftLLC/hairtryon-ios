#if DEBUG
import SwiftUI

/// Debug-only direct entry to the screens that are not part of the editor: home, welcome, settings, licences and export.
/// `xcrun simctl launch <device> com.ecomswift.lustra -lsScreen settings`.
enum DebugAppScreens {
    static let names: Set<String> = ["home", "home-filled", "onboarding", "settings", "licences", "export"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    @MainActor @ViewBuilder
    static func view(for name: String) -> some View {
        switch name {
        case "onboarding":
            OnboardingView().environmentObject(AppState())
        case "settings":
            SettingsView()
        case "licences":
            NavigationStack { LicensesView() }.preferredColorScheme(.dark)
        case "home-filled":
            HomeView(debugFilled: true)
        case "export":
            var spec = DebugEditorSpec()
            let _ = { spec.showExport = true; spec.primary = "Rose gold"; spec.hideHints = true }()
            DebugEditorHost(spec: spec)
        default:
            HomeView()
        }
    }
}
#endif
