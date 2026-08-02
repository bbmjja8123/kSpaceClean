import SwiftUI
import MetricsKit

/// Canvas-drawn icons used in the macOS menu bar. All rendering is
/// procedural so we don't ship binary assets and we can recolor freely.
public enum MenuBarIcons {

    /// Visual style for a menu-bar status icon.
    public enum Style: String, CaseIterable, Sendable, Codable {
        case sparkline
        case numeric
        case minimal
    }

    /// Render a 16pt-wide menu-bar status icon (the live status item).
    ///
    /// - Parameters:
    ///   - kind: The metric to draw.
    ///   - style: Visual style.
    ///   - values: Recent normalized history (0.0 - 1.0); used for sparkline style.
    ///   - currentValue: The current reading to display (used for numeric style).
    ///   - unit: Unit suffix to display (used for numeric style).
    @MainActor
    public static func statusIcon(
        kind: MetricKind,
        style: Style,
        values: [Double],
        currentValue: Double,
        unit: String
    ) -> some View {
        switch style {
        case .sparkline:
            return AnyView(SparklineIcon(values: values, accent: color(for: kind)))
        case .numeric:
            return AnyView(NumericIcon(value: currentValue, unit: unit, accent: color(for: kind)))
        case .minimal:
            return AnyView(MinimalIcon(kind: kind, accent: color(for: kind)))
        }
    }

    /// Render a small inline icon prefix used inside a metric card.
    @MainActor
    public static func cardIcon(kind: MetricKind, size: CGFloat = 14) -> some View {
        Image(systemName: symbolName(for: kind))
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color(for: kind))
    }

    /// SF Symbol fallback used by `cardIcon`.
    private static func symbolName(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer.medium"
        case .fan: return "fan.fill"
        case .battery: return "battery.100"
        }
    }

    /// Accent color used by the icon for the given metric.
    private static func color(for kind: MetricKind) -> Color {
        switch kind {
        case .cpu: return Color.brandPrimary
        case .memory: return Color.brandSecondary
        case .disk: return Color.brandAccent
        case .network: return Color.brandPrimary
        case .temperature: return Color.warning
        case .fan: return Color.brandSecondary
        case .battery: return Color.success
        }
    }
}

// MARK: - Concrete icon views

private struct SparklineIcon: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - CGFloat(v))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(accent), lineWidth: 1.5)
        }
        .frame(width: 22, height: 14)
    }
}

private struct NumericIcon: View {
    let value: Double
    let unit: String
    let accent: Color

    var body: some View {
        Text(formatted())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .monospacedDigit()
    }

    private func formatted() -> String {
        if unit.isEmpty { return String(Int(value)) }
        return "\(Int(value))\(unit)"
    }
}

private struct MinimalIcon: View {
    let kind: MetricKind
    let accent: Color

    var body: some View {
        Circle()
            .fill(accent.opacity(0.7))
            .frame(width: 6, height: 6)
    }
}
