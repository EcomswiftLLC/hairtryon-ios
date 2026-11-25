import XCTest
import UIKit
@testable import Lustra

/// Answers every hair question with a fixed probability plane, so editor logic can be tested without the Core ML model.
private struct FixedMatteSource: HairMatteSource {
    let plane: Plane
    func hairProbability(square: CGImage) throws -> Plane { plane }
}

@MainActor
final class EditorModelTests: XCTestCase {
    private func makeSession() throws -> HairSession {
        let (img, matte) = Synthetic.portrait()
        // The engine draws the photo into a 640 px square of side max(w, h) centred on the photo, then maps the answer back.
        let n = 320
        let side = Float(max(img.width, img.height))
        let originX = Float(img.width) / 2 - side / 2
        let originY = Float(img.height) / 2 - side / 2
        var prob = Plane(width: n, height: n)
        for v in 0..<n {
            for u in 0..<n {
                let x = Int((Float(u) + 0.5) / Float(n) * side + originX)
                let y = Int((Float(v) + 0.5) / Float(n) * side + originY)
                if x >= 0 && x < img.width && y >= 0 && y < img.height {
                    prob[u, v] = matte[x, y]
                }
            }
        }
        return try HairSession.open(rgba: img, matteSource: FixedMatteSource(plane: prob))
    }

