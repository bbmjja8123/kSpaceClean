// kWise/Features/History/TimelineView.swift
//
// 清理时间线 (v2.0 Phase 7) — every cleanup run becomes one timeline event
// (grouped by the per-run `runID` written since the Core Data migration),
// with whole-run rollback via `RestoreFromTrashService`.
//
// P2 T7 — the dashboard header is replaced by the narrative header
// (「这周你回收了 X」+ 磁盘对比 + 打卡一行小字，见 NarrativeHeaderModel)，
// and the retired monthly report's weekly buckets / top files / forecast
// are absorbed as the collapsible 「本月」 section above the event list.
import SwiftUI
import CoreData
import DesignSystem

// MARK: - Event model

public struct TimelineEvent: Identifiable {
    public let id: UUID
    public let date: Date
    public let kindLabel: String
    public let itemCount: Int
    public let freedBytes: Int64
    /// Rows already restored (or whose Trash copy is gone) still show, with
    /// their state — never silently hidden.
    public let restorableCount: Int
    /// Task 8 review Important 2：永久移除 run（垃圾桶来源组等，moveToTrash
    /// == false）—— 释放字节照计，但**没有回滚语义**：restorableCount 恒 0，
    /// 行尾不渲染回滚按钮，改渲染诚实的「已永久移除」说明行。
    public let isPermanent: Bool
    public let rows: [CleanupHistoryItem]

    public var isRestorable: Bool { restorableCount > 0 }
}

// MARK: - ViewModel

@MainActor
public final class TimelineViewModel: ObservableObject {
    @Published public private(set) var events: [TimelineEvent] = []
    @Published public private(set) var isRestoring = false
    @Published public private(set) var lastRestoreMessage: String?

    /// P2 T7 — narrative header lines (headline / disk sub / streak line).
    @Published public private(set) var narrative: (headline: String, sub: String, streakLine: String?) =
        (NarrativeHeaderModel.weekHeadline(records: [], now: Date(), calendar: .current),
         String(localized: String.LocalizationValue("history.narrative.subInsufficientSamples")),
         nil)
    /// P2 T7 — the retired monthly report's data, rendered as the 「本月」
    /// collapsible section (weekly buckets / top files / forecast).
    @Published public private(set) var monthly: MonthlyReport?

    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    /// Re-reads the local history and rebuilds the narrative header and the
    /// 本月 data from the injected environment (tests/previews inject;
    /// production reads the sample ring + streak ledger once per refresh).
    public func refresh(environment: NarrativeEnvironment = .live) {
        let rows = persistence.fetchHistory(limit: 0)
        events = Self.group(rows)
        narrative = NarrativeHeaderModel.build(
            records: rows,
            samples: environment.samples,
            streak: environment.streak
        )
        monthly = ReportGenerator.generate(
            history: rows,
            streak: environment.streak,
            samples: environment.samples
        )
    }

