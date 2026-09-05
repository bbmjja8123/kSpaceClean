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

    /// kWatch Pro is a one-time Non-Consumable purchase, so the disclosure
    /// must state that explicitly and must NOT contain any auto-renew
    /// language (App Review §3.1.2(a) — misstating a one-time product as a
    /// subscription is rejection bait).
    func testBodyStatesOneTimePurchase() {
        // Each locale states the one-time nature in its own words.
        let oneTimePhrases = [
            "en": "one-time",
            "zh-Hans": "一次性买断",
            "ja": "買い切り",
        ]
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans"), Locale(identifier: "ja")] {
            let disclosure = SubscriptionTerms.disclosure(for: locale)
            let phrase = oneTimePhrases[locale.identifier] ?? "one-time"
            XCTAssertTrue(disclosure.body.contains(phrase), "买断披露必须明示一次性付费 (\(locale.identifier))")
            XCTAssertFalse(disclosure.body.lowercased().contains("auto-renew"), "买断商品不得出现自动续订陈述 (\(locale.identifier))")
            XCTAssertFalse(disclosure.body.lowercased().contains("automatically renew"), "买断商品不得出现自动续订陈述 (\(locale.identifier))")
        }
    }

    /// Privacy + Support URLs are non-empty and point at the same host.
    func testURLsAreStable() {
        XCTAssertEqual(SubscriptionTerms.privacyPolicyURL.host, "kraftly.app")
        XCTAssertEqual(SubscriptionTerms.supportURL.host, "kraftly.app")
    }
}