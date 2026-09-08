// kWise/Shared/WidgetFeed/RunSmartCareIntent.swift
//
// Interactive-widget AppIntent (v2.0 Phase 6).
//
// Compiled into BOTH targets: the widget extension embeds it in
// `AppIntentConfiguration`, and the app target registers it in Shortcuts.
// It deliberately does NOT touch AppGraph (the UI graph owns observable
// state) — it opens the `kwise://smartcare` deep link and the app's
// `AppCoordinator` routes it. One navigation authority, zero duplication.
import AppIntents
import AppKit

public struct RunSmartCareIntent: AppIntent {
    public static let title: LocalizedStringResource = "运行 Smart Care"
    public static let description = IntentDescription("打开 kWise 并开始一键智能清理。")
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        if let url = URL(string: "kwise://smartcare") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}