    private func makeStore() -> LooksStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lustra-test-looks-\(UUID().uuidString).json")
        return LooksStore(url: url)
    }

    private func makeModel(autoRender: Bool = false) throws -> EditorModel {
        EditorModel(session: try makeSession(), looksStore: makeStore(), autoRender: autoRender)
    }

    private func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    func testStartsWithTheCopperLook() throws {
        let model = try makeModel()
        XCTAssertEqual(model.look.primary, HairPalette.shade(named: "Copper")?.color)
        XCTAssertEqual(model.look.style, .solid)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(model.primaryName, "Copper")
    }

    func testUndoAndRedoRestoreTheLook() throws {
        let model = try makeModel()
        let copper = model.look.primary
        let platinum = try XCTUnwrap(HairPalette.shade(named: "Platinum"))
        model.applyShade(platinum)
        XCTAssertEqual(model.look.primary, platinum.color)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.look.primary, copper)
        XCTAssertTrue(model.canRedo)
        model.redo()
        XCTAssertEqual(model.look.primary, platinum.color)
        XCTAssertFalse(model.canRedo)
    }

    func testSameColourTwiceIsOneUndoStep() throws {
        let model = try makeModel()
        let platinum = try XCTUnwrap(HairPalette.shade(named: "Platinum"))
        model.applyShade(platinum)
        model.applyShade(platinum)
        XCTAssertEqual(model.history.past.count, 1)
    }

    func testASliderDragIsOneUndoStep() throws {
        let model = try makeModel()
        let start = model.look.shine
        model.liveEditing(true)
        for value in [0.4, 0.5, 0.6, 0.7, 0.8] {
            model.setLive(\.shine, value)
        }
        XCTAssertEqual(model.look.shine, 0.8, accuracy: 0.0001)
        model.liveEditing(false)
        XCTAssertEqual(model.history.past.count, 1)
        model.undo()
        XCTAssertEqual(model.look.shine, start, accuracy: 0.0001)
        XCTAssertFalse(model.canUndo)
    }

    func testAValueChangeWithoutADragIsCommittedAtOnce() throws {
        let model = try makeModel()
        model.setLive(\.intensity, 0.5)
        XCTAssertEqual(model.history.past.count, 1)
    }

    func testStrokesGoThroughHistory() throws {
        let model = try makeModel()
        model.brushAdds = true
        model.beginStroke(at: CGPoint(x: 0.4, y: 0.2))
        model.extendStroke(to: CGPoint(x: 0.5, y: 0.25))
        model.extendStroke(to: CGPoint(x: 0.6, y: 0.3))
        XCTAssertNotNil(model.liveStroke)
        XCTAssertTrue(model.strokes.isEmpty, "A stroke in progress is not in the history yet")
        model.endStroke()
        XCTAssertNil(model.liveStroke)
        XCTAssertEqual(model.strokes.count, 1)
        XCTAssertTrue(model.strokes[0].addsHair)
        XCTAssertEqual(model.strokes[0].points.count, 3)

        model.brushAdds = false
        model.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        model.endStroke()
        XCTAssertEqual(model.strokes.count, 2)
        XCTAssertFalse(model.strokes[1].addsHair)

        model.undo()
        XCTAssertEqual(model.strokes.count, 1)
        model.redo()
        XCTAssertEqual(model.strokes.count, 2)
        model.resetRefine()
        XCTAssertTrue(model.strokes.isEmpty)
        model.undo()
        XCTAssertEqual(model.strokes.count, 2)
    }

    func testStrokePointsStayInsideThePhoto() throws {
        let model = try makeModel()
        model.beginStroke(at: CGPoint(x: -0.5, y: 1.7))
        model.endStroke()
        let p = try XCTUnwrap(model.strokes.first?.points.first)
        XCTAssertEqual(p.x, 0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 1, accuracy: 0.0001)
    }

    func testCancelledStrokeLeavesNoTrace() throws {
        let model = try makeModel()
        model.beginStroke(at: CGPoint(x: 0.3, y: 0.3))
        model.cancelStroke()
        XCTAssertNil(model.liveStroke)
        XCTAssertTrue(model.strokes.isEmpty)
        XCTAssertFalse(model.canUndo)
    }

    func testChoosingAStyleSuggestsASecondColour() throws {
        let model = try makeModel()
        let before = model.look.secondary
        model.setStyle(.ombre)
        XCTAssertEqual(model.look.style, .ombre)
        XCTAssertEqual(model.look.secondary, HairPalette.suggestedSecondary(for: model.look.primary))
        XCTAssertNotEqual(model.look.secondary, before)
        model.setStyle(.balayage)
        XCTAssertEqual(model.look.style, .balayage)
    }

    func testApplyingASavedLook() throws {
        let store = makeStore()
        var saved = HairLook()
        saved.style = .ombre
        saved.primary = HairColor(hex: 0x5C1229)
        saved.secondary = HairColor(hex: 0xD49A86)
        saved.rootShadow = 0.4
        store.add(saved, name: "Wine ombre")
        let model = EditorModel(session: try makeSession(), looksStore: store, autoRender: false)
        let tile = try XCTUnwrap(model.savedTiles.first)
        XCTAssertEqual(tile.title, "Wine ombre")
        XCTAssertTrue(tile.isSaved)
        model.apply(tile: tile)
        XCTAssertEqual(model.look, saved)
        XCTAssertTrue(model.isCurrentLookSaved)
        model.undo()
        XCTAssertNotEqual(model.look, saved)
    }

    func testSavingAndRemovingTheCurrentLook() throws {
        let model = try makeModel()
        XCTAssertFalse(model.isCurrentLookSaved)
        XCTAssertTrue(model.toggleSavedLook())
        XCTAssertTrue(model.isCurrentLookSaved)
        XCTAssertEqual(model.looksStore.saved.count, 1)
        XCTAssertFalse(model.toggleSavedLook())
        XCTAssertFalse(model.isCurrentLookSaved)
        XCTAssertTrue(model.looksStore.saved.isEmpty)
    }

    func testCompareTileCount() throws {
        let store = makeStore()
        let model = EditorModel(session: try makeSession(), looksStore: store, autoRender: false)
        XCTAssertEqual(model.paletteTiles.count, HairPalette.compareSelection.count)
        XCTAssertEqual(model.compareTiles.count, HairPalette.compareSelection.count)
        store.add(HairLook(), name: "Saved")
        XCTAssertEqual(model.compareTiles.count, HairPalette.compareSelection.count + 1)
        // Every colour tile keeps the rest of the current look.
        for tile in model.paletteTiles {
            var expected = model.look
            expected.primary = tile.look.primary
            XCTAssertEqual(tile.look, expected)
        }
        XCTAssertEqual(Set(model.compareTiles.map { $0.id }).count, model.compareTiles.count, "Tile ids must be unique")
    }

    func testGridColoursAllExist() {
        for name in ComparisonComposer.names {
            XCTAssertNotNil(HairPalette.shade(named: name), name)
        }
        XCTAssertEqual(ComparisonComposer.names.count + 1, ComparisonComposer.columns * ComparisonComposer.rows)
    }

    func testPreviewRenderProducesAnImage() async throws {
        let model = try makeModel(autoRender: true)
        let done = await waitUntil { model.renderedImage != nil && !model.isRendering }
        XCTAssertTrue(done, "The preview never finished rendering")
        let image = try XCTUnwrap(model.renderedImage)
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertEqual(model.stats?.hasHair, true)
        XCTAssertFalse(model.hairNotFound)
    }

    func testTheNewestRenderRequestWins() async throws {
        let model = try makeModel(autoRender: true)
        model.liveEditing(true)
        for i in 1...12 {
            model.setLive(\.brightness, Double(i) / 24)
        }
        model.liveEditing(false)
        let done = await waitUntil { model.renderedImage != nil && !model.isRendering }
        XCTAssertTrue(done)
        XCTAssertEqual(model.look.brightness, 0.5, accuracy: 0.0001)
    }

    func testThumbnailsAreRenderedForEveryTile() async throws {
        let model = try makeModel()
        model.loadThumbnails(for: model.compareTiles)
        let expected = model.compareTiles.count
        let done = await waitUntil(timeout: 90) { model.thumbs.count == expected }
        XCTAssertTrue(done, "Only \(model.thumbs.count) of \(expected) thumbnails were rendered")
        for image in model.thumbs.values {
            XCTAssertEqual(image.size.width / image.size.height, EditorTileCrop.aspect, accuracy: 0.03)
        }
    }

    func testSingleExportPayload() async throws {
        let model = try makeModel()
        let payload = model.makeExportPayload()
        XCTAssertEqual(payload.kind, .single)
        XCTAssertFalse(payload.title.isEmpty)
        XCTAssertGreaterThan(payload.before.size.width, 0)
        let after = await payload.makeAfter()
        let image = try XCTUnwrap(after)
        XCTAssertEqual(Int(image.size.width), 400)
        XCTAssertEqual(Int(image.size.height), 500)
    }

    func testBeginExportPresentsThePayload() throws {
        let model = try makeModel()
        XCTAssertNil(model.exportPayload)
        model.beginExport()
        XCTAssertNotNil(model.exportPayload)
        XCTAssertEqual(model.exportPayload?.kind, .single)
    }

    func testComparisonExportPayload() async throws {
        let model = try makeModel()
        model.beginComparisonExport()
        let payload = try XCTUnwrap(model.exportPayload)
        XCTAssertEqual(payload.kind, .comparison)
        let after = await payload.makeAfter()
        let image = try XCTUnwrap(after)
        XCTAssertEqual(Int(image.size.width), 1600)
        XCTAssertEqual(Int(image.size.height), 2000)
    }

    func testHintsHideAfterDismissingAndSkipTheNoHairHint() throws {
        let model = try makeModel()
        model.hintOverride = [.noHairFound, .lowLight, .blurry]
        XCTAssertEqual(model.visibleHints, [.blurry, .lowLight])
        model.hintsDismissed = true
        XCTAssertTrue(model.visibleHints.isEmpty)
    }

    func testBrushRadiusGrowsWithTheSize() throws {
        let model = try makeModel()
        model.brushSize = 0
        let small = model.brushRadius
        model.brushSize = 1
        XCTAssertGreaterThan(model.brushRadius, small)
    }

    func testTileCropStaysInsideTheImage() {
        var stats = HairStats()
        stats.pixelCount = 1000
        stats.minY = 0.9
        stats.centerX = 0.98
        let rect = EditorTileCrop.cropRect(width: 360, height: 450, stats: stats)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 360.001)
        XCTAssertLessThanOrEqual(rect.maxY, 450.001)
        XCTAssertEqual(rect.width / rect.height, EditorTileCrop.aspect, accuracy: 0.01)
    }
}
