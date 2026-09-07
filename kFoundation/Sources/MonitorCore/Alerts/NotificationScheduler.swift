import Foundation
import UserNotifications
import MetricsKit

/// A Sendable snapshot of a scheduled local notification, used by the test seam.
public struct ScheduledNotificationInfo: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

/// Protocol so the view model and tests can work with any notification scheduler.
public protocol NotificationSchedulerProtocol: Sendable {
    /// The current authorization status from `UNUserNotificationCenter`.
    var authorizationStatus: UNAuthorizationStatus { get async }

    /// Request alert/sound permission. Never blocks the UI — failures are swallowed.
    func requestAuthorization() async

    /// Schedule a local notification for a triggered alert. Does nothing when
    /// permission has not been granted (`.notDetermined` or `.denied`).
    func schedule(alert: MetricAlert, value: MetricValue) async

    /// Remove any pending notification for the given alert id.
    func removePending(alertID: UUID) async
}

/// Production scheduler backed by `UNUserNotificationCenter`.
///
/// Sandbox-compatible: local notifications require no special entitlement.
/// macOS 13+ uses the modern `UNUserNotificationCenter` API exclusively.
public actor NotificationScheduler: NotificationSchedulerProtocol {
    private let center: UNUserNotificationCenter
    private let overriddenAuthStatus: UNAuthorizationStatus? // test injection
    private var onSchedule: (@Sendable (ScheduledNotificationInfo) -> Void)?

    public init(
        center: UNUserNotificationCenter = .current(),
        overriddenAuthStatus: UNAuthorizationStatus? = nil
    ) {
        self.center = center
        self.overriddenAuthStatus = overriddenAuthStatus
    }

    // MARK: - Test seam

    /// When set, every `schedule` call invokes this handler instead of
    /// calling `UNUserNotificationCenter.add(_:)`.
    public func setOnSchedule(_ handler: (@Sendable (ScheduledNotificationInfo) -> Void)?) {
        onSchedule = handler
    }

    // MARK: - NotificationSchedulerProtocol

    public var authorizationStatus: UNAuthorizationStatus {
        get async {
            if let overridden = overriddenAuthStatus {
                return overridden
            }
            return await withCheckedContinuation { continuation in
                center.getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }
    }

    public func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Swallowed intentionally — never block the UI awaiting permission.
        }
    }

    public func schedule(alert: MetricAlert, value: MetricValue) async {
        let status = await authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "kWatch Alert"
        content.body = Self.body(for: alert, value: value)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        )

        let info = ScheduledNotificationInfo(
            identifier: request.identifier,
            title: content.title,
            body: content.body
        )

        if let handler = onSchedule {
            handler(info)
        } else {
            do {
                try await center.add(request)
            } catch {
                // Swallowed — local notifications are best-effort.
            }
        }
    }

    public func removePending(alertID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [alertID.uuidString])
    }

    // MARK: - Formatting helpers

    private static func body(for alert: MetricAlert, value: MetricValue) -> String {
        let kindName = alert.kind.rawValue.capitalized
        let direction = alert.op == .above ? "above" : "below"
        let thresholdStr = Self.formatThreshold(alert.threshold, for: alert.kind)
        let valueStr = Self.formatMetricValue(value)
        return "\(kindName) is \(direction) \(thresholdStr): \(valueStr)"
    }

    private static func formatThreshold(_ threshold: Double, for kind: MetricKind) -> String {
        switch kind {
        case .cpu, .memory, .disk, .battery:
            return "\(Int(threshold))%"
        case .network:
            return ByteCountFormatter.string(fromByteCount: Int64(threshold), countStyle: .file) + "/s"
        case .temperature, .gpu:
            return "\(Int(threshold))°C"
        case .fan:
            return "\(Int(threshold)) RPM"
        }
    }

    private static func formatMetricValue(_ value: MetricValue) -> String {
        switch value {
        case let .percentage(v):
            return "\(Int(v))%"
        case let .bytes(v):
            return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
        case let .bytesPerSecond(v):
            return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file) + "/s"
        case let .degreesCelsius(v):
            return "\(Int(v))°C"
        case let .revolutionsPerMinute(v):
            return "\(Int(v)) RPM"
        case let .volts(v):
            return String(format: "%.2fV", v)
        case let .text(v):
            return v
        case .unavailable:
            return "N/A"
        }
    }
}
