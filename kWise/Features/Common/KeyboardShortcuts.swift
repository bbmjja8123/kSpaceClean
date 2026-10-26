// kWise/Features/Common/KeyboardShortcuts.swift
import SwiftUI

/// View extension that attaches the standard scan-related keyboard shortcuts
/// used throughout kWise v1.0.
///
/// Two shortcuts are wired up:
///
/// - `⌘N`  New scan — clears current results and starts a fresh scan.
/// - `⌘R`  Rescan — re-runs the scan with the same root paths and filters.
///
/// On macOS 13 the only `keyboardShortcut` overload exposed by the SDK is
/// `keyboardShortcut(_:modifiers:)` (no closure), which still requires a
/// focusable responder (e.g. a Button) in the responder chain to fire. We
/// therefore install two hidden, frame-zero Buttons whose actions are the
/// supplied closures; the visible toolbar buttons remain the primary affordance.
///
/// On macOS 14+ the same hidden-Button approach continues to work, and we
/// keep using it so the behaviour is identical across supported OS
/// versions. A `Group` wrapper lets us conditionally emit the hidden
/// controls without changing the caller's shape.
///
/// ## Usage
///
/// ```swift
/// RootView()
///     .scanKeyboardShortcuts(
///         onNewScan:  { viewModel.startNewScan() },
///         onRescan:   { viewModel.rescan() }
///     )
/// ```
///
/// - Parameters:
///   - onNewScan: Closure invoked when the user presses `⌘N`.
///   - onRescan:  Closure invoked when the user presses `⌘R`.
extension View {
    func scanKeyboardShortcuts(
        onNewScan: @escaping () -> Void,
        onRescan: @escaping () -> Void
    ) -> some View {
        self.background {
            // Hidden focusable buttons used as shortcut targets.
            // `keyboardShortcut(_:modifiers:)` requires a real Button in the
            // responder chain so the shortcut can be discovered by the menu
            // system and triggered programmatically.
            HStack(spacing: 0) {
                Button(action: onNewScan) {
                    EmptyView()
                }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                Button(action: onRescan) {
                    EmptyView()
                }
                .keyboardShortcut("r", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }

    /// Rail navigation + settings keyboard shortcuts (Task 4, feature sprint).
    ///
    /// Four shortcuts are wired up:
    ///
    /// - `⌘1`  Anatomy — the single-canvas home screen.
    /// - `⌘2`  History — the narrative timeline.
    /// - `⌘3`  Settings.
    /// - `⌘,`  Settings — the macOS-conventional "open settings" chord. The
    ///   app deliberately ships no `Settings` scene (P2 IA: settings is a
    ///   rail face), so the conventional chord binds to the rail item
    ///   instead of being silently dead.
    ///
    /// Same hidden-Button technique as ``scanKeyboardShortcuts(onNewScan:
    /// onRescan:)`` — `keyboardShortcut(_:modifiers:)` needs a real Button
    /// in the responder chain, so we install frame-zero, invisible,
    /// accessibility-hidden buttons whose actions are the supplied closures.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// RootView()
    ///     .railKeyboardShortcuts(
    ///         onAnatomy:  { appState.navigation = .anatomy },
    ///         onHistory:  { appState.navigation = .history },
    ///         onSettings: { appState.navigation = .settings }
    ///     )
    /// ```
    ///
    /// - Parameters:
    ///   - onAnatomy: Closure invoked when the user presses `⌘1`.
    ///   - onHistory: Closure invoked when the user presses `⌘2`.
    ///   - onSettings: Closure invoked when the user presses `⌘3` or `⌘,`.
    func railKeyboardShortcuts(
        onAnatomy: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> some View {
        self.background {
            HStack(spacing: 0) {
                Button(action: onAnatomy) {
                    EmptyView()
                }
                .keyboardShortcut("1", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                Button(action: onHistory) {
                    EmptyView()
                }
                .keyboardShortcut("2", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                Button(action: onSettings) {
                    EmptyView()
                }
                .keyboardShortcut("3", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

                // ⌘, — conventional settings chord, bound to the rail item
                // (no Settings scene exists; see DocC above).
                Button(action: onSettings) {
                    EmptyView()
                }
                .keyboardShortcut(",", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }
}
