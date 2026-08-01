import SwiftUI

/// Transient undo toast shown after a successful uninstall.
///
/// The toast does NOT auto-dismiss — it persists until the user clicks
/// "撤销" or the host view swaps the sheet context. A 10-second countdown
/// is rendered into the undo button label so the user sees the affordance
/// decay, but the parent (``AppDetailView``) drives the actual removal via
/// the `onUndo` closure.
struct UninstallToast: View {
    /// Captured uninstall context the host view passes in. `Identifiable`
    /// so SwiftUI can drive a stable identity across body re-evaluations.
    struct State: Identifiable, Equatable {
        let id = UUID()
        let recordID: UUID
        let appName: String
        let appSize: Int64
    }

    let state: State
    let onUndo: () -> Void

    /// Seconds left on the countdown. Decrements once per second while the
    /// toast is on screen; the host view can dismiss the toast at any time
    /// regardless of the remaining count.
    ///
    /// Qualified as `SwiftUI.State` because the nested `State` payload type
    /// (the Identifiable snapshot the host passes in) would otherwise shadow
    /// the property wrapper in this scope.
    @SwiftUI.State private var secondsRemaining = 10

    /// Drives the countdown. `in: .common` so it ticks against user
    /// interaction (scroll, drag) instead of being suppressed.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(state: State, onUndo: @escaping () -> Void) {
        self.state = state
        self.onUndo = onUndo
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
            Text("已卸载 \(state.appName) (\(state.appSize.kbFormatted))")
                .font(AppFont.body)
            Spacer()
            Button("撤销 (\(secondsRemaining))", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(AppSpacing.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(AppSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onReceive(timer) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
        .animation(.easeInOut(duration: KFAnimation.durationNormal), value: secondsRemaining)
    }
}

// MARK: - Local formatting helper (mirror of UninstallConfirmSheet)
//
// File-local on purpose: keeps the formatter policy contained to the
// uninstall-flow sheets and avoids a global `Int64` extension that other
// modules could accidentally lean on with divergent style.

private extension Int64 {
    var kbFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
