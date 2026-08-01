import Foundation

/// Localized auto-renewal disclosure text required by App Store Review
/// Guidelines §3.1.2(a). Surfaced in the Paywall view *before* the user
/// can complete a purchase.
///
/// The text follows Apple's standard subscription disclosure template and
/// is intentionally identical across all 3 supported locales except for
/// translation. Each translation lives in the `Localizable.xcstrings`
/// catalog under the keys listed below.
public enum SubscriptionTerms {
    /// Localization keys used to look up the disclosure copy.
    public enum LocalizationKey: String, CaseIterable {
        /// Title shown above the disclosure block.
        case title = "subscription.terms.title"
        /// Body paragraph explaining the auto-renewal behavior.
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