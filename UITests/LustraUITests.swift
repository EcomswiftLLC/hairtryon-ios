import XCTest

final class LustraUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Lustra"].waitForExistence(timeout: 15))
    }
}
