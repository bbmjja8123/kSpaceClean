// kWise/Features/History/TimelineView.swift
//
// 清理时间线 (v2.0 Phase 7) — every cleanup run becomes one timeline event
// (grouped by the per-run `runID` written since the Core Data migration),
// with whole-run rollback via `RestoreFromTrashService`.
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
    public let rows: [CleanupHistoryItem]

    public var isRestorable: Bool { restorableCount > 0 }
}

// MARK: - ViewModel

@MainActor
public final class TimelineViewModel: ObservableObject {
    @Published public private(set) var events: [TimelineEvent] = []
    @Published public private(set) var isRestoring = false
    @Published public private(set) var lastRestoreMessage: String?

    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    public func refresh() {
        let rows = persistence.fetchHistory(limit: 0)
        events = Self.group(rows)
    }

    /// Groups rows by `runID` (legacy rows fall back to their own row id).
    static func group(_ rows: [CleanupHistoryItem]) -> [TimelineEvent] {
        let buckets = Dictionary(grouping: rows) { row -> UUID in
            row.runID ?? row.id ?? UUID()
        }
        return buckets.map { runID, rows in
            let date = rows.compactMap(\.cleanedAt).max() ?? Date()
            let freed = rows.reduce(Int64(0)) { $0 + $1.size }
            let notRestored = rows.filter { !$0.isRestored }.count
            return TimelineEvent(
                id: runID,
                date: date,
                kindLabel: rows.first?.kindLabel ?? "清理",
                itemCount: rows.count,
                freedBytes: freed,
                restorableCount: notRestored,
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
                    self?.lastRestoreMessage = "已还原 \(restored) 项"
                } else {
                    self?.lastRestoreMessage = "还原 \(restored) 项，\(failed) 项已不在废纸篓"
                }
                self?.refresh()
            }
        }
    }
}

// MARK: - View

struct TimelineView: View {
    @StateObject private var viewModel: TimelineViewModel

    init(persistence: PersistenceController = .shared) {
        _viewModel = StateObject(wrappedValue: TimelineViewModel(persistence: persistence))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header
                if viewModel.events.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "还没有清理记录",
                        subtitle: "完成一次清理后，这里会显示时间线。"
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

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("清理时间线")
                .font(AppFont.title2)
                .foregroundStyle(Color.textPrimary)
            Text("每次清理归为一条记录，可整体回滚到清理前状态")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            if let message = viewModel.lastRestoreMessage {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.success)
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
                    Text(SmartCareHeroView.formatBytes(event.freedBytes))
                        .font(AppFont.monoDigit)
                        .foregroundStyle(Color.textPrimary)
                }

                Text(event.isRestorable
                     ? "\(event.restorableCount) 项可还原"
                     : "已还原或已超出废纸篓保留期")
                    .font(AppFont.caption)
                    .foregroundStyle(event.isRestorable ? Color.success : Color.textSecondary)

                HStack {
                    Button("查看明细") { withAnimation(KFAnimation.easeInOut) { expanded.toggle() } }
                        .buttonStyle(.plain)
                        .font(AppFont.caption)
                    Spacer()
                    Button("整体回滚") { onRollback() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!event.isRestorable)
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
