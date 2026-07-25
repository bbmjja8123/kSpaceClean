import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

/// A single entry in the widget timeline representing a snapshot of kDupe state.
struct kDupeEntry: TimelineEntry {
    let date: Date
    let scanSummary: String
    let lastScanDate: Date?
    let duplicateCount: Int
    let wasteSize: Int64
}

// MARK: - Timeline Provider

/// Provides entries to the widget timeline.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> kDupeEntry {
        kDupeEntry(
            date: Date(),
            scanSummary: "Scan to find duplicates",
            lastScanDate: nil,
            duplicateCount: 0,
            wasteSize: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (kDupeEntry) -> Void) {
        let entry = kDupeEntry(
            date: Date(),
            scanSummary: "Scan to find duplicates",
            lastScanDate: nil,
            duplicateCount: 0,
            wasteSize: 0
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<kDupeEntry>) -> Void) {
        let entry = kDupeEntry(
            date: Date(),
            scanSummary: "Scan to find duplicates",
            lastScanDate: nil,
            duplicateCount: 0,
            wasteSize: 0
        )
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Widget View

/// The main view rendered inside the widget.
struct kDupeWidgetEntryView: View {
    var entry: kDupeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.accentColor)
                Text("kDupe")
                    .font(.headline)
                    .fontWeight(.bold)
            }

            Text(entry.scanSummary)
                .font(.caption)
                .foregroundColor(.secondary)

            if let lastScan = entry.lastScanDate {
                Text("Last scan: \(lastScan, style: .time)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.duplicateCount > 0 {
                HStack {
                    Text("\(entry.duplicateCount) duplicates")
                        .font(.caption)
                    Spacer()
                    Text(byteCountString(entry.wasteSize))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func byteCountString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Widget

/// The kDupe widget showing duplicate scan results at a glance.
@main
struct kDupeWidget: Widget {
    let kind: String = "app.kraftly.kdupe.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            kDupeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("kDupe")
        .description("Shows duplicate file scan results.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
