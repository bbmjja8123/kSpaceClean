import SwiftUI

public extension Color {
    // Brand colors (consistent across light/dark modes).
    static let brandPrimary = Color(hex: "#7C3AED")
    static let brandSecondary = Color(hex: "#3B82F6")
    static let brandAccent = Color(hex: "#F59E0B")
    static let success = Color(hex: "#10B981")
    static let danger = Color(hex: "#EF4444")
    static let warning = Color(hex: "#F97316")

    // Backwards-compatible semantic defaults (kept as the dark-mode values
    // so existing call sites continue to render correctly until they migrate
    // to `Color.resolve(_:for:)`).
    static let bgPrimary = Color(hex: "#1C1C1E")
    static let bgSecondary = Color(hex: "#2C2C2E")
    static let bgTertiary = Color(hex: "#3A3A3C")
    static let textPrimary = Color(hex: "#F5F5F7")
    static let textSecondary = Color(hex: "#98989D")
    static let separatorColor = Color(hex: "#48484A")

    // File category colors (brand-style, identical across modes).
    static let categoryImage = Color(hex: "#A855F7")
    static let categoryVideo = Color(hex: "#3B82F6")
    static let categoryDocument = Color(hex: "#10B981")
    static let categoryAudio = Color(hex: "#F59E0B")
    static let categoryCache = Color(hex: "#6B7280")
    static let categoryDev = Color(hex: "#EC4899")
    static let categoryApp = Color(hex: "#8B5CF6")
    static let categoryOther = Color(hex: "#9CA3AF")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let int = UInt64(hex, radix: 16) ?? 0
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Semantic color tokens that adapt to light vs dark appearance.
///
/// Each token resolves to a (light, dark) hex pair; brand tokens resolve to
/// the same value in both modes. Call sites that need to react to the
/// environment should use `Color.resolve(_:for:)` rather than the static
/// `Color.bgPrimary` constants.
public enum ColorToken: Sendable {
    case bgPrimary
    case bgSecondary
    case bgTertiary
    case textPrimary
    case textSecondary
    case separatorColor

    fileprivate var lightHex: String {
        switch self {
        case .bgPrimary: return "#FFFFFF"
        case .bgSecondary: return "#F5F5F7"
        case .bgTertiary: return "#E5E5EA"
        case .textPrimary: return "#1C1C1E"
        case .textSecondary: return "#6E6E73"
        case .separatorColor: return "#D1D1D6"
        }
    }

    fileprivate var darkHex: String {
        switch self {
        case .bgPrimary: return "#1C1C1E"
        case .bgSecondary: return "#2C2C2E"
        case .bgTertiary: return "#3A3A3C"
        case .textPrimary: return "#F5F5F7"
        case .textSecondary: return "#98989D"
        case .separatorColor: return "#48484A"
        }
    }
}

public extension Color {
    /// Resolve a `ColorToken` for the given color scheme.
    static func resolve(_ token: ColorToken, for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(hex: token.lightHex)
        case .dark:
            return Color(hex: token.darkHex)
        @unknown default:
            return Color(hex: token.darkHex)
        }
    }
}

public enum FileCategory: String, CaseIterable, Codable {
    case image, video, document, audio, cache, dev, app, other

    public var color: Color {
        switch self {
        case .image: return .categoryImage
        case .video: return .categoryVideo
        case .document: return .categoryDocument
        case .audio: return .categoryAudio
        case .cache: return .categoryCache
        case .dev: return .categoryDev
        case .app: return .categoryApp
        case .other: return .categoryOther
        }
    }

    /// Brand-style color for the given scheme. Categories are intentionally
    /// identical across light and dark modes; this exists so call sites that
    /// adopt the token-based resolution API have a uniform entry point.
    public func color(for scheme: ColorScheme) -> Color {
        _ = scheme
        return color
    }

    public var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .document: return "doc.text"
        case .audio: return "music.note"
        case .cache: return "archivebox"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .app: return "app"
        case .other: return "questionmark.folder"
        }
    }
}