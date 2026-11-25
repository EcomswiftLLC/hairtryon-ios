import SwiftUI
import UIKit

enum EditorLayoutKind {
    /// Photo on top, panel and tool bar under it (portrait).
    case stacked
    /// Photo on the left, panel with its tool bar on the right (iPad landscape).
    case sidePanel
    /// Tool rail, photo, panel (iPhone landscape).
    case sideRail

    static func kind(for size: CGSize) -> EditorLayoutKind {
        if size.width <= size.height { return .stacked }
        return size.height < 560 ? .sideRail : .sidePanel
    }
}

/// The editor: the photo, the undo and save bar, and the tool panels.
struct EditorView: View {
    @StateObject private var model: EditorModel
    let onClose: () -> Void

    init(session: HairSession, initialLook: HairLook? = nil, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: EditorModel(session: session, initialLook: initialLook))
        self.onClose = onClose
    }

    /// For debug screens and tests that build the model themselves.
    init(model: EditorModel, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geo in
            let kind = EditorLayoutKind.kind(for: geo.size)
            VStack(spacing: 0) {
                EditorTopBar(model: model, onClose: onClose)
                switch kind {
                case .stacked:
                    stacked(height: geo.size.height)
                case .sidePanel:
                    sidePanel(width: geo.size.width)
                case .sideRail:
                    sideRail(width: geo.size.width)
                }
            }
        }
        .apScreen()
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $model.exportPayload) { payload in
            ExportView(payload: payload)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding<Bool>(
                get: { model.errorMessage != nil },
                set: { shown in if !shown { model.errorMessage = nil } }
            ),
            actions: { Button("OK") {} },
            message: { Text(model.errorMessage ?? "") }
        )
    }

    private func stacked(height: CGFloat) -> some View {
        let panelHeight: CGFloat = min(max(height * 0.40, 300), 460)
        return VStack(spacing: 8) {
            EditorCanvas(model: model)
            VStack(spacing: 0) {
                EditorPanelHost(model: model)
                LSHairline()
                EditorToolBar(tool: $model.tool, axis: .horizontal)
            }
            .frame(height: panelHeight)
            .lsGlass()
            .clipShape(RoundedRectangle(cornerRadius: LS.Radius.panel, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    private func sidePanel(width: CGFloat) -> some View {
        let panelWidth: CGFloat = min(440, max(360, width * 0.34))
        return HStack(spacing: 8) {
            EditorCanvas(model: model)
            VStack(spacing: 0) {
                EditorToolBar(tool: $model.tool, axis: .horizontal)
                LSHairline()
                EditorPanelHost(model: model)
            }
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .lsGlass()
            .clipShape(RoundedRectangle(cornerRadius: LS.Radius.panel, style: .continuous))
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
    }

    private func sideRail(width: CGFloat) -> some View {
        let panelWidth: CGFloat = min(340, max(280, width * 0.36))
        return HStack(spacing: 6) {
            EditorToolBar(tool: $model.tool, axis: .vertical)
            EditorCanvas(model: model)
            EditorPanelHost(model: model)
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .lsGlass()
                .clipShape(RoundedRectangle(cornerRadius: LS.Radius.panel, style: .continuous))
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
    }
}

/// Shows the panel of the selected tool.
struct EditorPanelHost: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        switch model.tool {
        case .colour: EditorColorPanel(model: model)
        case .style: EditorStylePanel(model: model)
        case .finish: EditorFinishPanel(model: model)
        case .refine: EditorRefinePanel(model: model)
        case .compare: EditorComparePanel(model: model, store: model.looksStore)
        case .looks: EditorLooksPanel(model: model, store: model.looksStore)
        }
    }
}

/// Close, undo, redo and Save.
struct EditorTopBar: View {
    @ObservedObject var model: EditorModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            LSIconButton(symbol: "xmark", label: "Close editor", action: onClose)
                .accessibilityIdentifier("close-editor")
            Spacer(minLength: 8)
            LSIconButton(symbol: "arrow.uturn.backward", label: "Undo", disabled: !model.canUndo) { model.undo() }
                .accessibilityIdentifier("undo")
            LSIconButton(symbol: "arrow.uturn.forward", label: "Redo", disabled: !model.canRedo) { model.redo() }
                .accessibilityIdentifier("redo")
            Button {
                model.beginExport()
            } label: {
                Text("Save")
            }
            .buttonStyle(.apPrimary)
            .accessibilityHint(Text("Opens save and share options"))
            .accessibilityIdentifier("save-export")
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }
}
