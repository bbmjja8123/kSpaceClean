import SwiftUI

public enum AppFont {
    /// Large SF Symbol glyph used for page icons (e.g. onboarding headers).
    public static let icon = Font.system(size: 56)
    /// Display size for empty-state icons. Plain weight — the glyph is an
    /// SF Symbol, and bold would change its rendering.
    public static let display = Font.system(size: 48)
    /// Large app-icon glyph (Settings → About). Plain weight, same reason.
    public static let appIcon = Font.system(size: 64)
    public static let largeTitle = Font.system(size: 26, weight: .bold)
    public static let title2 = Font.system(size: 20, weight: .semibold)
    public static let title3 = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let bodyLarge = Font.system(size: 15)
    public static let callout = Font.system(size: 12)
    public static let caption = Font.system(size: 11)
    public static let monoDigit = Font.system(size: 13, design: .monospaced)
    /// Hero title used at the top of large feature surfaces (e.g. empty states,
    /// marketing headers). Bold at 28pt — sized between `largeTitle` and
    /// SwiftUI's built-in `.largeTitle` (34pt) to leave room for a subtitle
    /// underneath.
    public static let titleHero = Font.system(size: 28, weight: .bold)
    /// Rounded-design numeric font for primary metric values (e.g. dashboard
    /// "CPU 42%"). Rounded figures read friendlier at small sizes than the
    /// default design.
    public static let numberSize = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Monospaced small font for numeric captions and unit labels (e.g. "GB",
    /// "MHz"). Monospaced keeps columns of digits visually aligned in tables
    /// and tooltips.
    public static let numberCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
}
