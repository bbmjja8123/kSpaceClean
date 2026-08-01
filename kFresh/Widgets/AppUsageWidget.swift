import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct AppUsageEntry: TimelineEntry {
    let date: Date
    let topApps: [(name: String, size: String)]
}

// MARK: - Timeline Provider

struct AppUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> AppUsageEntry {
        AppUsageEntry(date: Date(), topApps: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (AppUsageEntry) -> Void) {
        completion(AppUsageEntry(date: Date(), topApps: [("Xcode", "12.5 GB")]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AppUsageEntry>) -> Void) {
        Task {
            let scanner = ResidueScanner()
            let apps = await scanner.scanAll()
            let top = apps.sorted { $0.sizeBytes > $1.sizeBytes }
                .prefix(4)
                .map { (name: $0.displayName, size: $0.sizeFormatted) }
            let entry = AppUsageEntry(date: Date(), topApps: Array(top))
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
            completion(timeline)
        }
    }
}

// MARK: - Entry View

struct AppUsageWidgetEntryView: View {
    var entry: AppUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("磁盘占用 Top", systemImage: "trash.circle")
                .font(.headline)

            if entry.topApps.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.topApps.indices, id: \.self) { i in
                    HStack {
                        Text("\(i + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.topApps[i].name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.topApps[i].size)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct AppUsageWidget: Widget {
    let kind = "app.kraftly.kfresh.widget.usage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AppUsageProvider()) { entry in
            AppUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("磁盘占用")
        .description("显示占用最大的 App")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
