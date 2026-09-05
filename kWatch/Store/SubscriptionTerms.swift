import Foundation

/// Localized one-time purchase disclosure text shown in the Paywall *before*
/// the user can complete a purchase.
///
/// kWatch Pro is a Non-Consumable ($7.99, one-time). The copy must state the
/// one-time nature explicitly and must never describe auto-renewal — a
/// subscription-style disclosure on a one-time product misstates the business
/// model and is an App Review risk (cf. Guidelines §3.1.2(a) templates).
///
/// The text is intentionally identical across all 3 supported locales except
/// for translation. Each translation lives in the `Localizable.xcstrings`
/// catalog under the keys listed below.
public enum SubscriptionTerms {
    /// URLs the disclosure links to. Centralised so `PaywallView` and any
    /// other presentation surfaces share the same targets. Update these
    /// when the privacy / support sites move (see V1-TODO C4 + C5).
    public static let privacyPolicyURL: URL = URL(string: "https://kraftly.app/kwatch/privacy")!
    public static let supportURL: URL = URL(string: "https://kraftly.app/kwatch/support")!

    /// Localization keys used to look up the disclosure copy.
    public enum LocalizationKey: String, CaseIterable {
        /// Title shown above the disclosure block.
        case title = "subscription.terms.title"
        /// Body paragraph stating the one-time purchase terms.
        case body = "subscription.terms.body"
        /// Hyperlink copy pointing to the support URL.
        case supportLink = "subscription.terms.supportLink"

        public var localizationKey: String { rawValue }
    }

    /// Returns the localized disclosure bundle for the given locale.
    /// Falls back to English if the requested locale is unsupported.
    public static func disclosure(for locale: Locale = .current) -> Disclosure {
        let bundle = localizationBundle(for: locale)
        return Disclosure(
            title: bundle.localizedString(forKey: LocalizationKey.title.rawValue, value: nil, table: nil),
            body: bundle.localizedString(forKey: LocalizationKey.body.rawValue, value: nil, table: nil),
            supportLink: bundle.localizedString(forKey: LocalizationKey.supportLink.rawValue, value: nil, table: nil)
        )
    }

    /// Bundle that contains the disclosure strings. Currently the main
    /// bundle; a future change could load a per-region sub-bundle.
    private static func localizationBundle(for locale: Locale) -> Bundle {
        guard let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// Disclosure block consumed by `PaywallView`.
    public struct Disclosure: Equatable {
        public let title: String
        public let body: String
        public let supportLink: String

        public init(title: String, body: String, supportLink: String) {
            self.title = title
            self.body = body
            self.supportLink = supportLink
        }
    }
}