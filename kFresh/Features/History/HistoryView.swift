import SwiftUI

/// History tab: lists the last 30 days of uninstall records and lets
/// the user restore any of them via the row's "恢复" button. State
/// (records + per-row restore progress) lives in `HistoryViewModel`.
///
/// `HistoryView` owns the view-model via `@StateObject` so the loaded
/// list survives across tab switches and parent re-renders.
struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel

    /// Designated init accepts an externally-built view-model so the
    /// app coordinator can inject shared dependencies (repository +
    /// trash-mover) for tests and previews.
    init(viewModel: HistoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("30 天内可恢复")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)

            if viewModel.records.isEmpty {
                EmptyStateView(
                    title: "暂无卸载记录",
                    subtitle: "卸载过的 App 会显示在这里，30 天内可一键恢复",
                    icon: "clock.arrow.circlepath"
                )
            } else {
                List {
                    ForEach(viewModel.records) { record in
                        HistoryRowView(
                            record: record,
                            restoreState: viewModel.restoreState,
                            onRestore: {
                                Task { await viewModel.restore(record) }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("卸载历史")
        .task { await viewModel.loadHistory() }
    }
}