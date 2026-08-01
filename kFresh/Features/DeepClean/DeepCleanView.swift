import SwiftUI

/// Pro "深度清理" screen: scans `/Library/LaunchAgents`,
/// `/Library/LaunchDaemons`, and `/Library/PreferencePanes` and lets the
/// user delete items in bulk. Every item is backed up by ``DeepCleanEngine``
/// before deletion.
///
/// The Pro gate is owned by the coordinator (Task 8) — this view does not
/// wrap itself in a paywall.
struct DeepCleanView: View {
    @StateObject private var viewModel: DeepCleanViewModel
    @State private var showCleanConfirm = false

    /// Creates the view. Production callers pass `nil` and get a real engine
    /// backed by `BackupManager` (default root); previews and tests inject a
    /// stub engine.
    init(engine: DeepCleanEngining? = nil) {
        let engine = engine ?? DeepCleanEngine(
            backupManager: BackupManager(),
            auditLogger: nil
        )
        _viewModel = StateObject(wrappedValue: DeepCleanViewModel(engine: engine))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .confirmationDialog(
            "确认清理",
            isPresented: $showCleanConfirm,
            titleVisibility: .visible
        ) {
            Button("清理所选 \(viewModel.selectedItems.count) 项", role: .destructive) {
                Task { _ = await viewModel.clean() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选项目会先备份到应用支持目录，再被删除。此操作不可撤销。")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .scanning:
            LoadingStateView(message: "正在扫描系统启动项…")
        case .cleaning:
            LoadingStateView(message: "正在清理所选项目…")
        case .loaded:
            if viewModel.groupedItems.isEmpty {
                EmptyStateView(
                    title: "没有可清理的项目",
                    subtitle: "系统启动项与偏好面板都是干净状态",
                    icon: "checkmark.seal"
                )
            } else {
                List {
                    ForEach(viewModel.groupedItems, id: \.0) { category, items in
                        SystemCleanGroupView(
                            category: category,
                            items: items,
                            selectedIDs: viewModel.selectedIDs,
                            onToggle: { item in
                                viewModel.toggle(item)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        case .failed(let message):
            EmptyStateView(
                title: "扫描失败",
                subtitle: message,
                icon: "exclamationmark.triangle",
                action: ("重试", { Task { await viewModel.load() } })
            )
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: AppSpacing.lg) {
            Text("已选 \(viewModel.selectedItems.count) 项 · \(viewModel.selectedSizeBytes.deepCleanSizeFormatted)")
                .font(.callout)
                .foregroundColor(.textSecondary)
            Spacer()
            Button {
                showCleanConfirm = true
            } label: {
                Label("清理", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.danger)
            .disabled(viewModel.selectedItems.isEmpty)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(Color.bgSecondary)
    }
}
