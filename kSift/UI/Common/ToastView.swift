import SwiftUI
import DesignSystem

/// A non-blocking success/info banner shown at the top of a screen.
///
/// Replaces modal alerts for outcomes the user does not need to acknowledge
/// (e.g. "cleanup finished"): the result stays readable while the list behind
/// it remains interactive. Presented via ``SwiftUI/View/toast(isPresented:autoDismissAfter:content:)``,
/// which owns the auto-dismiss timer and the slide-in transition.
struct ToastView: View {
    let title: String
    var subtitle: String?
    let icon: String
    /// Optional trailing call-to-action (e.g. "Open Vault"). Hidden when
    /// either the label or the handler is missing.
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFont.title2)
                    .foregroundColor(.success)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppFont.title3)
                        .foregroundColor(.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.callout)
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: AppSpacing.md)

                if let actionTitle, let onAction {
                    Button(actionTitle) {
                        onAction()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss", comment: "Toast close button"))
            }
            .padding(AppSpacing.lg)
        }
        .appShadow(AppShadow.md)
        .frame(maxWidth: 520)
    }
}

extension View {
    /// Overlays `content` at the top edge while `isPresented` is true, sliding
    /// it in and dismissing it automatically after `autoDismissAfter` seconds.
    ///
    /// The timer is keyed on `isPresented`, so re-presenting a toast restarts
    /// the countdown instead of inheriting the previous one. Dismissing by hand
    /// (the toast's close button) simply flips the binding, which cancels the
    /// pending `Task` through `.task(id:)`.
    func toast<Content: View>(
        isPresented: Binding<Bool>,
        autoDismissAfter seconds: Double = 3,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(alignment: .top) {
            ZStack {
                if isPresented.wrappedValue {
                    content()
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(toastAnimation, value: isPresented.wrappedValue)
        }
        .task(id: isPresented.wrappedValue) {
            guard isPresented.wrappedValue else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isPresented.wrappedValue = false
        }
    }

    /// `.smooth` on macOS 14+, `.easeInOut` on macOS 13 — both at the shared
    /// 350 ms `KFAnimation.durationNormal`.
    private var toastAnimation: Animation {
        if #available(macOS 14.0, *) {
            return KFAnimation.smooth
        }
        return KFAnimation.easeInOut
    }
}
