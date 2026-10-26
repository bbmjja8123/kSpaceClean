import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

@main
struct kWiseWidgetBundle: WidgetBundle {
    // `if #available` in the bundle body is the supported pattern for mixing a
    // ControlWidget into a WidgetBundle (@WidgetBundleBuilder has
    // `buildLimitedAvailability(_: some ControlWidget)`); on OSes below the
    // gate the branch collapses to nothing. Keep the body typed `some Widget`
    // — macOS SDK's WidgetBundle.Body is `Widget`, there is no
    // WidgetBundleContent on this platform.
    var body: some Widget {
        kWiseDiskWidget()
        if #available(macOS 26.0, *) {
            KlarisQuickCleanControl()
        }
    }
}

// MARK: - Timeline Entry

struct DiskUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Provider

/// v2.0 Phase 6: reads the shared `WidgetSnapshot` JSON the app writes after
/// scans and cleanups. No snapshot (or an unknown schema version) renders
/// the neutral state — never fabricated numbers.
struct DiskUsageProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    private func currentEntry() -> DiskUsageEntry {
        DiskUsageEntry(date: Date(), snapshot: store.read())
    }

    func placeholder(in context: Context) -> DiskUsageEntry {
        DiskUsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiskUsageEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskUsageEntry>) -> Void) {
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - View

struct DiskUsageWidgetView: View {
    var entry: DiskUsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, let disk = snapshot.disk {
            content(snapshot: snapshot, disk: disk)
        } else {
            neutralState
        }
    }

    private var neutralState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("kWise", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            Text(String(localized: String.LocalizationValue("widget.state.startPrompt")))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .widgetURL(URL(string: "klaris://smartcare"))
    }

    private func content(snapshot: WidgetSnapshot, disk: WidgetSnapshot.DiskInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("kWise", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if let streak = snapshot.streak, streak.currentStreak > 0 {
                    Label("\(streak.currentStreak)", systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Gauge(value: disk.usedFraction) {
                Text(String(localized: String.LocalizationValue("widget.gauge.disk")))
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.7 ? .orange : .blue)

            HStack {
                if let last = snapshot.lastCleanup {
                    let formatted = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
                    Text(String(format: String(localized: String.LocalizationValue("widget.state.lastCleanup")), formatted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let forecast = snapshot.forecast, forecast.isReliable {
                    Text(String(format: String(localized: String.LocalizationValue("widget.state.forecast")), forecast.daysToFull))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Interactive Smart Care button (App Intent, macOS 14).
                Button(intent: RunSmartCareIntent()) {
                    Label(String(localized: String.LocalizationValue("清理")), systemImage: "wand.and.stars")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(4)
        .widgetURL(URL(string: "klaris://smartcare"))
    }
}

// MARK: - Widget

/// Interactive (macOS 14+, widget target's deployment floor): tapping the
/// Smart Care button runs `RunSmartCareIntent`, which deep-links through
/// `AppCoordinator`. The whole widget surface also deep-links via `widgetURL`.
struct kWiseDiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kraftly.klaris.widget", provider: DiskUsageProvider()) { entry in
            DiskUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: String.LocalizationValue("widget.config.displayName")))
        .description(String(localized: String.LocalizationValue("widget.config.description")))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Control Center Control (macOS 26+)

/// 控制中心快捷回收（Task 11）。ControlWidget API 在 macOS 上是 26.0+
/// （iOS 18 同代，但 Mac 端 Controls 随 macOS Tahoe 26 才进入 Control
/// Center——SDK swiftinterface 标注 `@available(iOS 18.0, macOS 26.0, *)`，
/// 任务书里「macOS 15+」系同代版本号误推）。以 @available 门控，26 以下
/// 用户照常只用桌面 widget。
///
/// Action reuses `RunSmartCareIntent` (the same AppIntent the interactive
/// desktop widget button uses): it deep-links `klaris://smartcare` and the
/// app's `AppCoordinator` routes it onto the anatomy canvas. One navigation
/// authority, zero duplication.
///
/// Label copy lives in `Widgets/Localizable.xcstrings` — the widget appex
/// does NOT bundle the app's `Resources/Localizable.xcstrings`, so a
/// widget-local single-key catalog is what actually resolves in Control
/// Center (the key is mirrored into the app catalog for audit parity).
@available(macOS 26.0, *)
struct KlarisQuickCleanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // On macOS the configuration modifiers (displayName/description) live
        // on `ControlWidgetConfiguration`, so the button template must be
        // wrapped in a `StaticControlConfiguration` — the bare-button chain
        // from the task brief does not compile on this SDK.
        StaticControlConfiguration(kind: "app.kraftly.klaris.control.quickclean") {
            ControlWidgetButton(action: RunSmartCareIntent()) {
                Label(String(localized: String.LocalizationValue("widget.control.quickClean")), systemImage: "sparkles")
            }
        }
        .displayName("Klaris")
        .description(String(localized: String.LocalizationValue("widget.control.quickCleanDescription")))
    }
}

#Preview("Small", as: .systemSmall) {
    kWiseDiskWidget()
} timeline: {
    DiskUsageEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            disk: .init(usedBytes: 380_000_000_000, totalBytes: 494_384_712_704),
            lastCleanup: .init(freedBytes: 3_200_000_000, date: .now),
            streak: .init(currentStreak: 3, longestStreak: 9)
        )
    )
}
