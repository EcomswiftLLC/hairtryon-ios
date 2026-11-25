import Foundation

/// A hair colour, stored as sRGB hex so it can be saved and shown anywhere.
struct HairColor: Codable, Equatable, Hashable {
    var hex: UInt32

    init(hex: UInt32) { self.hex = hex & 0xFFFFFF }

    var lab: (L: Float, a: Float, b: Float) { ColorMath.lab(hex: hex) }
    var chroma: Float { let l = lab; return (l.a * l.a + l.b * l.b).squareRoot() }
}

/// How the colour is laid over the hair.
enum HairStyleKind: String, Codable, CaseIterable, Identifiable {
    case solid, ombre, balayage, highlights, twoTone
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .ombre: return "Ombre"
        case .balayage: return "Balayage"
        case .highlights: return "Highlights"
        case .twoTone: return "Two-tone"
        }
    }

    /// True when the style needs a second colour.
    var usesSecondary: Bool { self != .solid }
}

/// Every setting that decides how the hair looks. Saved as a favourite, so it never contains the photo.
struct HairLook: Codable, Equatable {
    var primary: HairColor = HairColor(hex: 0x7A3B22)
    var secondary: HairColor = HairColor(hex: 0xDDB86A)
    var style: HairStyleKind = .solid

    /// 0...1, how strongly the new colour replaces the old one.
    var intensity: Double = 0.92
    /// 0...1, brightness of the specular streaks.
    var shine: Double = 0.35
    /// -1...1, lighter or darker than the chosen colour.
    var brightness: Double = 0
    /// 0...1, darker colour at the roots.
    var rootShadow: Double = 0
    /// 0...1, how far down the root shadow reaches.
    var rootDepth: Double = 0.22
    /// 0...1, where the second colour starts (ombre and balayage), measured from the top of the hair.
    var gradientStart: Double = 0.38
    /// 0...1, how long the blend between the two colours is (ombre).
    var gradientSoftness: Double = 0.45
    /// 0...1, share of the hair covered by highlight or balayage streaks.
    var streakAmount: Double = 0.5
    /// 0...1, where the split falls in a two-tone look (0.5 is the middle).
    var splitPosition: Double = 0.5
    /// When true only grey and white strands are coloured, everything else keeps its colour.
    var grayCoverOnly: Bool = false
    /// 0...1, softens flyaways and texture inside the hair.
    var smooth: Double = 0
    /// 0...1, brings out the strands.
    var definition: Double = 0
    /// 0...1, how soft the hair edge is (0 keeps the detected edge sharp).
    var edgeSoftness: Double = 0.4

    static let `default` = HairLook()

    /// A look is "untouched" when it would leave the photo as it is.
    var isNeutral: Bool { intensity <= 0.001 && smooth <= 0.001 && definition <= 0.001 }

    /// Clamped copy, used by the renderer so a bad saved value can never produce NaN pixels.
    func sanitized() -> HairLook {
        var l = self
        func c(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { v.isNaN ? lo : min(hi, max(lo, v)) }
        l.intensity = c(intensity)
        l.shine = c(shine)
        l.brightness = c(brightness, -1, 1)
        l.rootShadow = c(rootShadow)
        l.rootDepth = c(rootDepth)
        l.gradientStart = c(gradientStart)
        l.gradientSoftness = c(gradientSoftness)
        l.streakAmount = c(streakAmount)
        l.splitPosition = c(splitPosition)
        l.smooth = c(smooth)
        l.definition = c(definition)
        l.edgeSoftness = c(edgeSoftness)
        return l
    }
}

/// A look the person saved.
struct SavedLook: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var look: HairLook
    var created: Date = Date()
}

/// One named colour in the palette.
struct HairShade: Identifiable, Equatable, Hashable {
    enum Family: String, CaseIterable, Identifiable {
        case natural = "Natural"
        case blonde = "Blonde"
        case red = "Red & copper"
        case fashion = "Fashion"
        var id: String { rawValue }
    }

    var name: String
    var hex: UInt32
    var family: Family
    var id: String { name }
    var color: HairColor { HairColor(hex: hex) }
}

