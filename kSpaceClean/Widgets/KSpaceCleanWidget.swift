import WidgetKit
import SwiftUI

// MARK: - Widget Bundle

struct KSpaceCleanWidgetBundle: WidgetBundle {
    var body: some Widget {
        KSpaceCleanWidget()
    }
}

// MARK: - Timeline Entry

struct DiskUsageEntry: TimelineEntry {
    let date: Date
    let usedBytes: Int64
    let totalBytes: Int64
    let categoryBreakdown: [(String, Int64)]  // (categoryName, bytes)
}

// MARK: - Provider

struct Provider: TimelineProvider {
    typealias Entry = DiskUsageEntry

    func placeholder(in context: Context) -> DiskUsageEntry {
        DiskUsageEntry(
            date: Date(),
            usedBytes: 128_000_000_000,
            totalBytes: 256_000_000_000,
            categoryBreakdown: [("System", 40_000_000_000), ("Apps", 30_000_000_000)]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DiskUsageEntry) -> Void) {
        let entry = DiskUsageEntry(
            date: Date(),
            usedBytes: 128_000_000_000,
            totalBytes: 256_000_000_000,
            categoryBreakdown: [("System", 40_000_000_000), ("Apps", 30_000_000_000)]
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskUsageEntry>) -> Void) {
        let entry = DiskUsageEntry(
            date: Date(),
            usedBytes: 128_000_000_000,
            totalBytes: 256_000_000_000,
            categoryBreakdown: [("System", 40_000_000_000), ("Apps", 30_000_000_000)]
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    var entry: DiskUsageEntry

    var body: some View {
        VStack(spacing: 8) {
            Text("Disk Space")
                .font(.caption)
                .foregroundColor(.secondary)

            ProgressRing(usedRatio: Double(entry.usedBytes) / Double(entry.totalBytes))
                .frame(width: 60, height: 60)

            Text("\(formatBytes(entry.usedBytes)) used")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct MediumWidgetView: View {
    var entry: DiskUsageEntry

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(usedRatio: Double(entry.usedBytes) / Double(entry.totalBytes))
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mac Storage")
                    .font(.headline)

                DiskUsageBarView(usedBytes: entry.usedBytes, totalBytes: entry.totalBytes)

                Text("\(formatBytes(entry.usedBytes)) used of \(formatBytes(entry.totalBytes))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct LargeWidgetView: View {
    var entry: DiskUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.brandPrimary)
                Text("Storage Overview")
                    .font(.headline)
            }

            HStack(spacing: 16) {
                ProgressRing(usedRatio: Double(entry.usedBytes) / Double(entry.totalBytes))
                    .frame(width: 70, height: 70)

                VStack(alignment: .leading) {
                    Text("\(formatBytes(entry.usedBytes))")
                        .font(.title2).fontWeight(.bold)
                    Text("used of \(formatBytes(entry.totalBytes))")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Divider()

            ForEach(entry.categoryBreakdown.prefix(4), id: \.0) { category, bytes in
                HStack {
                    Text(category).font(.caption)
                    Spacer()
                    Text(formatBytes(bytes)).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Shared Components

struct ProgressRing: View {
    let usedRatio: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.separatorColor.opacity(0.3), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(usedRatio, 1.0))
                .stroke(
                    AngularGradient(colors: [.brandPrimary, .brandAccent], center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(usedRatio * 100))%")
                .font(.caption2).fontWeight(.bold)
        }
    }
}

struct DiskUsageBarView: View {
    let usedBytes: Int64
    let totalBytes: Int64

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.separatorColor.opacity(0.3))
                    .frame(height: 6)
                Capsule()
                    .fill(usedRatio > 0.9 ? Color.red : (usedRatio > 0.7 ? Color.yellow : Color.green))
                    .frame(width: geo.size.width * min(usedRatio, 1.0), height: 6)
            }
        }
        .frame(height: 6)
    }

    private var usedRatio: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

// MARK: - Widget Configuration

struct KSpaceCleanWidget: Widget {
    let kind: String = "app.kraftly.sclean.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Disk Usage")
        .description("Check your Mac storage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
