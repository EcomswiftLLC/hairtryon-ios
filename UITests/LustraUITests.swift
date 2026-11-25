import XCTest

/// First-run flow: the welcome screen, then Home with its main actions, then Settings.
final class LustraUITests: XCTestCase {
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        // -ls.hasOnboarded NO shows the welcome screen again; -lsNoAds keeps Google's consent form out of the way.
        app.launchArguments = ["-ls.hasOnboarded", "NO", "-lsNoAds", "YES"]
        app.launch()
        return app
    }

    func testWelcomeThenHome() {
        let app = launchFresh()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "welcome screen shows Get started")
        if !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["home.choose"].waitForExistence(timeout: 15), "Home shows Choose a photo")
        XCTAssertTrue(app.staticTexts["Lustra"].exists)
    }

    func testSettingsOpensAndCloses() {
        let app = launchFresh()
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        if !start.isHittable { app.swipeUp() }
        start.tap()
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 10), "Settings opens")
        XCTAssertTrue(app.staticTexts["Privacy policy"].exists || app.buttons["Privacy policy"].exists || app.links["Privacy policy"].exists)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["home.choose"].waitForExistence(timeout: 10), "back on Home")
    }
}
