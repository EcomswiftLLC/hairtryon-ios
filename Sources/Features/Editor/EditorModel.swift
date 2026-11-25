import SwiftUI
import UIKit

/// The tools in the editor's tool bar, in order.
enum EditorTool: String, CaseIterable, Identifiable {
    case colour, style, finish, refine, compare, looks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colour: return "Color"
        case .style: return "Style"
        case .finish: return "Finish"
        case .refine: return "Refine"
        case .compare: return "Compare"
        case .looks: return "Looks"
        }
    }

    var symbol: String {
        switch self {
        case .colour: return "paintpalette"
        case .style: return "paintbrush.pointed"
        case .finish: return "sparkles"
        case .refine: return "scribble"
        case .compare: return "square.grid.2x2"
        case .looks: return "heart"
        }
    }
}

/// What undo and redo step through: the look plus the brush strokes.
struct EditorState: Equatable {
    var look: HairLook
    var strokes: [BrushStroke]
}

/// One tile of the compare grid or the saved looks list.
struct EditorTile: Identifiable, Equatable {
    var id: String
    var title: String
    var look: HairLook
    var savedID: UUID?
    var isSaved: Bool { savedID != nil }
}

/// The result of one preview render.
struct EditorRenderResult {
    var image: UIImage?
    var overlay: UIImage?
    var stats: HairStats
}

@MainActor
final class EditorModel: ObservableObject {
    static let defaultLook: HairLook = {
        var l = HairLook()
        if let copper = HairPalette.shade(named: "Copper") { l.primary = copper.color }
        l.style = .solid
        return l
    }()

    let session: HairSession
    let looksStore: LooksStore
    /// The untouched photo at preview size, for hold-to-compare and the split view.
    let beforeImage: UIImage
    let aspect: CGFloat

    @Published private(set) var history: EditHistory<EditorState>
    @Published var tool: EditorTool = .colour {
        didSet { if (tool == .refine) != (oldValue == .refine) { requestRender() } }
    }
    @Published private(set) var renderedImage: UIImage?
    @Published private(set) var matteOverlay: UIImage?
    @Published private(set) var stats: HairStats?
    @Published private(set) var analysis: PhotoAnalysis
    @Published private(set) var isRendering = false
    @Published private(set) var isSwitchingFace = false
    @Published private(set) var liveStroke: BrushStroke?
    @Published private(set) var thumbs: [String: UIImage] = [:]
    @Published private(set) var thumbRevision = 0
    @Published var showOriginal = false
    @Published var splitMode = false
    @Published var splitFraction: Double = 0.5
    @Published var hintsDismissed = false
    @Published var showHairArea = true {
        didSet { if oldValue != showHairArea && tool == .refine { requestRender() } }
    }
    @Published var brushAdds = true
    /// 0...1, mapped to a radius by `brushRadius`.
    @Published var brushSize: Double = 0.4
    @Published var brushHardness: Double = 0.5
    @Published var exportPayload: ExportPayload?
    @Published var errorMessage: String?

    /// Debug screens can replace the hints with fixed ones, and store captures hide them.
    var hintOverride: [PhotoHint]?
    var hideHints = false

    private let pipeline: EditorRenderPipeline
    private let thumbPipeline: EditorThumbPipeline
    private var renderTicket = 0
    private var thumbEntries: [String: HairLook] = [:]
    private var isLiveEditing = false
    private var coalesceTask: Task<Void, Never>?

    init(session: HairSession, looksStore: LooksStore? = nil, initialLook: HairLook? = nil, initialTool: EditorTool = .colour, autoRender: Bool = true) {
        self.session = session
        self.looksStore = looksStore ?? LooksStore.shared
        self.pipeline = EditorRenderPipeline(session: session)
        self.thumbPipeline = EditorThumbPipeline(session: session)
        let look: HairLook = initialLook ?? EditorModel.defaultLook
        self.history = EditHistory(initial: EditorState(look: look, strokes: []))
        self.analysis = session.analysis
        let small: RGBAImage = session.source.resized(maxSide: DetailLevel.preview.maxSide)
        self.beforeImage = small.uiImage() ?? UIImage()
        self.aspect = CGFloat(session.source.width) / CGFloat(max(1, session.source.height))
        self.tool = initialTool
        if autoRender { requestRender() }
    }

    // MARK: Current state

    var look: HairLook { history.present.look }
    var strokes: [BrushStroke] { history.present.strokes }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// The palette colour that matches the primary colour exactly, if any.
    var primaryShade: HairShade? { HairPalette.all.first { $0.hex == look.primary.hex } }

    var primaryName: String { primaryShade?.name ?? "Custom color" }

    var brushRadius: CGFloat { CGFloat(0.008 + brushSize * 0.07) }

