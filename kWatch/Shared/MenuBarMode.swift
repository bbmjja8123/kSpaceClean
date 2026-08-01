import Foundation

/// Presentation mode for the menu bar status item.
///
/// `trend` shows a mini sparkline, `numeric` shows the primary metric as a
/// number, and `minimal` shows a compact glyph. The raw string value is what
/// gets persisted (via `PreferencesRepository` / `SharedSnapshot`), so the
/// cases must never be renamed.
public enum MenuBarMode: String, CaseIterable, Codable, Sendable, Hashable {
    case trend
    case numeric
    case minimal
}
