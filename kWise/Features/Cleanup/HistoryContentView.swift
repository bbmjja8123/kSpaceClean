import SwiftUI
import DesignSystem
import CoreData

/// History content view — shows scan and cleanup history.
struct HistoryContentView: View {
    @State private var scanHistory: [ScanRecord] = []
    @State private var cleanupRecords: [CleanupHistoryItem] = []
    // I10: rollback sheet state.
    @State private var openBatch: [CleanupHistoryItem] = []
    @State private var batchSheetVisible: Bool = false

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
                    if !scanHistory.isEmpty {
                        Text("\u{626B}\u{63CF}\u{5386}\u{53F2}")
                            .font(AppFont.title3)
                            .foregroundColor(.textPrimary)

                        ForEach(scanHistory, id: \.id) { record in
                            ScanRecordRow(record: record)
                        }
                    }

                    if !cleanupRecords.isEmpty {
                        Text("\u{6E05}\u{7406}\u{5386}\u{53F2}")
                            .font(AppFont.title3)
                            .foregroundColor(.textPrimary)

                        // I10: rows are grouped by (cleanedAt, bundleID) so a
                        // user can see exactly which cleanup batch they want
                        // to undo and roll every file in that batch back in
                        // one tap. Tapping a batch opens RestoreHistoryItemView.
                        ForEach(groupedBatches, id: \.key) { batch in
                            Button {
                                openBatch = batch.items
                                batchSheetVisible = true
                            } label: {
                                CleanupBatchRow(
                                    cleanedAt: batch.cleanedAt,
                                    bundleID: batch.bundleID,
                                    items: batch.items
                                )
                            }
                            .buttonStyle(.plain)
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
        .sheet(isPresented: $batchSheetVisible) {
            RestoreHistoryItemView(batch: openBatch) {
                batchSheetVisible = false
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
        cleanupFetch.fetchLimit = 100
        cleanupRecords = (try? ctx.fetch(cleanupFetch)) ?? []
    }

    /// I10: bucket cleanup history into same-batch groups so the rollback
    /// sheet can list every file from a single cleanup run together.
    private var groupedBatches: [CleanupBatch] {
        let groups = Dictionary(grouping: cleanupRecords) { item in
            CleanupBatchKey(
                cleanedAt: (item.cleanedAt ?? Date.distantPast).rounded(toSeconds: 1),
                bundleID: item.bundleID ?? "_"
            )
        }
        return groups.map { key, items in
            CleanupBatch(
                key: "\(key.cleanedAt.timeIntervalSince1970)-\(key.bundleID)",
                cleanedAt: key.cleanedAt,
                bundleID: key.bundleID,
                items: items.sorted { $0.path ?? "" < $1.path ?? "" }
            )
        }
        .sorted { $0.cleanedAt > $1.cleanedAt }
    }
}

private struct CleanupBatchKey: Hashable {
    let cleanedAt: Date
    let bundleID: String
}

private struct CleanupBatch: Identifiable {
    let key: String
    let cleanedAt: Date
    let bundleID: String
    let items: [CleanupHistoryItem]
    var id: String { key }
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

struct CleanupBatchRow: View {
    let cleanedAt: Date
    let bundleID: String
    let items: [CleanupHistoryItem]

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalSize) \u{5B57}\u{8282} \u{00B7} \(items.count) \u{9879}")
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Text("\(cleanedAt.formatted()) \u{00B7} \(bundleID)")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.textTertiary)
            }
            .padding(AppSpacing.md)
        }
    }

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
}

private extension Date {
    /// Truncate to second precision so two items written within 1s of each
    /// other during the same cleanup batch land in the same group.
    func rounded(toSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: floor(timeIntervalSince1970 / toSeconds) * toSeconds)
    }
}