    var visibleHints: [PhotoHint] {
        if hintsDismissed || hideHints { return [] }
        let source: [PhotoHint] = hintOverride ?? analysis.hints
        let filtered: [PhotoHint] = source.filter { $0 != .noHairFound }
        let warnings: [PhotoHint] = filtered.filter { $0.isWarning }
        let others: [PhotoHint] = filtered.filter { !$0.isWarning }
        return warnings + others
    }

    var hairNotFound: Bool {
        if let s = stats { return !s.hasHair }
        return false
    }

    // MARK: Look edits

    func commitLook(_ new: HairLook) {
        history.commit(EditorState(look: new, strokes: strokes))
        requestRender()
    }

    func update(_ change: (inout HairLook) -> Void) {
        var l = look
        change(&l)
        commitLook(l)
    }

    /// Called by dials when a drag starts and ends: one drag is one undo step.
    func liveEditing(_ editing: Bool) {
        isLiveEditing = editing
        if !editing { history.endLive() }
    }

    func setLive(_ keyPath: WritableKeyPath<HairLook, Double>, _ value: Double) {
        var l = look
        l[keyPath: keyPath] = value
        let state = EditorState(look: l, strokes: strokes)
        if isLiveEditing { history.live(state) } else { history.commit(state) }
        requestRender()
    }

