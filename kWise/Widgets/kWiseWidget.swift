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
    let usedFraction: Double // 0...1, from the shared App Group snapshot
}

// MARK: - Provider

/// Phase 0 stub: reads the shared App Group snapshot when present, otherwise
/// renders a neutral state. Phase 6 replaces this with the real BridgeKit feed.
struct DiskUsageProvider: TimelineProvider {
    private static let suiteName = "group.app.kraftly.sclean"

    private func currentEntry() -> DiskUsageEntry {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        let used = defaults?.double(forKey: "snapshot.usedFraction") ?? 0
        return DiskUsageEntry(date: Date(), usedFraction: min(max(used, 0), 1))
    }

    func placeholder(in context: Context) -> DiskUsageEntry {
        DiskUsageEntry(date: Date(), usedFraction: 0)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("kWise", systemImage: "sparkles")
                .font(.headline)
            Gauge(value: entry.usedFraction) {
                Text("Disk")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            if entry.usedFraction == 0 {
                Text("Open kWise to scan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}

// MARK: - Widget

struct kWiseDiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kraftly.sclean.widget", provider: DiskUsageProvider()) { entry in
            DiskUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Disk Usage")
        .description("Check your Mac storage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Small", as: .systemSmall) {
    kWiseDiskWidget()
} timeline: {
    DiskUsageEntry(date: .now, usedFraction: 0.62)
}
