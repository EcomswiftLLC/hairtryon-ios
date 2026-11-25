import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var heroImage: UIImage?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scrolls when the screen is short (iPhone in landscape, large text), so the copy is never cut off
        // and "Get started" is always reachable.
        GeometryReader { geo in
            let wide = geo.size.width >= 700 && geo.size.width > geo.size.height
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .center, spacing: LS.Space.xl) {
                            hero.frame(maxWidth: .infinity).frame(height: min(max(geo.size.height - 64, 220), 560))
                            copy.frame(maxWidth: 460)
                        }
                        .padding(.horizontal, LS.Space.xl)
                        .frame(minHeight: geo.size.height)
                    } else {
                        VStack(alignment: .leading, spacing: LS.Space.l) {
                            hero.frame(height: min(geo.size.height * 0.34, 320)).padding(.top, LS.Space.m)
                            copy
                        }
                        .padding(.horizontal, LS.Space.l)
                        .frame(minHeight: geo.size.height)
                        .readableWidth(560)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .apScreen()
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion { appeared = true } else { withAnimation(.easeOut(duration: 0.9)) { appeared = true } }
        }
        .task {
            heroImage = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let first = SampleLibrary.photos().first else { return nil }
                return SampleLibrary.image(named: first.name, maxPixel: 1400)
            }.value
        }
    }

    private var hero: some View {
        ZStack {
            if let heroImage {
                // The photo only fills the frame it is given; it never decides the width of the screen.
                Color.clear.overlay { Image(uiImage: heroImage).resizable().scaledToFill() }.clipped()
                LinearGradient(colors: [.clear, LS.Palette.lens.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            } else {
                LinearGradient(colors: [LS.Palette.graphite, LS.Palette.carbon], startPoint: .topLeading, endPoint: .bottomTrailing)
                LustraMark(lineWidth: 3).frame(width: 120, height: 120)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(LS.Palette.line, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome to Lustra.")
                .apDisplay(42)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Preview a new hair colour on your own photo. Nothing is uploaded.")
                .font(LS.Font.body)
                .foregroundStyle(LS.Palette.mist)
                .padding(.top, LS.Space.s)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                LSHairline()
                line("paintpalette", "Colour that looks real", "Light, shade and strands stay natural.")
                LSHairline()
                line("wand.and.stars", "Ombre, balayage, highlights", "Blend two colours or add streaks.")
                LSHairline()
                line("lock.shield", "Private by design", "Hair is found on your device. Photos never leave it.")
                LSHairline()
            }
            .padding(.top, LS.Space.l)
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { appState.hasOnboarded = true }
            } label: {
                Text("Get started")
            }
            .buttonStyle(.apPrimaryWide)
            .accessibilityIdentifier("onboarding.start")
            .padding(.top, LS.Space.l)
            .padding(.bottom, LS.Space.l)
        }
    }

    private func line(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: LS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(LS.Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LS.Font.headline).foregroundStyle(LS.Palette.paper)
                Text(detail).font(LS.Font.callout).foregroundStyle(LS.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
