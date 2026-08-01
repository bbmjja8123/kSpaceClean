import WidgetKit
import SwiftUI

// MARK: - Quick Uninstall Entry

struct QuickFreshEntry: TimelineEntry {
    let date: Date
    let recentApps: [(name: String, bundleID: String)]
}

// MARK: - Timeline Provider

struct QuickFreshProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickFreshEntry {
        QuickFreshEntry(date: Date(), recentApps: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickFreshEntry) -> Void) {
        completion(QuickFreshEntry(date: Date(), recentApps: [("TestApp", "com.example.test")]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickFreshEntry>) -> Void) {
        Task {
            let scanner = ResidueScanner()
            let apps = await scanner.scanAll()
            let recent = apps.sorted { $0.displayName < $1.displayName }
                .prefix(3)
                .map { (name: $0.displayName, bundleID: $0.bundleID) }
            let entry = QuickFreshEntry(date: Date(), recentApps: Array(recent))
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
            completion(timeline)
        }
    }
}

// MARK: - Entry View

struct QuickFreshWidgetEntryView: View {
    var entry: QuickFreshEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("快速卸载", systemImage: "trash")
                .font(.headline)

            if entry.recentApps.isEmpty {
                Text("暂无应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.recentApps.indices, id: \.self) { i in
                    HStack {
                        Image(systemName: "app.badge")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.recentApps[i].name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct QuickFreshWidget: Widget {
    let kind = "app.kraftly.kfresh.widget.quick"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickFreshProvider()) { entry in
            QuickFreshWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("快速卸载")
        .description("快速访问最近安装的应用")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
