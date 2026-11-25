import SwiftUI

/// The Lustra mark: three flowing strands that catch the light, drawn in code so it stays sharp at any size.
struct LustraMark: View {
    var lineWidth: CGFloat = 2.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                strand(w: w, h: h, dx: -0.20, bend: 0.30, opacity: 0.55)
                strand(w: w, h: h, dx: 0.0, bend: -0.34, opacity: 1.0)
                strand(w: w, h: h, dx: 0.20, bend: 0.26, opacity: 0.75)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func strand(w: CGFloat, h: CGFloat, dx: CGFloat, bend: CGFloat, opacity: Double) -> some View {
        Path { p in
            let x0 = w * (0.5 + dx)
            p.move(to: CGPoint(x: x0, y: h * 0.06))
            p.addCurve(
                to: CGPoint(x: x0 + w * bend * 0.35, y: h * 0.94),
                control1: CGPoint(x: x0 + w * bend, y: h * 0.32),
                control2: CGPoint(x: x0 - w * bend, y: h * 0.68)
            )
        }
        .stroke(
            LinearGradient(colors: [LS.Palette.accent, LS.Palette.accentDeep], startPoint: .top, endPoint: .bottom),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .opacity(opacity)
    }
}
