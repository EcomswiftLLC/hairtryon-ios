import SwiftUI
import UIKit

// MARK: - Color

struct EditorColorPanel: View {
    @ObservedObject var model: EditorModel

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 52), spacing: 6)]

    var body: some View {
        EditorPanelScroll {
            HStack(alignment: .firstTextBaseline) {
                Text(model.primaryName)
                    .font(LS.Font.title(26))
                    .foregroundStyle(LS.Palette.paper)
                    .accessibilityIdentifier("color-name")
                Spacer(minLength: 8)
                if let shade = model.primaryShade {
                    Text(shade.family.rawValue).font(LS.Font.caption).foregroundStyle(LS.Palette.mist)
                }
            }
            ForEach(HairShade.Family.allCases) { family in
                EdSection(title: family.rawValue) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(HairPalette.shades(in: family)) { shade in
                            EdSwatch(name: shade.name, hex: shade.hex, selected: model.look.primary.hex == shade.hex) {
                                LSHaptics.tap()
                                model.applyShade(shade)
                            }
                        }
                    }
                }
            }
            ColorPicker(selection: customBinding, supportsOpacity: false) {
                Text("Custom color").font(LS.Font.body).foregroundStyle(LS.Palette.paper)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("custom-color")
            EdToggle(
                title: "Cover grays only",
                isOn: Binding<Bool>(get: { model.look.grayCoverOnly }, set: { on in model.setGrayCover(on) }),
                detail: "Only gray and white strands change. All other hair keeps its color.",
                identifier: "toggle-gray-cover"
            )
            EdDial(model: model, title: "Intensity", keyPath: \.intensity, identifier: "dial-intensity")
        }
    }

    private var customBinding: Binding<Color> {
        Binding<Color>(
            get: { EdColorBridge.color(model.look.primary) },
            set: { newColor in model.setPrimary(EdColorBridge.hairColor(newColor), coalesced: true) }
        )
    }
}

// MARK: - Style

struct EditorStylePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        EditorPanelScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LS.Space.s) {
                    ForEach(HairStyleKind.allCases) { kind in
                        LSChip(title: kind.title, selected: model.look.style == kind) {
                            LSHaptics.tap()
                            model.setStyle(kind)
                        }
                        .accessibilityIdentifier("style-" + kind.rawValue)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            EdNote(text: EditorStylePanel.explanation(for: model.look.style))
            if model.look.style.usesSecondary {
                secondaryColors
            }
            styleDials
            EdSection(title: "Roots") {
                EdDial(model: model, title: "Root shadow", keyPath: \.rootShadow, identifier: "dial-root-shadow")
                EdDial(model: model, title: "Root depth", keyPath: \.rootDepth, identifier: "dial-root-depth")
            }
        }
    }

    static func explanation(for kind: HairStyleKind) -> String {
        switch kind {
        case .solid: return "One color over all of the hair."
        case .ombre: return "Your color at the roots, fading into a second color towards the ends."
        case .balayage: return "Soft, painted streaks of a second color through the lengths."
        case .highlights: return "Fine streaks of a second color through the hair."
        case .twoTone: return "Two colors with a clear split between them."
        }
    }

    private var suggested: HairColor { HairPalette.suggestedSecondary(for: model.look.primary) }

    private var secondaryColors: some View {
        EdSection(title: "Second color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        EdSwatch(name: "Suggested", hex: suggested.hex, selected: model.look.secondary.hex == suggested.hex) {
                            LSHaptics.tap()
                            model.setSecondary(suggested)
                        }
                        Text("Suggested").font(LS.Font.caption).foregroundStyle(LS.Palette.mist)
                    }
                    ForEach(HairPalette.all) { shade in
                        EdSwatch(name: shade.name, hex: shade.hex, selected: model.look.secondary.hex == shade.hex) {
                            LSHaptics.tap()
                            model.setSecondary(shade.color)
                        }
                    }
                }
            }
            .scrollClipDisabled()
            ColorPicker(selection: secondaryBinding, supportsOpacity: false) {
                Text("Custom second color").font(LS.Font.body).foregroundStyle(LS.Palette.paper)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("custom-second-color")
        }
    }

    private var secondaryBinding: Binding<Color> {
        Binding<Color>(
            get: { EdColorBridge.color(model.look.secondary) },
            set: { newColor in model.setSecondary(EdColorBridge.hairColor(newColor), coalesced: true) }
        )
    }

    @ViewBuilder
    private var styleDials: some View {
        switch model.look.style {
        case .solid:
            EmptyView()
        case .ombre:
            EdDial(model: model, title: "Where it starts", keyPath: \.gradientStart, identifier: "dial-gradient-start")
            EdDial(model: model, title: "Softness", keyPath: \.gradientSoftness, identifier: "dial-gradient-softness")
        case .balayage:
            EdDial(model: model, title: "Where it starts", keyPath: \.gradientStart, identifier: "dial-gradient-start")
            EdDial(model: model, title: "Amount", keyPath: \.streakAmount, identifier: "dial-streak-amount")
        case .highlights:
            EdDial(model: model, title: "Amount", keyPath: \.streakAmount, identifier: "dial-streak-amount")
        case .twoTone:
            EdDial(model: model, title: "Split position", keyPath: \.splitPosition, identifier: "dial-split-position")
        }
    }
}

