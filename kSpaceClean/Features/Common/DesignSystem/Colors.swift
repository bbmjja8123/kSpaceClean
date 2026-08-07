// kSpaceClean/Features/Common/DesignSystem/Colors.swift
import SwiftUI

/// Design-system color tokens for kSpaceClean.
///
/// Two layers:
/// - Neutral surfaces (background, text, divider) for the app shell and lists.
/// - Semantic brand/risk/state colors that components consume by intent
///   (e.g. ``bgCanvas``) rather than by raw value.
extension Color {
    // Background
    /// Canvas background — primary app background behind all surfaces.
    static let bgCanvas = Color(red: 0.059, green: 0.063, blue: 0.071)        // #0F1012
    /// Surface background — secondary surface for cards, sidebars, and grouped content.
    static let bgSurface = Color(red: 0.110, green: 0.110, blue: 0.118)       // #1C1C1E
    /// Elevated surface — modals, popovers, and floating panels that sit above `bgSurface`.
    static let bgElevated = Color(red: 0.173, green: 0.173, blue: 0.180)      // #2C2C2E
    /// Divider — hairline separators between rows, sections, and list items.
    static let divider = Color(red: 0.227, green: 0.227, blue: 0.235)         // #3A3A3C

    // Text
    /// Primary text — highest-emphasis labels and headings.
    static let textPrimary = Color.white                                       // #FFFFFF
    /// Secondary text — supporting copy, metadata, less prominent labels.
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.600)   // #999999
    /// Tertiary text — captions, helper text, low-priority metadata.
    static let textTertiary = Color(red: 0.400, green: 0.400, blue: 0.400)    // #666666
    /// Disabled text — placeholder and non-interactive controls. Reuses divider tone.
    static let textDisabled = Color(red: 0.227, green: 0.227, blue: 0.235)   // #3A3A3C

    // Brand
    /// Brand primary — interactive brand accent for primary buttons and links.
    static let brandPrimary = Color(red: 0.039, green: 0.518, blue: 1.000)    // #0A84FF
    /// Brand accent — secondary brand accent used for highlights and badges.
    static let brandAccent = Color(red: 0.353, green: 0.784, blue: 0.980)     // #5AC8FA

    // Risk (4 levels)
    /// Risk: recommended — safe to clean, regenerated automatically. Default selected.
    static let riskRecommended = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    /// Risk: optional — limited effect, no side effects.
    static let riskOptional = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    /// Risk: caution — minor recovery cost (re-login / rebuild cache).
    static let riskCaution = Color(red: 1.000, green: 0.584, blue: 0.000)     // #FF9500
    /// Risk: dangerous — affects running apps or may cause data loss.
    static let riskDangerous = Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30

    // State
    /// State: warning — transient alerts and toasts about pending actions.
    static let stateWarning = Color(red: 1.000, green: 0.800, blue: 0.000)    // #FFCC00
    /// State: success — confirmation feedback for completed actions.
    static let stateSuccess = Color(red: 0.204, green: 0.780, blue: 0.349)    // #34C759
    /// State: error — destructive feedback and failure toasts.
    static let stateError = Color(red: 1.000, green: 0.231, blue: 0.188)      // #FF3B30
    /// State: scanning — animated/progressing indicator while a scan is running.
    static let stateScanning = Color(red: 0.039, green: 0.518, blue: 1.000)   // #0A84FF
}
