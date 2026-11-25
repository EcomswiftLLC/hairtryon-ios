import SwiftUI
import UIKit

// Small building blocks shared by the editor panels.

/// A titled group inside a panel.
struct EdSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            Text(title)
                .font(LS.Font.label)
                .foregroundStyle(LS.Palette.mist)
                .accessibilityAddTraits(.isHeader)
            content()
            if let detail {
                Text(detail)
                    .font(LS.Font.caption)
                    .foregroundStyle(LS.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The scrolling body of every tool panel.
struct EditorPanelScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LS.Space.m) { content() }
                .padding(.horizontal, LS.Space.m)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("panel-scroll")
    }
}

/// One round colour swatch with a 44 pt colour disc inside a 52 pt target. The selected one gets a ring and a check mark,
/// so the choice never depends on colour alone.
struct EdSwatch: View {
    let name: String
    let hex: UInt32
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(hex: hex)).padding(4)
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1).padding(4)
                if selected {
                    Circle().strokeBorder(LS.Palette.accent, lineWidth: 2.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(checkColor)
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("swatch-" + name)
    }

    private var checkColor: Color {
        ColorMath.luminance(hex: hex) > 0.4 ? Color.black.opacity(0.75) : Color.white
    }
}

/// A dial for one number of the look, shown as a percentage. One drag is one undo step.
struct EdDial: View {
    @ObservedObject var model: EditorModel
    let title: String
    let keyPath: WritableKeyPath<HairLook, Double>
    var range: ClosedRange<Double> = 0...1
    let identifier: String

    var body: some View {
        DialSlider(
            title: title,
            value: Binding<Double>(
                get: { model.look[keyPath: keyPath] * 100 },
                set: { newValue in model.setLive(keyPath, newValue / 100) }
            ),
            range: (range.lowerBound * 100)...(range.upperBound * 100),
            defaultValue: HairLook.`default`[keyPath: keyPath] * 100,
            unit: "%",
            decimals: 0,
            onEditingChanged: { editing in model.liveEditing(editing) }
        )
        .accessibilityIdentifier(identifier)
    }
}

/// A dial for a plain 0...1 setting of the editor (brush size, hardness) that is not part of the look.
struct EdPlainDial: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let identifier: String

    var body: some View {
        DialSlider(
            title: title,
            value: Binding<Double>(get: { value * 100 }, set: { newValue in value = newValue / 100 }),
            range: 0...100,
            defaultValue: defaultValue * 100,
            unit: "%",
            decimals: 0
        )
        .accessibilityIdentifier(identifier)
    }
}

/// An on/off row with a label and an optional explanation.
struct EdToggle: View {
    let title: String
    @Binding var isOn: Bool
    var detail: String? = nil
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) {
                Text(title).font(LS.Font.body).foregroundStyle(LS.Palette.paper)
            }
            .toggleStyle(SwitchToggleStyle(tint: LS.Palette.accent))
            .frame(minHeight: 44)
            .accessibilityIdentifier(identifier)
            if let detail {
                Text(detail)
                    .font(LS.Font.caption)
                    .foregroundStyle(LS.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A compact capsule button for panel actions.
struct EdButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var destructive = false
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
                }
                Text(title).font(LS.Font.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(prominent ? LS.Palette.accent : LS.Palette.graphite, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : LS.Palette.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var foreground: Color {
        if prominent { return LS.Palette.onAccent }
        return destructive ? LS.Palette.danger : LS.Palette.paper
    }
}

/// An explanation or empty state inside a panel.
struct EdNote: View {
    let text: String
    var color: Color = LS.Palette.mist

    var body: some View {
        Text(text)
            .font(LS.Font.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A grey placeholder with a light sweep, shown while a thumbnail renders. Still when Reduce Motion is on.
struct EdShimmer: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            LS.Palette.graphite
                .overlay(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.10), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                )
                .clipped()
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small floating badge with a spinner, shown over the photo while something takes a moment.
struct EdBusyBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(LS.Palette.accent)
            Text(text).font(LS.Font.callout).foregroundStyle(LS.Palette.paper)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .lsGlass(radius: 22, tint: 0.88)
        .accessibilityElement(children: .combine)
    }
}

/// A tile of the compare grid or the saved looks: a 4:5 thumbnail of this photo and a name.
struct EdTileView: View {
    let title: String
    let image: UIImage?
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(EditorTileCrop.aspect, contentMode: .fit)
                    .overlay {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            EdShimmer()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? LS.Palette.accent : LS.Palette.line, lineWidth: selected ? 2.5 : 1)
                    )
                Text(title)
                    .font(LS.Font.caption)
                    .foregroundStyle(selected ? LS.Palette.paper : LS.Palette.mist)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Converts between the app's hex colours and the SwiftUI colour picker.
enum EdColorBridge {
    static func color(_ c: HairColor) -> Color { Color(hex: c.hex) }

    static func hairColor(_ color: Color) -> HairColor {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, (r * 255).rounded())))
        let gi = UInt32(max(0, min(255, (g * 255).rounded())))
        let bi = UInt32(max(0, min(255, (b * 255).rounded())))
        return HairColor(hex: (ri << 16) | (gi << 8) | bi)
    }
}

/// The tool bar: a row under the panel, or a column beside the photo in short landscape.
struct EditorToolBar: View {
    @Binding var tool: EditorTool
    let axis: Axis

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 2) { items }
                    .padding(.horizontal, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) { items }.padding(.vertical, 4)
                }
                .frame(width: 70)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var items: some View {
        ForEach(EditorTool.allCases) { t in
            toolButton(t)
        }
    }

    private func toolButton(_ t: EditorTool) -> some View {
        let on: Bool = t == tool
        let wide: CGFloat? = axis == .horizontal ? CGFloat.infinity : nil
        return Button {
            LSHaptics.tap()
            tool = t
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.symbol)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 26)
                Text(t.title).font(LS.Font.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? LS.Palette.accent : LS.Palette.mist)
            .frame(maxWidth: wide, minHeight: 52)
            .frame(width: axis == .vertical ? 62 : nil)
            .background(on ? LS.Palette.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t.title))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("tool-" + t.rawValue)
    }
}
