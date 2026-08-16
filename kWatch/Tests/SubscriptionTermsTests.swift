import XCTest
@testable import kWatch

/// Tests for the localized subscription-terms disclosure used in the
/// Paywall. The actual strings live in `Localizable.xcstrings`; these
/// tests guard the resolution contract so the Paywall never crashes on
/// a missing key.
final class SubscriptionTermsTests: XCTestCase {

    /// Default locale resolves to a non-empty bundle without throwing.
    func testDefaultLocaleReturnsNonEmptyDisclosure() {
        let disclosure = SubscriptionTerms.disclosure()
        XCTAssertFalse(disclosure.title.isEmpty)
        XCTAssertFalse(disclosure.body.isEmpty)
        XCTAssertFalse(disclosure.supportLink.isEmpty)
    }

    /// All three localization keys resolve under each supported locale.
    func testAllSupportedLocalesResolveKeys() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans"), Locale(identifier: "ja")] {
            let d = SubscriptionTerms.disclosure(for: locale)
            XCTAssertFalse(d.title.isEmpty, "title missing for \(locale.identifier)")
            XCTAssertFalse(d.body.isEmpty, "body missing for \(locale.identifier)")
            XCTAssertFalse(d.supportLink.isEmpty, "supportLink missing for \(locale.identifier)")
        }
    }

    /// Privacy + Support URLs are non-empty and point at the same host.
    func testURLsAreStable() {
        XCTAssertEqual(SubscriptionTerms.privacyPolicyURL.host, "kraftly.app")
        XCTAssertEqual(SubscriptionTerms.supportURL.host, "kraftly.app")
    }
}