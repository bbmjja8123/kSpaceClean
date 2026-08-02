import Foundation
import MetricsKit
import DesignSystem

/// User-configurable per-metric menu-bar icon style. Each metric can
/// independently use sparkline, numeric, or minimal. Default: sparkline.
public struct MenuBarIconTheme: Codable, Equatable, Sendable {
    public var styles: [String: MenuBarIcons.Style]   // raw MetricKind value → Style

    public init(styles: [String: MenuBarIcons.Style] = [:]) {
        self.styles = styles
    }

    public func style(for kind: MetricKind) -> MenuBarIcons.Style {
        styles[kind.rawValue] ?? .sparkline
    }

    public mutating func set(_ style: MenuBarIcons.Style, for kind: MetricKind) {
        styles[kind.rawValue] = style
    }

    /// All metrics default to sparkline style.
    public static let `default` = MenuBarIconTheme()
}