// MARK: - Finish

struct EditorFinishPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        EditorPanelScroll {
            EdDial(model: model, title: "Shine", keyPath: \.shine, identifier: "dial-shine")
            EdDial(model: model, title: "Brightness", keyPath: \.brightness, range: -1...1, identifier: "dial-brightness")
            EdDial(model: model, title: "Smooth", keyPath: \.smooth, identifier: "dial-smooth")
            EdDial(model: model, title: "Definition", keyPath: \.definition, identifier: "dial-definition")
            EdDial(model: model, title: "Edge softness", keyPath: \.edgeSoftness, identifier: "dial-edge-softness")
        }
    }
}

// MARK: - Refine

struct EditorRefinePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        EditorPanelScroll {
            if model.hairNotFound {
                EdNote(text: "No hair was found. Choose Add hair and paint over the hair in the photo.", color: LS.Palette.danger)
            }
            HStack(spacing: LS.Space.s) {
                LSChip(title: "Add hair", systemImage: "plus", selected: model.brushAdds) {
                    model.brushAdds = true
                }
                .accessibilityIdentifier("brush-add")
                LSChip(title: "Remove hair", systemImage: "minus", selected: !model.brushAdds) {
                    model.brushAdds = false
                }
                .accessibilityIdentifier("brush-remove")
            }
            EdPlainDial(title: "Brush size", value: $model.brushSize, defaultValue: 0.4, identifier: "dial-brush-size")
            EdPlainDial(title: "Hardness", value: $model.brushHardness, defaultValue: 0.5, identifier: "dial-brush-hardness")
            EdToggle(
                title: "Show hair area",
                isOn: $model.showHairArea,
                detail: "Tints what Lustra detected as hair.",
                identifier: "toggle-hair-area"
            )
            HStack(spacing: LS.Space.s) {
                EdButton(title: "Undo last stroke", symbol: "arrow.uturn.backward", identifier: "undo-stroke") {
                    model.removeLastStroke()
                }
                .disabled(model.strokes.isEmpty)
                .opacity(model.strokes.isEmpty ? 0.4 : 1)
                EdButton(title: "Reset refine", symbol: "arrow.counterclockwise", destructive: true, identifier: "reset-refine") {
                    model.resetRefine()
                }
                .disabled(model.strokes.isEmpty)
                .opacity(model.strokes.isEmpty ? 0.4 : 1)
            }
            EdNote(text: "Paint over hair that was missed, or remove color from skin and background. Pinch to zoom and drag with two fingers to move around.")
        }
    }
}

// MARK: - Compare

