import SwiftUI

/// Transient undo toast shown after a successful uninstall.
///
/// The toast does NOT auto-dismiss — it persists until the user clicks
/// "撤销" or the host view swaps the sheet context. A 10-second countdown
/// is rendered into the undo button label so the user sees the affordance
/// decay, but the parent (``AppDetailView``) drives the actual removal via
/// the `onUndo` closure.
///
/// Wave 2 P1 (G-KF-04): the headline now reads "已释放 X GB" so the
/// instant after the user clicks uninstall, they see the cleanup's
/// concrete payoff. Matches CleanMyMac X / BuhoCleaner / DaisyDisk's
/// post-cleanup counter — a key driver of "this app is doing real work"
/// perception. ``State`` carries ``totalFreedBytes`` (= app size + every
/// residue actually deleted) so the toast never has to re-derive it.
struct UninstallToast: View {
    /// Captured uninstall context the host view passes in. `Identifiable`
    /// so SwiftUI can drive a stable identity across body re-evaluations.
    struct State: Identifiable, Equatable {
        let id = UUID()
        let recordID: UUID
        let appName: String
        let appSize: Int64
        /// App body + sum of deleted residues, in bytes. Equal to
        /// ``appSize`` when the user unchecked every residue bucket.
        let totalFreedBytes: Int64

        init(recordID: UUID, appName: String, appSize: Int64, totalFreedBytes: Int64) {
            self.recordID = recordID
            self.appName = appName
            self.appSize = appSize
            self.totalFreedBytes = totalFreedBytes
        }

        /// Convenience init that defaults ``totalFreedBytes`` to
        /// ``appSize`` — the legacy "app body only" case. Kept so the
        /// existing call sites and tests that don't know about residue
        /// totals still compile after the v1.x-B I-4 rollout.
        init(recordID: UUID, appName: String, appSize: Int64) {
            self.init(recordID: recordID,
                      appName: appName,
                      appSize: appSize,
                      totalFreedBytes: appSize)
        }
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
                .font(AppFont.title3)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("已释放 \(state.totalFreedBytes.kbFormatted)")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textPrimary)
                Text(state.appName)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("撤销 (\(secondsRemaining))", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(AppSpacing.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(AppSpacing.md)
        // The freed-bytes count is the perceived payoff — a small
        // bounce draws the eye to it for half a second after the toast
        // appears, then settles. Wave 2 P1 polish.
        .scaleEffect(justAppeared ? 1.04 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: justAppeared)
        .onAppear {
            justAppeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                justAppeared = false
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onReceive(timer) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
        .animation(.easeInOut(duration: KFAnimation.durationNormal), value: secondsRemaining)
    }

    /// Drives the brief entry bounce. Resets to `false` 150 ms after
    /// appearance so the spring settles into its resting scale.
    @SwiftUI.State private var justAppeared = false
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
