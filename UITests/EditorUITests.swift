import XCTest
import UIKit

/// Walks the editor on a debug screen (bundled sample photo, real hair detection) in portrait.
/// Launch arguments: `-lsScreen <name>` opens the screen, `-lsNoAds YES` keeps the consent form away.
final class EditorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ screen: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-lsScreen", screen, "-lsNoAds", "YES"]
        app.launch()
        return app
    }

    /// Finds an element of any type by its accessibility identifier.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the tool panel until the element can be tapped.
    private func scrollIntoView(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        let panel = app.scrollViews["panel-scroll"].firstMatch
        var tries = 0
        while !(target.exists && target.isHittable) && tries < 8 {
            if panel.exists { panel.swipeUp() } else { app.swipeUp() }
            tries += 1
        }
    }

    private func openEditor(_ screen: String) -> XCUIApplication {
        let app = launch(screen)
        // Opening a photo runs the hair model, so allow plenty of time.
        let ready = element(app, "tool-colour").waitForExistence(timeout: 120)
        if !ready, element(app, "debug-error").exists {
            XCTFail("Hair detection is unavailable on this build")
        }
        XCTAssertTrue(ready, "The editor did not open on \(screen)")
        return app
    }

    func testEditorShowsItsKeyControls() {
        let app = openEditor("editor-colour")
        for id in ["close-editor", "undo", "redo", "save-export", "hold-compare", "split-toggle",
                   "tool-colour", "tool-style", "tool-finish", "tool-refine", "tool-compare", "tool-looks"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "Missing control \(id)")
        }
        // The swatches sit further down the panel, so scroll to them first.
        for id in ["swatch-Copper", "custom-color"] {
            scrollIntoView(app, id)
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "Missing control \(id)")
        }
        XCTAssertFalse(element(app, "undo").isEnabled, "Nothing to undo on a fresh photo")
    }

    func testPickingASwatchEnablesUndo() {
        let app = openEditor("editor-colour")
        let swatch = element(app, "swatch-Chestnut")
        XCTAssertTrue(swatch.waitForExistence(timeout: 10))
        swatch.tap()
        let undo = element(app, "undo")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: undo)
        waitForExpectations(timeout: 10)
        undo.tap()
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: undo)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(element(app, "redo").isEnabled)
    }

    func testDraggingTheIntensityDialChangesItsValue() {
        let app = openEditor("editor-colour")
        scrollIntoView(app, "dial-intensity")
        let dial = element(app, "dial-intensity")
        XCTAssertTrue(dial.waitForExistence(timeout: 10))
        let before = dial.value as? String ?? ""
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
        let after = dial.value as? String ?? ""
        XCTAssertNotEqual(before, after, "The intensity value did not change")
        XCTAssertTrue(element(app, "undo").isEnabled)
    }

    func testSwitchingBetweenTools() {
        let app = openEditor("editor-colour")
        element(app, "tool-style").tap()
        XCTAssertTrue(element(app, "style-ombre").waitForExistence(timeout: 10))
        element(app, "style-ombre").tap()
        XCTAssertTrue(element(app, "custom-second-color").waitForExistence(timeout: 10))
        element(app, "tool-finish").tap()
        XCTAssertTrue(element(app, "dial-shine").waitForExistence(timeout: 10))
        element(app, "tool-refine").tap()
        XCTAssertTrue(element(app, "brush-add").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "brush-remove").exists)
        element(app, "brush-remove").tap()
        element(app, "tool-colour").tap()
        scrollIntoView(app, "swatch-Copper")
        XCTAssertTrue(element(app, "swatch-Copper").waitForExistence(timeout: 10))
    }

    func testCompareGridAndExportGrid() {
        let app = openEditor("editor-colour")
        element(app, "tool-compare").tap()
        let export = element(app, "export-grid")
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        scrollIntoView(app, "tile-Platinum")
        XCTAssertTrue(element(app, "tile-Platinum").waitForExistence(timeout: 10))
        element(app, "tile-Platinum").tap()
        XCTAssertTrue(element(app, "undo").isEnabled)
        export.tap()
        let close = element(app, "export.close")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The export screen did not open")
        close.tap()
        XCTAssertTrue(element(app, "tool-colour").waitForExistence(timeout: 20))
    }

    func testLooksTabSavesTheCurrentLook() {
        let app = openEditor("looks")
        XCTAssertTrue(element(app, "save-look").waitForExistence(timeout: 20))
        element(app, "save-look").tap()
        XCTAssertTrue(element(app, "save-look").exists)
    }

    func testSaveOpensTheExportScreen() {
        let app = openEditor("editor-colour")
        element(app, "save-export").tap()
        let close = element(app, "export.close")
        XCTAssertTrue(close.waitForExistence(timeout: 30), "The export screen did not open")
        close.tap()
        XCTAssertTrue(element(app, "save-export").waitForExistence(timeout: 20))
    }

    func testRefineTabShowsTheBrushControls() {
        let app = openEditor("editor-refine")
        for id in ["brush-add", "brush-remove", "dial-brush-size", "dial-brush-hardness", "toggle-hair-area", "reset-refine"] {
            scrollIntoView(app, id)
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "Missing control \(id)")
        }
    }
}

/// Opens the editor screens on a device turned to landscape and saves a screenshot of each.
/// A test fails when the window does not end up wider than tall, so a rotation that did not happen can never pass.
final class EditorLandscapeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// The simulator hands back its portrait frame buffer with a landscape picture lying on its side, so turn it upright.
    private func uprightScreenshot() -> UIImage {
        let source: UIImage = XCUIScreen.main.screenshot().image
        let sourceFormat = UIGraphicsImageRendererFormat()
        sourceFormat.scale = source.scale
        let image: UIImage = UIGraphicsImageRenderer(size: source.size, format: sourceFormat).image { _ in source.draw(at: .zero) }
        guard image.size.height > image.size.width else { return image }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            image.draw(at: .zero)
        }
    }

    private func check(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchArguments = ["-lsScreen", screen, "-lsNoAds", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "No app window for \(screen)", file: file, line: line)
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, window.frame.width <= window.frame.height {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        // The editor is ready when its tool bar exists; give the thumbnails a few more seconds.
        let ready = app.descendants(matching: .any).matching(identifier: "tool-colour").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 120), "\(screen): the editor did not open", file: file, line: line)
        RunLoop.current.run(until: Date().addingTimeInterval(6))

        let frame = window.frame
        let shot = XCTAttachment(image: uprightScreenshot())
        shot.name = "landscape-\(screen)"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertGreaterThan(frame.width, frame.height, "\(screen): window is \(Int(frame.width))x\(Int(frame.height)), not landscape", file: file, line: line)
        XCTAssertTrue(app.state == .runningForeground, "\(screen): app left the foreground", file: file, line: line)
        app.terminate()
    }

    func testEditorColourLandscape() { check("editor-colour") }
    func testEditorRefineLandscape() { check("editor-refine") }
    func testCompareGridLandscape() { check("compare-grid") }
    func testEditorOmbreLandscape() { check("editor-ombre") }
}