    /// For controls that give no start and end (the system color picker): changes within half a second share one undo step.
    func setLookCoalesced(_ l: HairLook) {
        history.live(EditorState(look: l, strokes: strokes))
        requestRender()
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.history.endLive()
        }
    }

    func applyShade(_ shade: HairShade) {
        update { $0.primary = shade.color }
    }

    func setPrimary(_ color: HairColor, coalesced: Bool = false) {
        var l = look
        l.primary = color
        if coalesced { setLookCoalesced(l) } else { commitLook(l) }
    }

    func setSecondary(_ color: HairColor, coalesced: Bool = false) {
        var l = look
        l.secondary = color
        if coalesced { setLookCoalesced(l) } else { commitLook(l) }
    }

    func setStyle(_ kind: HairStyleKind) {
        var l = look
        let wasSolid = !l.style.usesSecondary
        l.style = kind
        if kind.usesSecondary && wasSolid {
            l.secondary = HairPalette.suggestedSecondary(for: l.primary)
        }
        commitLook(l)
    }

    func setGrayCover(_ on: Bool) {
        update { $0.grayCoverOnly = on }
    }

    func apply(tile: EditorTile) {
        commitLook(tile.look)
    }

    // MARK: Undo and redo

    func undo() {
        let before = strokes
        history.undo()
        if before != strokes { invalidateThumbs() }
        requestRender()
    }

    func redo() {
        let before = strokes
        history.redo()
        if before != strokes { invalidateThumbs() }
        requestRender()
    }

    // MARK: Brush strokes

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, p.x)), y: min(1, max(0, p.y)))
    }

    func beginStroke(at p: CGPoint) {
        liveStroke = BrushStroke(points: [clamped(p)], radius: brushRadius, addsHair: brushAdds, hardness: CGFloat(brushHardness))
    }

    func extendStroke(to p: CGPoint) {
        guard var s = liveStroke else { return }
        let q = clamped(p)
        if let last = s.points.last {
            let dx = last.x - q.x, dy = last.y - q.y
            if dx * dx + dy * dy < 0.000004 { return }
        }
        s.points.append(q)
        liveStroke = s
    }

    func endStroke() {
        guard let s = liveStroke else { return }
        liveStroke = nil
        commitStroke(s)
    }

    func cancelStroke() {
        liveStroke = nil
    }

    func commitStroke(_ stroke: BrushStroke) {
        history.commit(EditorState(look: look, strokes: strokes + [stroke]))
        invalidateThumbs()
        requestRender()
    }

    func removeLastStroke() {
        guard !strokes.isEmpty else { return }
        history.commit(EditorState(look: look, strokes: Array(strokes.dropLast())))
        invalidateThumbs()
        requestRender()
    }

    func resetRefine() {
        guard !strokes.isEmpty else { return }
        history.commit(EditorState(look: look, strokes: []))
        invalidateThumbs()
        requestRender()
    }

    // MARK: Faces

    func selectFace(_ index: Int) {
        guard !isSwitchingFace, index >= 0, index < analysis.faces.count, index != analysis.selectedFace else { return }
        isSwitchingFace = true
        LSHaptics.tap()
        let session = self.session
        Task { [weak self] in
            var failure: String? = nil
            do {
                try await HairService.shared.selectFace(index, in: session)
            } catch {
                failure = error.localizedDescription
            }
            guard let self = self else { return }
            self.finishFaceSwitch(failure)
        }
    }

    private func finishFaceSwitch(_ failure: String?) {
        analysis = session.analysis
        pipeline.invalidate()
        invalidateThumbs()
        if !strokes.isEmpty { history.commit(EditorState(look: look, strokes: [])) }
        isSwitchingFace = false
        errorMessage = failure
        requestRender()
    }

    // MARK: Rendering

    /// Renders the current state at preview size on a background queue. The newest request wins.
    func requestRender() {
        let state = history.present
        let wantsOverlay = showHairArea && tool == .refine
        isRendering = true
        renderTicket += 1
        let ticket = renderTicket
        pipeline.renderPreview(look: state.look, strokes: state.strokes, wantsOverlay: wantsOverlay) { [weak self] result in
            guard let self = self else { return }
            if ticket != self.renderTicket { return }
            if let image = result.image { self.renderedImage = image }
            self.matteOverlay = result.overlay
            self.stats = result.stats
            self.isRendering = false
        }
    }

    // MARK: Thumbnails (compare grid and saved looks)

    var paletteTiles: [EditorTile] {
        var tiles: [EditorTile] = []
        for name in HairPalette.compareSelection {
            guard let shade = HairPalette.shade(named: name) else { continue }
            var l = look
            l.primary = shade.color
            tiles.append(EditorTile(id: "shade-" + name, title: name, look: l, savedID: nil))
        }
        return tiles
    }

    var savedTiles: [EditorTile] {
        looksStore.saved.map { entry in
            EditorTile(id: "saved-" + entry.id.uuidString, title: entry.name, look: entry.look, savedID: entry.id)
        }
    }

    var compareTiles: [EditorTile] { paletteTiles + savedTiles }

    /// Renders the tiles that have no up-to-date thumbnail yet, one after another, off the main thread.
    func loadThumbnails(for tiles: [EditorTile]) {
        let generation = thumbPipeline.currentGeneration()
        let strokesNow = strokes
        for tile in tiles {
            if thumbEntries[tile.id] == tile.look { continue }
            thumbEntries[tile.id] = tile.look
            let id = tile.id
            thumbPipeline.render(look: tile.look, strokes: strokesNow) { [weak self] image in
                guard let self = self else { return }
                if self.thumbPipeline.currentGeneration() != generation { return }
                if let image = image { self.thumbs[id] = image }
            }
        }
    }

    private func invalidateThumbs() {
        thumbPipeline.invalidate()
        thumbEntries.removeAll()
        thumbs.removeAll()
        thumbRevision += 1
    }

    // MARK: Saved looks

    var isCurrentLookSaved: Bool { looksStore.contains(look) }

    /// Saves the current look, or removes it when it is already saved. Returns true when it is saved afterwards.
    @discardableResult
    func toggleSavedLook() -> Bool {
        if let entry = looksStore.entry(for: look) {
            looksStore.remove(entry.id)
            return false
        }
        looksStore.add(look)
        return true
    }

    // MARK: Export

    func makeExportPayload() -> ExportPayload {
        let session = self.session
        let state = history.present
        let before: UIImage = session.source.resized(maxSide: 1600).uiImage() ?? beforeImage
        let title = LooksStore.defaultName(for: state.look)
        return ExportPayload(kind: .single, title: title, before: before, makeAfter: {
            await EditorExporter.renderFull(session: session, look: state.look, strokes: state.strokes)
        })
    }

    func makeComparisonPayload() -> ExportPayload {
        let session = self.session
        let state = history.present
        let before: UIImage = session.source.resized(maxSide: 1600).uiImage() ?? beforeImage
        return ExportPayload(kind: .comparison, title: "Color comparison", before: before, makeAfter: {
            await ComparisonComposer.render(session: session, look: state.look, strokes: state.strokes)
        })
    }

    func beginExport() {
        exportPayload = makeExportPayload()
    }

    func beginComparisonExport() {
        exportPayload = makeComparisonPayload()
    }
}

/// Renders the finished photo at full quality.
enum EditorExporter {
    static func renderFull(session: HairSession, look: HairLook, strokes: [BrushStroke]) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = session.context(.full, strokes: strokes)
                continuation.resume(returning: context.render(look).uiImage())
            }
        }
    }
}

// MARK: - Render pipelines

/// Renders live previews on one background queue. A newer request makes older ones that have not started yet skip their work.
final class EditorRenderPipeline: @unchecked Sendable {
    private let session: HairSession
    private let queue = DispatchQueue(label: "app.lustra.editor.render", qos: .userInitiated)
    private let lock = NSLock()
    private var newest = 0
    // Only touched on `queue`.
    private var cachedStrokes: [BrushStroke] = []
    private var cachedContext: HairContext?