struct EditorComparePanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: LooksStore

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 76, maximum: 150), spacing: 10)]

    var body: some View {
        EditorPanelScroll {
            HStack(alignment: .center) {
                Text("Every shade on this photo")
                    .font(LS.Font.title(20))
                    .foregroundStyle(LS.Palette.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                EdButton(title: "Export grid", symbol: "square.and.arrow.up", prominent: true, identifier: "export-grid") {
                    model.beginComparisonExport()
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.paletteTiles) { tile in
                    EdTileView(
                        title: tile.title,
                        image: model.thumbs[tile.id],
                        selected: tile.look.primary == model.look.primary,
                        identifier: "tile-" + tile.title
                    ) {
                        LSHaptics.tap()
                        model.apply(tile: tile)
                    }
                }
            }
            if !model.savedTiles.isEmpty {
                EdSection(title: "Your saved looks") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(model.savedTiles) { tile in
                            EdTileView(
                                title: tile.title,
                                image: model.thumbs[tile.id],
                                selected: tile.look == model.look,
                                identifier: "tile-saved-" + tile.title
                            ) {
                                LSHaptics.tap()
                                model.apply(tile: tile)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { model.loadThumbnails(for: model.compareTiles) }
        .onChange(of: model.thumbRevision) { model.loadThumbnails(for: model.compareTiles) }
        .onChange(of: model.look) { model.loadThumbnails(for: model.compareTiles) }
        .onChange(of: store.saved) { model.loadThumbnails(for: model.compareTiles) }
    }
}

// MARK: - Looks

struct EditorLooksPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: LooksStore
    @State private var renaming: SavedLook?
    @State private var renameText: String = ""
    @State private var showRename = false

    var body: some View {
        let saved: Bool = store.contains(model.look)
        return EditorPanelScroll {
            if saved {
                saveButton(saved: true).buttonStyle(.apSecondaryWide)
            } else {
                saveButton(saved: false).buttonStyle(.apPrimaryWide)
            }

            if store.saved.isEmpty {
                EdNote(text: "No saved looks yet. Save a color you like and it will wait here, ready to try on any photo.")
            } else {
                VStack(spacing: 4) {
                    ForEach(store.saved) { entry in
                        row(entry)
                    }
                }
            }
        }
        .onAppear { model.loadThumbnails(for: model.savedTiles) }
        .onChange(of: store.saved) { model.loadThumbnails(for: model.savedTiles) }
        .onChange(of: model.thumbRevision) { model.loadThumbnails(for: model.savedTiles) }
        .alert("Rename look", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let target = renaming { store.rename(target.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func saveButton(saved: Bool) -> some View {
        Button {
            let nowSaved = model.toggleSavedLook()
            LSHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: nowSaved ? "Look saved" : "Look removed")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "heart.fill" : "heart").accessibilityHidden(true)
                Text(saved ? "Saved to your looks" : "Save this look")
            }
        }
        .accessibilityIdentifier("save-look")
    }

    private func subtitle(_ look: HairLook) -> String {
        if look.style == .solid { return "Solid color" }
        return look.style.title + " with " + HairPalette.nearestName(to: look.secondary)
    }

    private func row(_ entry: SavedLook) -> some View {
        let tileID = "saved-" + entry.id.uuidString
        let isCurrent: Bool = entry.look == model.look
        return HStack(spacing: 10) {
            Button {
                LSHaptics.tap()
                model.commitLook(entry.look)
            } label: {
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 52, height: 65)
                        .overlay {
                            if let image = model.thumbs[tileID] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                EdShimmer()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isCurrent ? LS.Palette.accent : LS.Palette.line, lineWidth: isCurrent ? 2.5 : 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(LS.Font.body).foregroundStyle(LS.Palette.paper).lineLimit(1)
                        Text(subtitle(entry.look)).font(LS.Font.caption).foregroundStyle(LS.Palette.mist).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 65)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(entry.name + ", " + subtitle(entry.look)))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityIdentifier("saved-look-" + entry.name)
            Menu {
                Button {
                    renaming = entry
                    renameText = entry.name
                    showRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    store.remove(entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(LS.Palette.paper)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("More for " + entry.name))
        }
    }
}
