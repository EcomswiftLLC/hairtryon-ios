import SwiftUI
import PhotosUI
import UIKit

/// The editor that is currently open.
struct ActiveEditor: Identifiable {
    let id = UUID()
    let session: HairSession
    let initialLook: HairLook?
}

struct HomeView: View {
    /// Debug builds can ask for a Home screen already filled with samples and saved looks (store screenshots).
    var debugFilled: Bool = false

    @ObservedObject private var looks: LooksStore
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var pickerItem: PhotosPickerItem?
    @State private var editor: ActiveEditor?
    @State private var opening = false
    @State private var errorText: String?
    @State private var settingsShown = false
    @State private var cameraShown = false
    @State private var pendingLook: HairLook?
    @State private var pickerShown = false
    @State private var samples: [SamplePhoto] = []

    init(debugFilled: Bool = false) {
        self.debugFilled = debugFilled
        #if DEBUG
        if debugFilled {
            _looks = ObservedObject(wrappedValue: HomeView.seededDebugStore())
            return
        }
        #endif
        _looks = ObservedObject(wrappedValue: LooksStore.shared)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LS.Space.xl) {
                    topBar
                    headline
                    actions
                    if !looks.saved.isEmpty { savedLooks }
                    if !samples.isEmpty { samplesSection }
                    featureList
                    CKInlineBanner()
                }
                .padding(.horizontal, LS.Space.m)
                .padding(.bottom, LS.Space.xl)
                .readableWidth(hSize == .regular ? 820 : 900)
            }
            .scrollIndicators(.hidden)
            if opening { openingOverlay }
        }
        .apScreen()
        .photosPicker(isPresented: $pickerShown, selection: $pickerItem, matching: .images, photoLibrary: .shared())
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(item: $editor) { active in
            EditorView(session: active.session, initialLook: active.initialLook) { editor = nil }
        }
        .fullScreenCover(isPresented: $cameraShown) {
            CameraPicker(
                onImage: { image in
                    cameraShown = false
                    start(with: image, look: pendingLook)
                },
                onCancel: { cameraShown = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $settingsShown) { SettingsView() }
        .alert("We could not open this photo", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .task { samples = SampleLibrary.photos() }
    }

    #if DEBUG
    /// A throwaway store with a few saved looks, so the store screenshot of Home shows what it looks like in use.
    private static func seededDebugStore() -> LooksStore {
        let store = LooksStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("lustra-home-debug-\(UUID().uuidString).json"))
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
        return store
    }
    #endif

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            LustraMark(lineWidth: 2)
                .frame(width: 26, height: 26)
            Text("Lustra")
                .font(LS.Font.title(21))
                .foregroundStyle(LS.Palette.paper)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { settingsShown = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(LS.Palette.paper)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Settings"))
            .accessibilityIdentifier("home.settings")
        }
        .padding(.top, LS.Space.s)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            Text("Try a new hair colour.")
                .apDisplay(38)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            Text("See dye, ombre, balayage and highlights on your own photo before you commit. Your photo never leaves this device.")
                .font(LS.Font.body)
                .foregroundStyle(LS.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: LS.Space.s) {
            Button {
                pendingLook = nil
                pickerShown = true
            } label: {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.apPrimaryWide)
            .accessibilityIdentifier("home.choose")

            if CameraPicker.isAvailable {
                Button {
                    pendingLook = nil
                    cameraShown = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                }
                .buttonStyle(.apSecondaryWide)
                .accessibilityIdentifier("home.camera")
            }
        }
    }

    private var savedLooks: some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            LSSectionTitle(text: "Your saved looks")
            Text("Choose a photo to try one of them.")
                .font(LS.Font.callout)
                .foregroundStyle(LS.Palette.mist)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LS.Space.s) {
                    ForEach(looks.saved) { saved in
                        Button {
                            pendingLook = saved.look
                            pickerShown = true
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: saved.look.primary.hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(LS.Palette.line, lineWidth: 1))
                                    .overlay(alignment: .trailing) {
                                        if saved.look.style.usesSecondary {
                                            Circle().fill(Color(hex: saved.look.secondary.hex)).frame(width: 14, height: 14)
                                                .overlay(Circle().strokeBorder(LS.Palette.line, lineWidth: 1))
                                                .offset(x: 8)
                                        }
                                    }
                                    .padding(.trailing, saved.look.style.usesSecondary ? 8 : 0)
                                Text(saved.name).font(LS.Font.label).foregroundStyle(LS.Palette.paper).lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(LS.Palette.graphite, in: Capsule())
                            .overlay(Capsule().strokeBorder(LS.Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Try \(saved.name) on a photo"))
                    }
                }
            }
        }
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: LS.Space.s) {
            LSSectionTitle(text: "No photo handy?")
            Text("Try Lustra on a sample photo.")
                .font(LS.Font.callout)
                .foregroundStyle(LS.Palette.mist)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: hSize == .regular ? 180 : 140), spacing: LS.Space.s)], spacing: LS.Space.s) {
                ForEach(samples) { sample in
                    Button {
                        pendingLook = nil
                        if let image = SampleLibrary.image(named: sample.name, maxPixel: HairSession.fullSide) {
                            start(with: image, look: nil)
                        } else {
                            errorText = "This sample could not be loaded."
                        }
                    } label: {
                        SampleTile(sample: sample)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Try \(sample.title)"))
                }
            }
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            LSSectionTitle(text: "What you can do")
                .padding(.bottom, LS.Space.s)
            LSHairline()
            feature("paintpalette", "30 shades and your own", "Natural, blonde, red and fashion colours, or pick any colour.")
            LSHairline()
            feature("wand.and.stars", "Ombre, balayage and highlights", "Blend two colours, add streaks, shadow the roots.")
            LSHairline()
            feature("square.grid.3x3", "Compare colours side by side", "See many colours on one photo and save the grid.")
            LSHairline()
            feature("hand.draw", "Refine the hair area", "Brush hair in or out until the edge is right.")
            LSHairline()
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: LS.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(LS.Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LS.Font.headline).foregroundStyle(LS.Palette.paper)
                Text(detail).font(LS.Font.callout).foregroundStyle(LS.Palette.mist).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var openingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: LS.Space.m) {
                ProgressView().tint(LS.Palette.accent).scaleEffect(1.3)
                Text("Finding the hair").font(LS.Font.headline).foregroundStyle(LS.Palette.paper)
                Text("This happens on your device.").font(LS.Font.callout).foregroundStyle(LS.Palette.mist)
            }
            .padding(LS.Space.l)
            .lsGlass()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.opening")
        }
        .transition(.opacity)
    }

    // MARK: Opening photos

    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        opening = true
        guard let data = try? await item.loadTransferable(type: Data.self), let image = PhotoDecoder.decode(data: data) else {
            opening = false
            errorText = "Lustra could not read this photo. Try another one."
            return
        }
        opening = false
        start(with: image, look: pendingLook)
    }

    private func start(with image: UIImage, look: HairLook?) {
        opening = true
        Task {
            do {
                let session = try await HairService.shared.open(image: image)
                opening = false
                editor = ActiveEditor(session: session, initialLook: look)
            } catch {
                opening = false
                errorText = error.localizedDescription
            }
        }
    }
}

private struct SampleTile: View {
    let sample: SamplePhoto
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
            } else {
                LS.Palette.graphite
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            Text(sample.title)
                .font(LS.Font.label)
                .foregroundStyle(LS.Palette.paper)
                .padding(10)
                .lineLimit(1)
        }
        .aspectRatio(0.8, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LS.Palette.line, lineWidth: 1))
        .task {
            let name = sample.name
            image = await Task.detached(priority: .utility) { SampleLibrary.image(named: name, maxPixel: 600) }.value
        }
    }
}
