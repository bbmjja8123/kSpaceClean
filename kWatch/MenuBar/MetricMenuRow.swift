import SwiftUI
import MetricsKit
import DesignSystem

/// A single icon + title + trailing value row used inside the menu-bar
/// popover. Pure presentation with no monitoring side effects.
public struct MetricMenuRow: View {
    public let title: String
    public let value: String
    public let icon: String

    /// When `true`, the row renders a lock glyph instead of the value. Locked
    /// rows fire `onTap` (typically to open the paywall); free users see the
    /// Pro-gated metrics rendered this way.
    public var isLocked: Bool

    /// Action fired when the row is clicked. Locked rows use this to present
    /// the paywall; unlocked rows keep it `nil` and render as inert text.
    public var onTap: (() -> Void)?

    public init(
        title: String,
        value: String,
        icon: String,
        isLocked: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.isLocked = isLocked
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(isLocked ? Color.textSecondary : Color.brandPrimary)
                Text(title)
                    .foregroundStyle(isLocked ? Color.textSecondary : Color.textPrimary)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text(value)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isLocked && onTap == nil)
    }
}
