import Foundation

/// Everything the review-prompt rule needs to know. A plain value, so the rule can be unit tested.
struct ReviewSnapshot: Equatable {
    var installDate: Date
    var sessionCount: Int
    var successfulExports: Int
    var lastAdDismissed: Date?
    var lastRequestDate: Date?
    var lastRequestVersion: String?
    var currentVersion: String
    var adOnScreen: Bool = false
    var shareSheetOnScreen: Bool = false
}

enum ReviewBlock: Equatable {
    case exportNotSuccessful
    case tooFewExports
    case tooSoonAfterInstall
    case adOnScreen
    case shareSheetOnScreen
    case adShownRecently(secondsLeft: TimeInterval)
    case alreadyAskedThisVersion
    case askedRecently

    /// True when waiting (without the person doing anything) can make the request possible.
    var clearsWithTime: Bool {
        if case .adShownRecently = self { return true }
        return false
    }
}

enum ReviewDecision: Equatable {
    case request
    case blocked(ReviewBlock)
}

/// The rule for Apple's review prompt. Apple's own rate limit applies on top of this (three prompts a year at most).
///
/// The prompt is asked for only at a happy moment: right after the third successful save or export, while the "saved"
/// confirmation is showing, and only when none of the blocks below apply.
enum ReviewPolicy {
    static let requiredExports = 3
    static let minDaysSinceInstall: Double = 2
    static let minSessionsSinceInstall = 3
    static let quietSecondsAfterAd: TimeInterval = 60
    static let minDaysBetweenRequests: Double = 120

    static func evaluate(_ s: ReviewSnapshot, exportSucceeded: Bool, now: Date = Date()) -> ReviewDecision {
        guard exportSucceeded else { return .blocked(.exportNotSuccessful) }
        guard s.successfulExports >= requiredExports else { return .blocked(.tooFewExports) }
        let days = now.timeIntervalSince(s.installDate) / 86_400
        guard days >= minDaysSinceInstall || s.sessionCount >= minSessionsSinceInstall else { return .blocked(.tooSoonAfterInstall) }
        if s.adOnScreen { return .blocked(.adOnScreen) }
        if s.shareSheetOnScreen { return .blocked(.shareSheetOnScreen) }
        if s.lastRequestVersion == s.currentVersion { return .blocked(.alreadyAskedThisVersion) }
        if let last = s.lastRequestDate, now.timeIntervalSince(last) / 86_400 < minDaysBetweenRequests { return .blocked(.askedRecently) }
        if let ad = s.lastAdDismissed {
            let elapsed = now.timeIntervalSince(ad)
            if elapsed >= 0 && elapsed < quietSecondsAfterAd { return .blocked(.adShownRecently(secondsLeft: quietSecondsAfterAd - elapsed)) }
        }
        return .request
    }
}

/// Stores the counters in UserDefaults, on the device only.
final class ReviewTracker {
    static let shared = ReviewTracker()

    private let defaults: UserDefaults
    private enum Key {
        static let install = "ls.review.installDate"
        static let sessions = "ls.review.sessions"
        static let exports = "ls.review.exports"
        static let lastAd = "ls.review.lastAdDismissed"
        static let lastRequest = "ls.review.lastRequestDate"
        static let lastVersion = "ls.review.lastRequestVersion"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.install) == nil { defaults.set(Date(), forKey: Key.install) }
    }

    /// Call once per app launch.
    func recordSessionStart() { defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions) }
    /// Call after a save, file save or share finished successfully.
    func recordExportSuccess() { defaults.set(defaults.integer(forKey: Key.exports) + 1, forKey: Key.exports) }
    /// Call when a rewarded ad is closed (or fails while showing).
    func recordAdDismissed(at date: Date = Date()) { defaults.set(date, forKey: Key.lastAd) }
    func recordRequested(version: String, at date: Date = Date()) {
        defaults.set(date, forKey: Key.lastRequest)
        defaults.set(version, forKey: Key.lastVersion)
    }

    func snapshot(adOnScreen: Bool, shareSheetOnScreen: Bool, version: String = ReviewTracker.appVersion) -> ReviewSnapshot {
        ReviewSnapshot(
            installDate: (defaults.object(forKey: Key.install) as? Date) ?? Date(),
            sessionCount: defaults.integer(forKey: Key.sessions),
            successfulExports: defaults.integer(forKey: Key.exports),
            lastAdDismissed: defaults.object(forKey: Key.lastAd) as? Date,
            lastRequestDate: defaults.object(forKey: Key.lastRequest) as? Date,
            lastRequestVersion: defaults.string(forKey: Key.lastVersion),
            currentVersion: version,
            adOnScreen: adOnScreen,
            shareSheetOnScreen: shareSheetOnScreen
        )
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

/// App Store links. The numeric id is known only after the ASC record exists (see AppLinks.appStoreID).
enum AppLinks {
    /// Filled in once the app has an App Store id (ASC app id). While nil, the "Rate Lustra" row is hidden.
    static let appStoreID: String? = nil

    static var writeReviewURL: URL? {
        guard let id = appStoreID, !id.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }

    static let privacyURL = URL(string: "https://ecomswiftllc.github.io/lustra/privacy/")!
    static let termsURL = URL(string: "https://ecomswiftllc.github.io/lustra/terms/")!
    static let supportURL = URL(string: "https://ecomswiftllc.github.io/lustra/support/")!
    static let licensesURL = URL(string: "https://ecomswiftllc.github.io/lustra/licenses/")!
    static let mailURL = URL(string: "mailto:support@ecomswiftllc.com")!
}
