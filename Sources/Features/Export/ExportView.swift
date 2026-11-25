import SwiftUI
import UIKit
import StoreKit

/// What the editor hands to the export screen.
struct ExportPayload: Identifiable {
    enum Kind { case single, comparison }

    let id = UUID()
    var kind: Kind = .single
    /// Shown on the export screen and used as the saved file name.
    var title: String
    /// The original photo (any size up to about 1600 px) for the before/after slider.
    var before: UIImage
    /// Renders the finished result at full quality. Called once, after the screen opens.
    var makeAfter: () async -> UIImage?
}

enum ExportKind: Equatable {
    case photos, files, share

    var successText: String {
        switch self {
        case .photos: return "Saved to Photos"
        case .files: return "Saved to Files"
        case .share: return "Shared"
        }
    }
}

/// State and actions of the export screen. Every save, file save and share goes through one rewarded ad (or none when no ad can load).
@MainActor
final class ExportModel: ObservableObject {
    enum Phase: Equatable {
        case rendering
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .rendering
    @Published private(set) var result: UIImage?
    @Published private(set) var exporting = false
    @Published private(set) var statusText: String?
    @Published private(set) var statusIsError = false
    @Published private(set) var showsSettingsButton = false

    let payload: ExportPayload
    private let tracker: ReviewTracker
    private let filesExporter = FilesExporter()
    private var shareSheetOnScreen = false
    private var visible = false
    private var reviewTask: Task<Void, Never>?
    /// Set by the view: asks the system to show Apple's review prompt.
    var requestReview: () -> Void = {}

    init(payload: ExportPayload, tracker: ReviewTracker = .shared) {
        self.payload = payload
        self.tracker = tracker
    }

    func appear() { visible = true }

    func disappear() {
        visible = false
        reviewTask?.cancel()
        ExportActions.clearTemporaryFiles()
    }

    func load() async {
        guard result == nil else { return }
        phase = .rendering
        if let image = await payload.makeAfter() {
            result = image
            phase = .ready
        } else {
            phase = .failed("The photo could not be rendered. Close this screen and try again.")
        }
    }

    // MARK: Actions

    /// The tap on Save to Photos / Save to Files / Share. The ad (if any) comes first, then the action runs.
    func start(_ kind: ExportKind) {
        guard let image = result, !exporting else { return }
        statusText = nil
        statusIsError = false
        showsSettingsButton = false
        RewardedGate.shared.requestExport { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.perform(kind, image: image) }
        }
    }

    private func perform(_ kind: ExportKind, image: UIImage) async {
        exporting = true
        defer {
            exporting = false
            RewardedGate.shared.exportEnded()
        }
        do {
            switch kind {
            case .photos:
                try await ExportActions.saveToPhotos(image)
                succeeded(kind)
            case .files:
                let url = try ExportActions.temporaryFile(for: image, title: payload.title)
                shareSheetOnScreen = true
                let ok = await filesExporter.export(fileURL: url)
                shareSheetOnScreen = false
                if ok { succeeded(kind) } else { statusText = nil }
            case .share:
                let url = try ExportActions.temporaryFile(for: image, title: payload.title)
                shareSheetOnScreen = true
                let ok = await ShareSheet.present(fileURL: url)
                shareSheetOnScreen = false
                if ok { succeeded(kind) } else { statusText = nil }
            }
        } catch let error as ExportError {
            statusText = error.errorDescription
            statusIsError = true
            showsSettingsButton = (error.errorDescription == ExportError.photosDenied.errorDescription)
            LSHaptics.warning()
        } catch {
            statusText = "Something went wrong. Please try again."
            statusIsError = true
            LSHaptics.warning()
        }
    }

    private func succeeded(_ kind: ExportKind) {
        statusText = kind.successText
        statusIsError = false
        LSHaptics.success()
        tracker.recordExportSuccess()
        considerReviewPrompt()
    }

    // MARK: Review prompt

    /// Asks Apple's review prompt only when the policy allows it. If only a recent ad stands in the way, waits for the
    /// quiet time to pass while the saved confirmation is still on screen.
    func considerReviewPrompt() {
        reviewTask?.cancel()
        reviewTask = Task { @MainActor [weak self] in
            // Let the confirmation be seen first.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            var attempts = 0
            while let self, !Task.isCancelled, attempts < 3 {
                attempts += 1
                guard self.visible else { return }
                let snapshot = self.tracker.snapshot(adOnScreen: RewardedGate.isAdOnScreen, shareSheetOnScreen: self.shareSheetOnScreen)
                switch ReviewPolicy.evaluate(snapshot, exportSucceeded: true) {
                case .request:
                    self.tracker.recordRequested(version: snapshot.currentVersion)
                    self.requestReview()
                    return
                case .blocked(let reason):
                    guard reason.clearsWithTime, case .adShownRecently(let left) = reason else { return }
                    try? await Task.sleep(nanoseconds: UInt64((left + 0.5) * 1_000_000_000))
                }
            }
        }
    }
}

