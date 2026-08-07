import CoreGraphics
import Foundation

/// Window-frame tokens for kFresh. Views that present their own fixed-size
/// window or sheet read their size from here instead of hardcoding frame
/// values.
enum WindowFrame {
    /// Full-screen onboarding guide (FDA education flow).
    static let onboarding = CGSize(width: 560, height: 520)
    /// Settings window. Sized to fit a `TabView` with two tabs of `Form`
    /// content on macOS without scrolling or overflow.
    static let settings = CGSize(width: 480, height: 380)
    /// Pro paywall sheet width.
    static let paywallWidth: CGFloat = 420
    /// Uninstall confirmation sheet width.
    static let confirmSheetWidth: CGFloat = 480
    /// About window width.
    static let aboutWidth: CGFloat = 360
}