    /// Groups rows by `runID` (legacy rows fall back to their own row id).
    static func group(_ rows: [CleanupHistoryItem]) -> [TimelineEvent] {
        let buckets = Dictionary(grouping: rows) { row -> UUID in
            row.runID ?? row.id ?? UUID()
        }
        return buckets.map { runID, rows in
            let date = rows.compactMap(\.cleanedAt).max() ?? Date()
            let freed = rows.reduce(Int64(0)) { $0 + $1.size }
            // Task 8 review Important 2：永久移除 run 永不进回滚集 ——
            // restorableCount 恒 0（否则回滚逐行 .notFound，假入口）。
            let isPermanent = rows.first?.actionKind
                == CleanupHistoryItem.ActionKind.permanentCleanup
            let notRestored = isPermanent ? 0 : rows.filter { !$0.isRestored }.count
            return TimelineEvent(
                id: runID,
                date: date,
                kindLabel: rows.first?.kindLabel ?? String(localized: String.LocalizationValue("history.timeline.kindCleanup")),
                itemCount: rows.count,
                freedBytes: freed,
                restorableCount: notRestored,
                isPermanent: isPermanent,
                rows: rows
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Rolls back one whole run: restores every still-restorable row and
    /// marks them `restoredAt`.
    public func rollback(_ event: TimelineEvent) {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            var restored = 0
            var failed = 0
            let context = persistence.newBackgroundContext()
            for row in event.rows where !row.isRestored {
                guard let path = row.path else { continue }
                switch RestoreFromTrashService.restore(path: path) {
                case .restored:
                    restored += 1
                    await context.perform { [persistence] in
                        row.restoredAt = Date()
                        persistence.save(context: context)
                    }
                case .notInTrash, .notFound:
                    failed += 1
                @unknown default:
                    failed += 1
                }
            }
            await MainActor.run { [weak self] in
                self?.isRestoring = false
                if failed == 0 {
                    self?.lastRestoreMessage = String(
                        format: String(localized: String.LocalizationValue("history.timeline.restoredCount")),
                        restored
                    )
                } else {
                    self?.lastRestoreMessage = String(
                        format: String(localized: String.LocalizationValue("history.timeline.restoredPartial")),
                        restored, failed
                    )
                }
                self?.refresh()
            }
        }
    }
}

// MARK: - View

struct TimelineView: View {
    @StateObject private var viewModel: TimelineViewModel
    @State private var showMonthly = false

    init(persistence: PersistenceController = .shared) {
        _viewModel = StateObject(wrappedValue: TimelineViewModel(persistence: persistence))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                narrativeHeader
                monthlySection
                if viewModel.events.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: String(localized: String.LocalizationValue("history.timeline.emptyTitle")),
                        subtitle: String(localized: String.LocalizationValue("history.timeline.emptySubtitle"))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    eventList
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.refresh() }
    }

    /// P2 T7 — narrative header: one sentence + one honest sub-line + the
    /// streak as a single small line (no game panel).
    private var narrativeHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(viewModel.narrative.headline)
                .font(AppFont.titleHero)
                .foregroundStyle(Color.textPrimary)
            Text(viewModel.narrative.sub)
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
            if let streak = viewModel.narrative.streakLine {
                Text(streak)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(String(localized: String.LocalizationValue("history.timeline.explainer")))
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            if let message = viewModel.lastRestoreMessage {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.success)
            }
        }
    }

    /// P2 T7 — the retired monthly report, absorbed as a collapsible
    /// 「本月」 section: weekly buckets, top cleaned files, disk forecast.
    @ViewBuilder
    private var monthlySection: some View {
        if let report = viewModel.monthly {
            DisclosureGroup(isExpanded: $showMonthly) {
                monthlyDetail(report)
                    .padding(.top, AppSpacing.sm)
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Text(String(localized: String.LocalizationValue("history.monthly.sectionTitle")))
                        .font(AppFont.title3)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(SharedByteFormat.formatBytes(report.totalFreedBytes))
                        .font(AppFont.monoDigit)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(AppSpacing.md)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
    }

    private func monthlyDetail(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Weekly buckets, oldest → newest (same chart the report had).
            HStack(alignment: .bottom, spacing: AppSpacing.md) {
                let maxBytes = max(report.weekly.map(\.freedBytes).max() ?? 1, 1)
                ForEach(report.weekly) { bucket in
                    VStack(spacing: AppSpacing.xs) {
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(Color.brandPrimary.opacity(0.7))
                            .frame(height: CGFloat(max(4, 64 * Double(bucket.freedBytes) / Double(maxBytes))))
                        Text(bucket.label)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96)

            // Top cleaned files this month (up to 5, largest first).
            if !report.topCleanedFiles.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(String(localized: String.LocalizationValue("history.monthly.topFiles")))
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textPrimary)
                    ForEach(report.topCleanedFiles) { file in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(Color.brandPrimary)
                            Text(file.name)
                                .font(AppFont.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(SharedByteFormat.formatBytes(file.size))
                                .font(AppFont.monoDigit)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }

            // Disk-full forecast (honest variants — C-5).
            switch report.forecast {
            case .insufficientData:
                Text(String(localized: String.LocalizationValue("history.forecast.insufficientData")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            case .stable:
                Text(String(localized: String.LocalizationValue("history.forecast.stable")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            case .filling(let days, _):
                Text(String(
                    format: String(localized: String.LocalizationValue("history.forecast.filling")),
                    days
                ))
                .font(AppFont.callout)
                .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.events) { event in
                TimelineEventRow(event: event) {
                    viewModel.rollback(event)
                }
            }
        }
    }
}

// MARK: - Row

private struct TimelineEventRow: View {
    let event: TimelineEvent
    let onRollback: () -> Void
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Timeline rail
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.bgSecondary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Text(event.kindLabel)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.brandPrimary.opacity(0.12))
                        .clipShape(Capsule())
                    Text(Self.dateFormatter.string(from: event.date))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(SharedByteFormat.formatBytes(event.freedBytes))
                        .font(AppFont.monoDigit)
                        .foregroundStyle(Color.textPrimary)
                }

                // Task 8 review Important 2：永久移除 run 的诚实说明行 ——
                // 不再复用「不可还原」的通用灰字（那是「已还原/废纸篓已清」
                // 语义），而是明确「当时就是永久移除，无回滚入口」。
                if event.isPermanent {
                    Text("history.timeline.permanentRemoved")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.warning)
                } else {
                    Text(event.isRestorable
                         ? String(format: String(localized: String.LocalizationValue("history.timeline.restorableCount")), event.restorableCount)
                         : String(localized: String.LocalizationValue("history.timeline.notRestorable")))
                        .font(AppFont.caption)
                        .foregroundStyle(event.isRestorable ? Color.success : Color.textSecondary)
                }

                HStack {
                    Button(String(localized: String.LocalizationValue("history.timeline.showDetails"))) {
                        withAnimation(KFAnimation.easeInOut) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.caption)
                    Spacer()
                    // 永久移除 run 不渲染回滚按钮（不是禁用 —— 禁用暗示
                    // 「有这个能力」，永久移除压根没有这个能力）。
                    if !event.isPermanent {
                        Button(String(localized: String.LocalizationValue("history.timeline.rollbackAll"))) { onRollback() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!event.isRestorable)
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    TimelineView(persistence: PersistenceController(inMemory: true))
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