/// The finished photo with before/after, and the three ways to keep it.
struct ExportView: View {
    let payload: ExportPayload
    @StateObject private var model: ExportModel
    @State private var split: Double = 0.06
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.horizontalSizeClass) private var hSize

    init(payload: ExportPayload) {
        self.payload = payload
        _model = StateObject(wrappedValue: ExportModel(payload: payload))
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width >= 700
            Group {
                if wide {
                    HStack(alignment: .center, spacing: LS.Space.xl) {
                        preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                        controls.frame(width: min(380, geo.size.width * 0.38))
                    }
                    .padding(LS.Space.l)
                } else {
                    ScrollView {
                        VStack(spacing: LS.Space.l) {
                            preview.frame(height: min(geo.size.height * 0.58, 640))
                            controls
                        }
                        .padding(.horizontal, LS.Space.m)
                        .padding(.bottom, LS.Space.l)
                        .readableWidth(620)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .apScreen()
        .preferredColorScheme(.dark)
        .task {
            model.requestReview = { requestReview() }
            model.appear()
            await model.load()
        }
        .onDisappear { model.disappear() }
    }

    // MARK: Pieces

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LS.Palette.paper)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LS.Palette.graphite.opacity(0.9)))
        }
        .accessibilityLabel(Text("Close"))
        .accessibilityIdentifier("export.close")
        .padding(LS.Space.m)
    }

    @ViewBuilder
    private var preview: some View {
        switch model.phase {
        case .rendering:
            VStack(spacing: LS.Space.m) {
                ProgressView().tint(LS.Palette.accent)
                Text("Preparing your photo").font(LS.Font.callout).foregroundStyle(LS.Palette.mist)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            Text(message)
                .font(LS.Font.body)
                .foregroundStyle(LS.Palette.danger)
                .multilineTextAlignment(.center)
                .padding(LS.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if let result = model.result {
                if payload.kind == .single {
                    BeforeAfterSlider(before: payload.before, after: result, position: $split)
                        .accessibilityIdentifier("export.beforeAfter")
                        .padding(.top, 56)
                } else {
                    Image(uiImage: result)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LS.Palette.line, lineWidth: 1))
                        .padding(.top, 56)
                        .accessibilityLabel(Text("Your color comparison"))
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: LS.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text(payload.kind == .single ? "Your new look" : "Your color comparison")
                    .apDisplay(30)
                    .accessibilityAddTraits(.isHeader)
                Text(payload.kind == .single
                     ? "Drag across the photo to compare with your original."
                     : "Every color on your photo, side by side.")
                    .font(LS.Font.callout)
                    .foregroundStyle(LS.Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: LS.Space.s) {
                Button { model.start(.photos) } label: {
                    exportLabel("Save to Photos", symbol: "square.and.arrow.down")
                }
                .buttonStyle(.apPrimaryWide)
                .disabled(!ready)
                .accessibilityIdentifier("export.save")

                HStack(spacing: LS.Space.s) {
                    Button { model.start(.files) } label: {
                        exportLabel("Files", symbol: "folder")
                    }
                    .buttonStyle(.apSecondaryWide)
                    .disabled(!ready)
                    .accessibilityIdentifier("export.files")

                    Button { model.start(.share) } label: {
                        exportLabel("Share", symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.apSecondaryWide)
                    .disabled(!ready)
                    .accessibilityIdentifier("export.share")
                }
            }

            if let status = model.statusText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: model.statusIsError ? "exclamationmark.triangle" : "checkmark.circle.fill")
                        .foregroundStyle(model.statusIsError ? LS.Palette.danger : LS.Palette.success)
                        .accessibilityHidden(true)
                    Text(status)
                        .font(LS.Font.callout)
                        .foregroundStyle(LS.Palette.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("export.status")
                if model.showsSettingsButton {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.apQuiet)
                }
            }

            Text("Lustra is free because of ads: saving or sharing asks you to watch one short ad. Your photo never leaves this device.")
                .font(LS.Font.caption)
                .foregroundStyle(LS.Palette.mist)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { dismiss() }
                .buttonStyle(.apQuiet)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("export.done")
        }
    }

    /// Same icon box for every button, so Files and Share (different symbol heights) end up the same height.
    private func exportLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22, height: 22)
            Text(title)
        }
    }

    private var ready: Bool { model.phase == .ready && !model.exporting }
}
