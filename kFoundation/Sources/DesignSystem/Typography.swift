import SwiftUI

public enum AppFont {
    /// Large SF Symbol glyph used for page icons (e.g. onboarding headers).
    public static let icon = Font.system(size: 56)
    public static let largeTitle = Font.system(size: 26, weight: .bold)
    public static let title2 = Font.system(size: 20, weight: .semibold)
    public static let title3 = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let callout = Font.system(size: 12)
    public static let caption = Font.system(size: 11)
    public static let monoDigit = Font.system(size: 13, design: .monospaced)
}
