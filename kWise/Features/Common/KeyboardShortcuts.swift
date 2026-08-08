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
/// ScanResultsView()
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
}
