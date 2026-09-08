import SwiftUI
import DesignSystem

/// Main view for the maintenance tools feature (v2.0 Phase 2).
///
/// Guidance-first by design: tasks kWise cannot perform inside the App
/// Sandbox show a copy-paste Terminal command with an honest note, and the
/// one task inside the user's granted scope (user logs) runs through the
/// shared cleanup engine with rollback support.
public struct MaintenanceView: View {
    @StateObject private var viewModel: MaintenanceViewModel

    /// Injectable for the app root (graph engine + quota routing).
    public init(viewModel: MaintenanceViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MaintenanceViewModel())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header
                taskGrid
            }
            .padding(AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("系统维护")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Text("修复常见系统问题。受沙箱限制的任务提供可直接粘贴到终端的命令。")
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Task Grid

    private var taskGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppSpacing.lg),
                GridItem(.flexible(), spacing: AppSpacing.lg),
            ],
            spacing: AppSpacing.lg
        ) {
            ForEach(MaintenanceTask.allCases) { task in
                MaintenanceCard(task: task, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Maintenance Card

private struct MaintenanceCard: View {
    let task: MaintenanceTask
    @ObservedObject var viewModel: MaintenanceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerRow
            descriptionText
            sandboxNote
            Spacer()
            actionArea
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .task(id: viewModel.results[task.id]) {
            await autoClearResult()
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: task.icon)
                .font(.title3)
                .foregroundColor(.brandPrimary)

            Text(task.rawValue)
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
        }
    }

    private var descriptionText: some View {
        Text(task.detail)
            .font(AppFont.callout)
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sandboxNote: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: task.isEngineBacked ? "checkmark.shield" : "info.circle")
                .font(AppFont.caption)
                .foregroundColor(task.isEngineBacked ? .success : .textSecondary)
            Text(task.sandboxNote)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if viewModel.runningTask == task.id {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("运行中...")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        } else if let result = viewModel.results[task.id] {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.success)
                Text(result)
                    .font(AppFont.caption)
                    .foregroundColor(.success)
                    .lineLimit(2)
            }
        } else if task.isEngineBacked {
            Button("清理") {
                Task { await viewModel.execute(task) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isRunning)
        } else {
            Button(viewModel.copiedCommands.contains(task.id) ? "已复制 ✓" : "复制终端命令") {
                viewModel.copyCommand(for: task)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Auto-Clear

    /// Waits 5 seconds then removes the result for this task,
    /// so the card returns to its idle state automatically.
    private func autoClearResult() async {
        guard viewModel.results[task.id] != nil else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            viewModel.clearResult(for: task.id)
        }
    }
}
