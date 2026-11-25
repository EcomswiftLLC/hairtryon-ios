import SwiftUI

@main
struct LustraApp: App {
    @StateObject private var ads = AdsManager.shared

    init() {
        LSAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            Text("Lustra")
                .apDisplay()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .apScreen()
                .environmentObject(ads)
                .preferredColorScheme(.dark)
                .tint(LS.Palette.accent)
        }
    }
}
