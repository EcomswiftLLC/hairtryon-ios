import XCTest
@testable import Lustra

final class ReviewPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        exports: Int = 3, sessions: Int = 3, installedDaysAgo: Double = 1,
        adSecondsAgo: Double? = nil, lastRequestDaysAgo: Double? = nil, lastVersion: String? = nil,
        adOnScreen: Bool = false, sheetOnScreen: Bool = false
    ) -> ReviewSnapshot {
        ReviewSnapshot(
            installDate: now.addingTimeInterval(-installedDaysAgo * 86_400),
            sessionCount: sessions,
            successfulExports: exports,
            lastAdDismissed: adSecondsAgo.map { now.addingTimeInterval(-$0) },
            lastRequestDate: lastRequestDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            lastRequestVersion: lastVersion,
            currentVersion: "1.0",
            adOnScreen: adOnScreen,
            shareSheetOnScreen: sheetOnScreen
        )
    }

    func testRequestsAfterThirdSuccessfulExportOnThirdSession() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(), exportSucceeded: true, now: now), .request)
    }

    func testNeverAfterAnErrorOrCancel() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(), exportSucceeded: false, now: now), .blocked(.exportNotSuccessful))
    }

    func testNeedsThreeExports() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(exports: 2), exportSucceeded: true, now: now), .blocked(.tooFewExports))
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(exports: 9), exportSucceeded: true, now: now), .request)
    }

    func testNeedsTwoDaysOrThreeSessions() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(sessions: 2, installedDaysAgo: 1.9), exportSucceeded: true, now: now), .blocked(.tooSoonAfterInstall))
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(sessions: 2, installedDaysAgo: 2.1), exportSucceeded: true, now: now), .request)
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(sessions: 3, installedDaysAgo: 0.1), exportSucceeded: true, now: now), .request)
    }

    func testNotWithinSixtySecondsOfAnAd() {
        if case .blocked(.adShownRecently(let left)) = ReviewPolicy.evaluate(snapshot(adSecondsAgo: 20), exportSucceeded: true, now: now) {
            XCTAssertEqual(left, 40, accuracy: 0.01)
        } else {
            XCTFail("expected an ad block")
        }
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(adSecondsAgo: 61), exportSucceeded: true, now: now), .request)
        XCTAssertTrue(ReviewBlock.adShownRecently(secondsLeft: 5).clearsWithTime)
        XCTAssertFalse(ReviewBlock.tooFewExports.clearsWithTime)
    }

    func testNeverWhileAnAdOrShareSheetIsOnScreen() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(adOnScreen: true), exportSucceeded: true, now: now), .blocked(.adOnScreen))
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(sheetOnScreen: true), exportSucceeded: true, now: now), .blocked(.shareSheetOnScreen))
    }

    func testOncePerVersionAndEvery120Days() {
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(lastRequestDaysAgo: 300, lastVersion: "1.0"), exportSucceeded: true, now: now), .blocked(.alreadyAskedThisVersion))
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(lastRequestDaysAgo: 119, lastVersion: "0.9"), exportSucceeded: true, now: now), .blocked(.askedRecently))
        XCTAssertEqual(ReviewPolicy.evaluate(snapshot(lastRequestDaysAgo: 121, lastVersion: "0.9"), exportSucceeded: true, now: now), .request)
    }

    func testTrackerCountsAndStoresTheCounters() {
        let suite = "ls.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = ReviewTracker(defaults: defaults)
        tracker.recordSessionStart()
        tracker.recordSessionStart()
        tracker.recordExportSuccess()
        tracker.recordAdDismissed(at: now)
        tracker.recordRequested(version: "1.0", at: now)
        let s = tracker.snapshot(adOnScreen: false, shareSheetOnScreen: false, version: "1.0")
        XCTAssertEqual(s.sessionCount, 2)
        XCTAssertEqual(s.successfulExports, 1)
        XCTAssertEqual(s.lastAdDismissed, now)
        XCTAssertEqual(s.lastRequestVersion, "1.0")
    }

    func testRateRowLinkUsesTheWriteReviewAction() {
        // Until the app has an App Store id the row is hidden; the URL builder is checked with a known id in the app code path.
        if let url = AppLinks.writeReviewURL {
            XCTAssertTrue(url.absoluteString.hasSuffix("?action=write-review"))
        } else {
            XCTAssertNil(AppLinks.appStoreID)
        }
    }
}
