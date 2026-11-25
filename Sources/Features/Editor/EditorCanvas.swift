import SwiftUI
import UIKit

/// The photo with the new hair colour. Pinch to zoom, drag to move when zoomed, double tap to zoom or reset.
/// Hold the compare button to see the original, or switch to the split view for a draggable divider.
struct EditorCanvas: View {
    @ObservedObject var model: EditorModel
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func fit(aspect: CGFloat, in size: CGSize, inset: CGFloat) -> CGRect {
        let availW = max(1, size.width - inset * 2)
        let availH = max(1, size.height - inset * 2)
        var w = availW
        var h = availW / max(0.01, aspect)
        if h > availH {
            h = availH
            w = availH * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private var brushMode: Bool { model.tool == .refine && !model.splitMode }
    private var showsMatte: Bool { model.tool == .refine && model.showHairArea }

    var body: some View {
        GeometryReader { geo in
            let rect: CGRect = EditorCanvas.fit(aspect: model.aspect, in: geo.size, inset: 6)
            ZStack(alignment: .topLeading) {
                if model.splitMode {
                    BeforeAfterSlider(
                        before: model.beforeImage,
                        after: model.renderedImage ?? model.beforeImage,
                        position: $model.splitFraction,
                        cornerRadius: 12
                    )
                    .padding(6)
                } else {
                    EditorGestureSurface(zoom: $zoom, offset: $offset, fitted: rect, brushMode: brushMode, onBrush: handleBrush)
                    zoomable(rect: rect)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .scaleEffect(zoom)
                        .offset(offset)
                }
                overlays
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(LS.Palette.lens)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onChange(of: model.splitMode) {
                if model.splitMode { resetZoom() }
            }
        }
        .padding(.horizontal, 8)
    }

    private func resetZoom() {
        if reduceMotion {
            zoom = 1
            offset = .zero
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                zoom = 1
                offset = .zero
            }
        }
    }

    private func handleBrush(_ phase: EditorBrushPhase, _ p: CGPoint) {
        switch phase {
        case .began: model.beginStroke(at: p)
        case .moved: model.extendStroke(to: p)
        case .ended: model.endStroke()
        case .cancelled: model.cancelStroke()
        }
    }

    // MARK: Zoomable content

    private func zoomable(rect: CGRect) -> some View {
        let shown: UIImage = model.showOriginal ? model.beforeImage : (model.renderedImage ?? model.beforeImage)
        return ZStack(alignment: .topLeading) {
            Image(uiImage: shown)
                .resizable()
                .interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
                .accessibilityLabel(Text(model.showOriginal ? "Original photo" : "Photo with new hair color: \(model.primaryName)"))
                .accessibilityIdentifier("canvas-photo")
            if showsMatte, !model.showOriginal, let overlay = model.matteOverlay {
                Image(uiImage: overlay)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            strokeLayer(rect: rect)
            faceLayer(rect: rect)
        }
    }

    private func strokeLayer(rect: CGRect) -> some View {
        let stroke: BrushStroke? = model.liveStroke
        return Canvas { context, size in
            guard let s = stroke, let first = s.points.first else { return }
            let colour: Color = s.addsHair ? Color(hex: 0x3DD6C6) : LS.Palette.danger
            let width: CGFloat = max(2, s.radius * max(size.width, size.height) * 2)
            if s.points.count == 1 {
                let c = CGPoint(x: first.x * size.width, y: first.y * size.height)
                let dot = Path(ellipseIn: CGRect(x: c.x - width / 2, y: c.y - width / 2, width: width, height: width))
                context.fill(dot, with: .color(colour.opacity(0.6)))
                return
            }
            var path = Path()
            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for p in s.points.dropFirst() {
                path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
            }
            context.stroke(path, with: .color(colour.opacity(0.6)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func faceLayer(rect: CGRect) -> some View {
        let faces: [FaceInfo] = model.analysis.faces
        if faces.count > 1 && !model.showOriginal {
            ForEach(faces) { face in
                faceButton(face: face, rect: rect)
            }
        }
    }

    private func faceButton(face: FaceInfo, rect: CGRect) -> some View {
        let fr = CGRect(
            x: rect.minX + face.rect.minX * rect.width,
            y: rect.minY + face.rect.minY * rect.height,
            width: face.rect.width * rect.width,
            height: face.rect.height * rect.height
        )
        let selected: Bool = model.analysis.selectedFace == face.id
        return Button {
            model.selectFace(face.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? LS.Palette.accent : Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: selected ? 3 : 1.5, dash: selected ? [] : [6, 4])
                    )
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LS.Palette.onAccent, LS.Palette.accent)
                        .padding(4)
                }
            }
            .frame(width: max(44, fr.width), height: max(44, fr.height))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: fr.midX, y: fr.midY)
        .accessibilityLabel(Text("Face \(face.id + 1)"))
        .accessibilityValue(Text(selected ? "Selected" : "Not selected"))
        .accessibilityHint(Text("Colors the hair of this person"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("face-\(face.id)")
    }

    // MARK: Overlays that do not zoom

    private var overlays: some View {
        ZStack {
            VStack(spacing: 8) {
                if !model.visibleHints.isEmpty {
                    EditorHintBanner(hints: Array(model.visibleHints.prefix(2))) {
                        model.hintsDismissed = true
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if model.hairNotFound && model.tool != .refine {
                noHairCard
            }

            if model.renderedImage == nil || model.isSwitchingFace {
                EdBusyBadge(text: model.isSwitchingFace ? "Switching face" : "Coloring your hair")
            }

            VStack {
                Spacer(minLength: 0)
                controls
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            if zoom > 1.02 && !model.splitMode {
                Button {
                    resetZoom()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LS.Palette.paper)
                        .frame(width: 44, height: 44)
                        .background(LS.Palette.carbon.opacity(0.85), in: Circle())
                        .overlay(Circle().strokeBorder(LS.Palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Reset zoom"))
                .accessibilityIdentifier("reset-zoom")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)
            }
        }
    }

    private var noHairCard: some View {
        VStack(spacing: 10) {
            Text("No hair found").font(LS.Font.title(22)).foregroundStyle(LS.Palette.paper)
            Text("Lustra could not find hair in this photo. Paint over the hair in Refine, or try another photo.")
                .font(LS.Font.callout)
                .foregroundStyle(LS.Palette.mist)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            EdButton(title: "Open Refine", symbol: "scribble", prominent: true, identifier: "open-refine") {
                model.tool = .refine
            }
        }
        .padding(LS.Space.m)
        .frame(maxWidth: 320)
        .lsGlass(radius: 22, tint: 0.88)
        .accessibilityIdentifier("no-hair-card")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            holdChip
            LSChip(title: "Split view", systemImage: "rectangle.split.2x1", selected: model.splitMode) {
                model.splitMode.toggle()
            }
            .accessibilityIdentifier("split-toggle")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var holdChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye").font(.system(size: 13, weight: .semibold))
            Text("Hold to compare").font(LS.Font.label).lineLimit(1)
        }
        .foregroundStyle(model.showOriginal ? LS.Palette.onAccent : LS.Palette.paper)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(model.showOriginal ? LS.Palette.accent : LS.Palette.graphite, in: Capsule())
        .overlay(Capsule().strokeBorder(LS.Palette.line, lineWidth: 1))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !model.showOriginal {
                        model.showOriginal = true
                        LSHaptics.tap()
                    }
                }
                .onEnded { _ in
                    model.showOriginal = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hold to compare with the original"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { model.showOriginal.toggle() }
        .accessibilityIdentifier("hold-compare")
    }
}

/// The tips banner over the photo: warnings first. One tap on the close button hides it.
struct EditorHintBanner: View {
    let hints: [PhotoHint]
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(hints.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.element.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(item.element.isWarning ? LS.Palette.danger : LS.Palette.accent)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(item.element.message)
                            .font(LS.Font.callout)
                            .foregroundStyle(LS.Palette.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 12)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LS.Palette.mist)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss tips"))
            .accessibilityIdentifier("dismiss-hints")
        }
        .lsGlass(radius: 16, tint: 0.88)
        .accessibilityIdentifier("hint-banner")
    }
}
