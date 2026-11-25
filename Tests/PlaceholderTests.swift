import XCTest
@testable import Lustra

final class PlaceholderTests: XCTestCase {
    func testAdUnitNormalization() {
        XCTAssertNil(AdsConfiguration.normalizedUnitID("$(ADMOB_BANNER_UNIT_ID)"))
        XCTAssertEqual(AdsConfiguration.normalizedUnitID(" ca-app-pub-1/2 "), "ca-app-pub-1/2")
    }
}
