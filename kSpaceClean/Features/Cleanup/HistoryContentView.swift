import SwiftUI
import DesignSystem
import CoreData

/// History content view — shows scan and cleanup history.
struct HistoryContentView: View {
    @State private var scanHistory: [ScanRecord] = []
    @State private var cleanupRecords: [CleanupHistoryItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text("\u{5386}\u{53F2}")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("\u{5237}\u{65B0}") {
                    loadHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Scan History Section
                    if !scanHistory.isEmpty {
                        Text("\u{626B}\u{63CF}\u{5386}\u{53F2}")
                            .font(AppFont.title3)
                            .foregroundColor(.textPrimary)

                        ForEach(scanHistory, id: \.id) { record in
                            ScanRecordRow(record: record)
                        }
                    }

                    // Cleanup History Section
                    if !cleanupRecords.isEmpty {
                        Text("\u{6E05}\u{7406}\u{5386}\u{53F2}")
                            .font(AppFont.title3)
                            .foregroundColor(.textPrimary)

                        ForEach(cleanupRecords, id: \.id) { record in
                            CleanupRecordMiniRow(record: record)
                        }
                    }

                    if scanHistory.isEmpty && cleanupRecords.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
        .onAppear {
            Task { @MainActor in
                loadHistory()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.textSecondary)

            Text("\u{5C1A}\u{65E0}\u{5386}\u{53F2}\u{8BB0}\u{5F55}")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)

            Text("\u{60A8}\u{7684}\u{626B}\u{63CF}\u{548C}\u{6E05}\u{7406}\u{8BB0}\u{5F55}\u{5C06}\u{663E}\u{793A}\u{5728}\u{8FD9}\u{91CC}")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
        }
        .frame(maxHeight: .infinity)
    }

    @MainActor
    private func loadHistory() {
        let ctx = CoreDataStack.shared.viewContext

        let scanFetch = ScanRecord.fetchRequest()
        scanFetch.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        scanFetch.fetchLimit = 20
        scanHistory = (try? ctx.fetch(scanFetch)) ?? []

        let cleanupFetch = CleanupHistoryItem.fetchRequest()
        cleanupFetch.sortDescriptors = [NSSortDescriptor(key: "cleanedAt", ascending: false)]
        cleanupFetch.fetchLimit = 20
        cleanupRecords = (try? ctx.fetch(cleanupFetch)) ?? []
    }
}

struct ScanRecordRow: View {
    let record: ScanRecord

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.totalBytes) \u{5B57}\u{8282}")
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Text(record.startedAt?.formatted() ?? "")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                if let entries = record.entries {
                    Text("\(entries.count) \u{4E2A}\u{6587}\u{4EF6}")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(AppSpacing.md)
        }
    }
}

struct CleanupRecordMiniRow: View {
    let record: CleanupHistoryItem

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.size) \u{5B57}\u{8282}")
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Text(record.cleanedAt?.formatted() ?? "")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Text(record.riskLevel ?? "recommended")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(AppSpacing.md)
        }
    }
}
