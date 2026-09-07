import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

@main
struct kWiseWidgetBundle: WidgetBundle {
    var body: some Widget {
        kWiseDiskWidget()
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
            Text("打开 kWise 开始首次扫描")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .widgetURL(URL(string: "kwise://smartcare"))
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
                Text("磁盘")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.7 ? .orange : .blue)

            HStack {
                if let last = snapshot.lastCleanup {
                    let formatted = ByteCountFormatter.string(fromByteCount: last.freedBytes, countStyle: .file)
                    Text("上次清理 \(formatted)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let forecast = snapshot.forecast, forecast.isReliable {
                    Text("预计 \(forecast.daysToFull) 天后磁盘将满")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Interactive Smart Care button (App Intent, macOS 14).
                Button(intent: RunSmartCareIntent()) {
                    Label("清理", systemImage: "wand.and.stars")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(4)
        .widgetURL(URL(string: "kwise://smartcare"))
    }
}

// MARK: - Widget

/// Interactive (macOS 14+, widget target's deployment floor): tapping the
/// Smart Care button runs `RunSmartCareIntent`, which deep-links through
/// `AppCoordinator`. The whole widget surface also deep-links via `widgetURL`.
struct kWiseDiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kraftly.sclean.widget", provider: DiskUsageProvider()) { entry in
            DiskUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("磁盘占用")
        .description("查看 Mac 存储占用、上次清理与连续打卡。点击即可运行 Smart Care。")
        .supportedFamilies([.systemSmall, .systemMedium])
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
