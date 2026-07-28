// kSpaceClean/Features/Common/DesignSystem/Accessibility.swift
import SwiftUI

/// Centralized accessors for macOS accessibility settings used by kSpaceClean.
///
/// The accessors wrap `NSWorkspace` so callers do not need to import AppKit
/// directly. They are read on the main actor because `NSWorkspace` APIs
/// require it; consumers can therefore call them from any SwiftUI view body
/// without additional isolation work.
///
/// `dynamicTypeSize` is intentionally not exposed as a static accessor:
/// `@Environment` property wrappers cannot be applied to `static` storage,
/// and reading the current dynamic type size is a per-view concern. Views
/// should declare `@Environment(\.dynamicTypeSize) private var dynamicTypeSize`
/// directly and consult it where layout is computed.
enum AccessibilitySettings {

    /// `true` when VoiceOver is currently running on the user's Mac.
    ///
    /// Use this to add richer spoken hints, slow down animations, or surface
    /// an accessibility-only banner when the user cannot see the UI.
    static var voiceOverEnabled: Bool {
        NSWorkspace.shared.isVoiceOverEnabled
    }

    /// `true` when the user has enabled "Reduce motion" in
    /// System Settings → Accessibility → Display.
    ///
    /// The design system consults this flag (transitively, via
    /// ``Animation/accessibleDefault(_:)``) to swap expressive animations
    /// for short linear fades so motion-sensitive users are not subjected
    /// to parallax, zooms, or large translation effects.
    static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `true` when the user has enabled "Increase contrast" in
    /// System Settings → Accessibility → Display.
    ///
    /// Components can use this to pick higher-contrast color tokens
    /// (e.g. textPrimary over bgCanvas instead of textSecondary).
    static var increaseContrastEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}

extension Animation {
    /// Returns `base` when motion is allowed, or a short linear fade when
    /// the user has "Reduce motion" enabled.
    ///
    /// Use this anywhere an animation is supplied to a view modifier so
    /// motion-sensitive users automatically get a calmer experience:
    ///
    /// ```swift
    /// withAnimation(.accessibleDefault(.easeInOut(duration: 0.25))) {
    ///     isExpanded.toggle()
    /// }
    /// ```
    ///
    /// - Parameter base: The animation to use when motion is allowed.
    /// - Returns: `base` unchanged when ``AccessibilitySettings/reduceMotionEnabled``
    ///   is `false`; otherwise a 0.1s linear animation.
    static func accessibleDefault(_ base: Animation) -> Animation {
        AccessibilitySettings.reduceMotionEnabled ? .linear(duration: 0.1) : base
    }
}