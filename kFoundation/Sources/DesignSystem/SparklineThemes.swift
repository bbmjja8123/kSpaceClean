@preconcurrency import SwiftUI

/// A user-selectable visual theme for sparkline rendering.
///
/// Each theme provides a primary line color plus a two-stop gradient
/// (light → dark) used for the area fill below the line. Theme identity
/// is stored as a stable `id` string so the user-selected theme can be
/// persisted across launches in `UserDefaults`.
public struct SparklineTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let lineColor: Color
    public let gradientColors: [Color]

    public init(id: String, name: String, lineColor: Color, gradientColors: [Color]) {
        self.id = id
        self.name = name
        self.lineColor = lineColor
        self.gradientColors = gradientColors
    }

    /// All built-in themes, exposed in display order.
    public static let allThemes: [SparklineTheme] = [
        .blue, .green, .purple, .sunset, .monochrome, .vivid, .muted
    ]

    /// The fallback theme used when an unknown `id` is requested.
    public static let `default` = SparklineTheme.blue

    /// Look up a theme by its stable `id`. Falls back to `.default` when
    /// the `id` does not match any built-in theme (e.g. a previously
    /// installed version stored an unknown id).
    public static func theme(forID id: String) -> SparklineTheme {
        allThemes.first { $0.id == id } ?? .default
    }

    /// Bright but calm blue — the default pick for most users.
    public static let blue = SparklineTheme(
        id: "blue",
        name: "Ocean Blue",
        lineColor: Color(hex: "#3B82F6"),
        gradientColors: [Color(hex: "#60A5FA"), Color(hex: "#1D4ED8")]
    )

    /// Balanced green, easy on the eye for long-running dashboard views.
    public static let green = SparklineTheme(
        id: "green",
        name: "Forest",
        lineColor: Color(hex: "#10B981"),
        gradientColors: [Color(hex: "#34D399"), Color(hex: "#047857")]
    )

    /// Deep violet that matches the brand `brandPrimary` palette.
    public static let purple = SparklineTheme(
        id: "purple",
        name: "Twilight",
        lineColor: Color(hex: "#8B5CF6"),
        gradientColors: [Color(hex: "#A78BFA"), Color(hex: "#5B21B6")]
    )

    /// Warm amber → red gradient; great for CPU / temperature metrics.
    public static let sunset = SparklineTheme(
        id: "sunset",
        name: "Sunset",
        lineColor: Color(hex: "#F59E0B"),
        gradientColors: [Color(hex: "#FBBF24"), Color(hex: "#DC2626")]
    )

    /// Greyscale theme for users who prefer minimal color in the menu bar.
    public static let monochrome = SparklineTheme(
        id: "monochrome",
        name: "Mono",
        lineColor: Color(hex: "#6B7280"),
        gradientColors: [Color(hex: "#9CA3AF"), Color(hex: "#374151")]
    )

    /// High-saturation pink → purple gradient for users who want their
    /// menu bar charts to pop.
    public static let vivid = SparklineTheme(
        id: "vivid",
        name: "Vivid",
        lineColor: Color(hex: "#EC4899"),
        gradientColors: [Color(hex: "#F472B6"), Color(hex: "#7C3AED")]
    )

    /// Low-saturation slate tones that recede into the menu bar chrome.
    public static let muted = SparklineTheme(
        id: "muted",
        name: "Muted",
        lineColor: Color(hex: "#94A3B8"),
        gradientColors: [Color(hex: "#CBD5E1"), Color(hex: "#64748B")]
    )
}