enum HairPalette {
    static let all: [HairShade] = [
        HairShade(name: "Jet black", hex: 0x0E0D10, family: .natural),
        HairShade(name: "Soft black", hex: 0x201815, family: .natural),
        HairShade(name: "Espresso", hex: 0x2E1C14, family: .natural),
        HairShade(name: "Dark brown", hex: 0x42291B, family: .natural),
        HairShade(name: "Chestnut", hex: 0x5E3A27, family: .natural),
        HairShade(name: "Light brown", hex: 0x86603F, family: .natural),
        HairShade(name: "Mushroom", hex: 0x6F6254, family: .natural),
        HairShade(name: "Silver", hex: 0xBFC2C7, family: .natural),

        HairShade(name: "Dark blonde", hex: 0xA9824A, family: .blonde),
        HairShade(name: "Honey", hex: 0xC9A05A, family: .blonde),
        HairShade(name: "Golden blonde", hex: 0xDDBA6E, family: .blonde),
        HairShade(name: "Ash blonde", hex: 0xC4B592, family: .blonde),
        HairShade(name: "Champagne", hex: 0xE3CFA6, family: .blonde),
        HairShade(name: "Platinum", hex: 0xEDE4D3, family: .blonde),

        HairShade(name: "Auburn", hex: 0x7B3622, family: .red),
        HairShade(name: "Copper", hex: 0xB3562B, family: .red),
        HairShade(name: "Ginger", hex: 0xCB6A2F, family: .red),
        HairShade(name: "Burgundy", hex: 0x5C1229, family: .red),
        HairShade(name: "Cherry", hex: 0x9E1B34, family: .red),
        HairShade(name: "Rose gold", hex: 0xD49A86, family: .red),

        HairShade(name: "Blush pink", hex: 0xE6A0B6, family: .fashion),
        HairShade(name: "Magenta", hex: 0xC2307F, family: .fashion),
        HairShade(name: "Lavender", hex: 0xAE92D8, family: .fashion),
        HairShade(name: "Violet", hex: 0x6C42C2, family: .fashion),
        HairShade(name: "Midnight blue", hex: 0x1D2A63, family: .fashion),
        HairShade(name: "Electric blue", hex: 0x2B79E0, family: .fashion),
        HairShade(name: "Teal", hex: 0x1D9A8E, family: .fashion),
        HairShade(name: "Emerald", hex: 0x1B7F52, family: .fashion),
        HairShade(name: "Mint", hex: 0x8EDDBA, family: .fashion),
        HairShade(name: "Sunset orange", hex: 0xEE7A33, family: .fashion),
    ]

    static func shades(in family: HairShade.Family) -> [HairShade] { all.filter { $0.family == family } }

    static func shade(named name: String) -> HairShade? { all.first { $0.name == name } }

    /// A readable name for the nearest palette colour, for accessibility labels.
    static func nearestName(to color: HairColor) -> String {
        let t = color.lab
        var best = (name: "Custom", d: Float.greatestFiniteMagnitude)
        for s in all {
            let l = s.color.lab
            let d = (l.L - t.L) * (l.L - t.L) + (l.a - t.a) * (l.a - t.a) + (l.b - t.b) * (l.b - t.b)
            if d < best.d { best = (s.name, d) }
        }
        return best.d < 140 ? best.name : "Custom"
    }

    /// A ready-made second colour that looks good next to the first (lighter and warmer for dark colours).
    static func suggestedSecondary(for primary: HairColor) -> HairColor {
        let l = primary.lab
        let newL = l.L < 50 ? min(88, l.L + 38) : max(14, l.L - 34)
        let hex = ColorMath.hex(L: newL, a: l.a * 0.9 + 4, b: l.b * 0.9 + 8)
        return HairColor(hex: hex)
    }

    /// Looks for the "compare" grid: a spread of colours across families.
    static let compareSelection: [String] = [
        "Jet black", "Espresso", "Chestnut", "Auburn", "Copper", "Honey",
        "Golden blonde", "Platinum", "Rose gold", "Blush pink", "Lavender", "Midnight blue",
        "Emerald", "Burgundy", "Silver", "Sunset orange",
    ]
}
