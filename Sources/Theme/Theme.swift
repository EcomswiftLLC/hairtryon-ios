import SwiftUI
import UIKit

/// Lustra design tokens. The app is dark only: a neutral, unlit surface is what lets a photo be judged honestly,
/// and accent (the colour of a lens barrel engraving) is the single accent.
enum LS {
    enum Palette {
        /// App background. Neutral, no colour cast.
        static let lens     = Color(hex: 0x0C0A0F)
        /// First surface above the background.
        static let carbon   = Color(hex: 0x151219)
        /// Raised surface (panels, rows when pressed).
        static let graphite = Color(hex: 0x201B26)
        /// Hairline rules and outlines.
        static let line     = Color.white.opacity(0.10)
        /// Primary text.
        static let paper    = Color(hex: 0xF3EEE8)
        /// Secondary text. 7:1 on `lens`.
        static let mist     = Color(hex: 0xAFA8B3)
        /// The accent.
        static let accent    = Color(hex: 0xEDB7A2)
        static let accentDeep = Color(hex: 0xC98672)
        /// Text and icons on top of accent.
        static let onAccent  = Color(hex: 0x24120D)
        static let danger   = Color(hex: 0xE88C80)
        static let success  = Color(hex: 0x8FC7A4)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let control: CGFloat = 14
        static let panel: CGFloat = 22
    }

    enum Font {
        /// Large editorial headline (New York). Tight tracking is applied by `.apDisplay`.
        /// Serif sizes follow the person's text size setting (up to 1.6 times, so a headline never outgrows the screen).
        private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
            min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * 1.6)
        }
        static func display(_ size: CGFloat = 38) -> SwiftUI.Font {
            .system(size: scaled(size, .largeTitle), weight: .regular, design: .serif)
        }
        static func title(_ size: CGFloat = 24) -> SwiftUI.Font {
            .system(size: scaled(size, .title2), weight: .medium, design: .serif)
        }
        static let headline = SwiftUI.Font.system(.headline, design: .default).weight(.semibold)
        static let body = SwiftUI.Font.system(.body, design: .default)
        static let callout = SwiftUI.Font.system(.callout, design: .default)
        static let label = SwiftUI.Font.system(.footnote, design: .default).weight(.medium)
        static let caption = SwiftUI.Font.system(.caption, design: .default)
        static let number = SwiftUI.Font.system(.callout, design: .rounded).monospacedDigit().weight(.medium)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// Full-screen background in the app's base colour.
    func apScreen() -> some View {
        background(LS.Palette.lens.ignoresSafeArea())
    }

    /// Editorial headline treatment.
    func apDisplay(_ size: CGFloat = 38) -> some View {
        font(LS.Font.display(size)).tracking(-0.6).foregroundStyle(LS.Palette.paper)
    }
}

/// Appearance for system bars, set once at launch.
enum LSAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(hex: 0xF3EEE8)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(hex: 0xF3EEE8)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(hex: 0xEDB7A2)
    }
}
