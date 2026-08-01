import SwiftUI
import MetricsKit
import DesignSystem

/// A single icon + title + trailing value row used inside the menu-bar
/// popover. Pure presentation with no monitoring side effects.
public struct MetricMenuRow: View {
    public let title: String
    public let value: String
    public let icon: String

    public init(title: String, value: String, icon: String) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    public var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
        }
    }
}