    init(session: HairSession) {
        self.session = session
    }

    private func isStale(_ ticket: Int) -> Bool {
        lock.lock()
        let stale = ticket != newest
        lock.unlock()
        return stale
    }

    /// Drops the cached context (the matte changed, for example after choosing another face).
    func invalidate() {
        queue.async {
            self.cachedContext = nil
        }
    }

    private func context(for strokes: [BrushStroke]) -> HairContext {
        if let c = cachedContext, cachedStrokes == strokes { return c }
        let c = session.context(.preview, strokes: strokes)
        cachedContext = c
        cachedStrokes = strokes
        return c
    }

    func renderPreview(look: HairLook, strokes: [BrushStroke], wantsOverlay: Bool, completion: @escaping (EditorRenderResult) -> Void) {
        lock.lock()
        newest += 1
        let ticket = newest
        lock.unlock()
        queue.async {
            if self.isStale(ticket) { return }
            let ctx = self.context(for: strokes)
            if self.isStale(ticket) { return }
            let image: UIImage? = ctx.render(look).uiImage()
            var overlay: UIImage? = nil
            if wantsOverlay { overlay = EditorMatteOverlay.image(from: ctx.matte) }
            if self.isStale(ticket) { return }
            let result = EditorRenderResult(image: image, overlay: overlay, stats: ctx.stats)
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// Renders small, cropped thumbnails one at a time at low priority.
final class EditorThumbPipeline: @unchecked Sendable {
    private let session: HairSession
    private let queue = DispatchQueue(label: "app.lustra.editor.thumbs", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    // Only touched on `queue`.
    private var cachedStrokes: [BrushStroke] = []
    private var cachedContext: HairContext?
    private var cachedGeneration = -1

    init(session: HairSession) {
        self.session = session
    }

    func currentGeneration() -> Int {
        lock.lock()
        let g = generation
        lock.unlock()
        return g
    }

    /// Makes every queued and finished thumbnail obsolete.
    func invalidate() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    func render(look: HairLook, strokes: [BrushStroke], completion: @escaping (UIImage?) -> Void) {
        let gen = currentGeneration()
        queue.async {
            if self.currentGeneration() != gen { return }
            let ctx: HairContext
            if let c = self.cachedContext, self.cachedGeneration == gen, self.cachedStrokes == strokes {
                ctx = c
            } else {
                ctx = self.session.context(.thumb, strokes: strokes)
                self.cachedContext = ctx
                self.cachedGeneration = gen
                self.cachedStrokes = strokes
            }
            let rendered: RGBAImage = ctx.render(look)
            let image: UIImage? = EditorTileCrop.tileImage(from: rendered, stats: ctx.stats)
            if self.currentGeneration() != gen { return }
            DispatchQueue.main.async { completion(image) }
        }
    }
}

/// Turns the hair matte into a translucent tint for the Refine tool.
enum EditorMatteOverlay {
    static func image(from matte: Plane) -> UIImage? {
        let w = matte.width, h = matte.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        // Electric teal: easy to tell apart from hair, skin and background.
        let r: Float = 0.24, g: Float = 0.84, b: Float = 0.78
        for i in 0..<(w * h) {
            let m: Float = min(1, max(0, matte.data[i]))
            let a: Float = m * 0.5
            px[i * 4] = UInt8(r * a * 255)
            px[i * 4 + 1] = UInt8(g * a * 255)
            px[i * 4 + 2] = UInt8(b * a * 255)
            px[i * 4 + 3] = UInt8(a * 255)
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        guard let cg = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: space, bitmapInfo: info, provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}

/// Crops a rendered photo to a 4:5 tile around the hair, shared by the thumbnails and the exported grid.
enum EditorTileCrop {
    static let aspect: CGFloat = 0.8

    static func cropRect(width: Int, height: Int, stats: HairStats) -> CGRect {
        let W = CGFloat(width), H = CGFloat(height)
        var cw = W
        var ch = W / aspect
        if ch > H {
            ch = H
            cw = H * aspect
        }
        var cx = W / 2
        var y0: CGFloat = 0
        if stats.hasHair {
            cx = CGFloat(stats.centerX) * W
            y0 = CGFloat(stats.minY) * H - 0.08 * ch
        }
        var x0 = cx - cw / 2
        x0 = min(max(0, x0), W - cw)
        y0 = min(max(0, y0), H - ch)
        return CGRect(x: x0, y: y0, width: cw, height: ch)
    }

    static func tileImage(from image: RGBAImage, stats: HairStats) -> UIImage? {
        let rect = cropRect(width: image.width, height: image.height, stats: stats)
        if let cropped = image.cropped(rect) { return cropped.uiImage() }
        return image.uiImage()
    }
}
