// kWise/Features/Cleanup/Engine/CleanupNotificationSink.swift
//
// Post-cleanup local notification (v2.0 Phase 1).
//
// The Settings toggle 「清理后通知」 used to be `.constant(true)` — nothing
// existed behind it. This sink is the implementation: it observes the same
// `CleanupEvent` stream the quota ledger uses and posts one local
// notification per finished run. Permission is requested lazily from the
// Settings toggle, never at first launch.
import Foundation
import UserNotifications

public struct CleanupNotificationSink: CleanupEventSink {

    public init() {}

    /// Ask for notification permission. Called from the Settings toggle the
    /// moment the user opts in.
    @MainActor
    public static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.ui.error("Notification authorization failed: \(error.localizedDescription)")
            }
            // Denial is respected silently — the toggle stays on but macOS
            // suppresses delivery; no nagging (C-5).
        }
    }

    public func cleanupDidFinish(_ event: CleanupEvent) async {
        guard UserPreferences.load().notifyAfterCleanup else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "清理完成")
        let formatted = ByteCountFormatter.string(fromByteCount: event.freedBytes, countStyle: .file)
        content.body = String(localized: "本次已释放 \(formatted)")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kwise.cleanup.\(event.date.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
