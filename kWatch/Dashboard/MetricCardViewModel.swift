import Foundation
import MetricsKit

/// Display color token for a dashboard metric card.
///
/// Using a custom enum rather than SwiftUI's `Color` keeps the view model
/// fully `Equatable` and `Sendable`. The view layer resolves the token
/// to a concrete `Color`.
public enum CardColor: String, Equatable, Sendable {
    case blue, green, orange, purple, red, yellow, gray
}

/// Pure formatting and display metadata for one dashboard metric card.
///
/// All text formatting, icon selection, and color mapping are computed eagerly
/// from the raw metric values so that views never contain formatting logic.
/// The type is `Equatable` so SwiftUI can diff card collections efficiently.
public struct MetricCardViewModel: Identifiable, Equatable {
    // MARK: - Identity

    public let id: MetricKind
    public let kind: MetricKind

    // MARK: - Display properties

    /// Human-readable title (e.g. "CPU", "Memory").
    public let title: String

    /// Formatted primary value (e.g. "42%", "1.2 GB", "--").
    public let displayValue: String

    /// Contextual subtitle (e.g. "System CPU", "Pro Feature", "SMC unavailable").
    public let subtitle: String

    /// SF Symbol name for the card icon.
    public let icon: String

    /// Color token the view should use for accent/icon.
    public let cardColor: CardColor

    // MARK: - Lock / unavailable state

    /// Whether this card represents a Pro-gated metric whose hardware IS
    /// available. Locked cards imply the user would benefit from upgrading.
    public let isLocked: Bool

    /// Concise explanation shown when the card is locked.
    public let lockDescription: String

    /// Whether the underlying sensor/hardware is unavailable on this Mac.
    /// `true` means even a Pro purchase cannot enable it.
    public let isUnavailable: Bool

    /// Reason string from `MetricAvailability` (empty when the sensor works).
    public let unavailableDescription: String

    // MARK: - Init

    /// Build a fully formatted card view model from raw metric data.
    ///
    /// - Parameters:
    ///   - kind: The metric kind (determines title, icon, color, and free/Pro
    ///     classification).
    ///   - value: The current reading.
    ///   - availability: Whether the sensor is available on this hardware.
    ///   - isPro: Whether the current user holds a Pro entitlement.
    public init(
        kind: MetricKind,
        value: MetricValue,
        availability: MetricAvailability,
        isPro: Bool
    ) {
        self.id = kind
        self.kind = kind
        self.title = Self.title(for: kind)

        // Derive availability state.
        let hardwareUnavailable: Bool
        let reason: String
        switch availability {
        case .available:
            hardwareUnavailable = false
            reason = ""
        case .unsupported(let r):
            hardwareUnavailable = true
            reason = r
        case .unavailable(let r):
            hardwareUnavailable = true
            reason = r
        }

        let isProFeature: Bool
        switch kind {
        case .temperature, .fan, .battery, .gpu: isProFeature = true
        case .cpu, .memory, .disk, .network: isProFeature = false
        }

        // Lock state: Pro-gated features whose hardware is available to the user.
        isLocked = isProFeature && !hardwareUnavailable && !isPro
        isUnavailable = hardwareUnavailable
        unavailableDescription = reason

        // Value
        displayValue = Self.format(value)

        // Subtitle
        if hardwareUnavailable {
            subtitle = reason.isEmpty ? String(localized: "Unavailable") : reason
        } else if isLocked {
            subtitle = String(localized: "Pro Feature")
        } else {
            subtitle = Self.defaultSubtitle(for: kind)
        }

        // Icon
        if hardwareUnavailable {
            icon = "questionmark.circle"
        } else if isLocked {
            icon = "lock.fill"
        } else {
            icon = Self.defaultIcon(for: kind)
        }

        // Color
        if hardwareUnavailable || isLocked {
            cardColor = .gray
        } else {
            cardColor = Self.defaultCardColor(for: kind)
        }

        // Lock description
        lockDescription = String(localized: "Upgrade to Pro to monitor \(kind.rawValue).")
    }

    // MARK: - Equatable

    public static func == (lhs: MetricCardViewModel, rhs: MetricCardViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.displayValue == rhs.displayValue &&
        lhs.subtitle == rhs.subtitle &&
        lhs.icon == rhs.icon &&
        lhs.cardColor == rhs.cardColor &&
        lhs.isLocked == rhs.isLocked &&
        lhs.isUnavailable == rhs.isUnavailable &&
        lhs.lockDescription == rhs.lockDescription &&
        lhs.unavailableDescription == rhs.unavailableDescription
    }

    // MARK: - Formatting helpers

    private static func title(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return String(localized: "CPU")
        case .memory: return String(localized: "Memory")
        case .disk: return String(localized: "Disk")
        case .network: return String(localized: "Network")
        case .temperature: return String(localized: "Temperature")
        case .fan: return String(localized: "Fan")
        case .battery: return String(localized: "Battery")
        case .gpu: return String(localized: "GPU")
        }
    }

    private static func defaultSubtitle(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return String(localized: "System CPU")
        case .memory: return String(localized: "Memory Pressure")
        case .disk: return String(localized: "Disk Usage")
        case .network: return String(localized: "Network Traffic")
        case .temperature: return String(localized: "System Temperature")
        case .fan: return String(localized: "Fan Speed")
        case .battery: return String(localized: "Battery Charge")
        case .gpu: return String(localized: "GPU Temperature")
        }
    }

    private static func defaultIcon(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer"
        case .fan: return "fan"
        case .battery: return "battery.100"
        case .gpu: return "display"
        }
    }

    private static func defaultCardColor(for kind: MetricKind) -> CardColor {
        switch kind {
        case .cpu: return .blue
        case .memory: return .green
        case .disk: return .orange
        case .network: return .purple
        case .temperature: return .red
        case .fan: return .yellow
        case .battery: return .green
        case .gpu: return .purple
        }
    }

    /// Format any `MetricValue` to a concise display string.
    private static func format(_ value: MetricValue) -> String {
        switch value {
        case .percentage(let v):
            return "\(Int(round(v)))%"
        case .bytes(let b):
            return MetricCardViewModel.formatBytes(b)
        case .bytesPerSecond(let b):
            return "\(MetricCardViewModel.formatBytes(b))/s"
        case .degreesCelsius(let c):
            return "\(Int(round(c)))°C"
        case .revolutionsPerMinute(let r):
            return "\(Int(round(r))) RPM"
        case .volts(let v):
            return String(format: "%.2f V", v)
        case .text(let t):
            return t
        case .unavailable:
            return String(localized: "N/A")
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unitIndex])
    }
}
