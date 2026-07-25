import SwiftUI

public extension Color {
    // Brand
    static let brandPrimary = Color(hex: "#7C3AED")
    static let brandSecondary = Color(hex: "#3B82F6")
    static let brandAccent = Color(hex: "#F59E0B")
    static let success = Color(hex: "#10B981")
    static let danger = Color(hex: "#EF4444")
    static let warning = Color(hex: "#F97316")

    // Semantic backgrounds
    static let bgPrimary = Color(hex: "#1C1C1E")
    static let bgSecondary = Color(hex: "#2C2C2E")
    static let bgTertiary = Color(hex: "#3A3A3C")
    static let textPrimary = Color(hex: "#F5F5F7")
    static let textSecondary = Color(hex: "#98989D")
    static let separatorColor = Color(hex: "#48484A")

    // File categories
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
