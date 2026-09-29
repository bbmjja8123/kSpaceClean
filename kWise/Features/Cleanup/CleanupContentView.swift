import SwiftUI
import DesignSystem
import CommonUtils

/// Cleanup content view — shows cleanup history and risk-aware confirmation.
struct CleanupContentView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @EnvironmentObject var appState: AppState
    @State private var showConfirmation = false
    @State private var confirmationLevel: CleanupConfirmationLevel = .low
    @State private var deleteConfirmed = false
    /// P1 T4 预演层 —— 确认弹窗点「确认清理」后先预演，二次人签才执行。
    @State private var rehearsalPayload: RehearsalSheetPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack {
                Text("清理")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                Spacer()
                if !viewModel.cleanupHistory.isEmpty {
                    Button("刷新") {
                        Task { await viewModel.refreshHistory() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 16)

            if viewModel.isCleaning {
                cleaningProgress
            } else if viewModel.cleanupHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        // P1 T4 二次人签：确认弹窗只负责预演，真正的执行在预演 sheet 的
        // 「确认执行」按钮里（executeConfirmedCleanup 消费 pendingTargets）。
        .sheet(item: $rehearsalPayload) { payload in
            CleanupRehearsalSheet(
                items: payload.items,
                onConfirm: { confirmed in
                    // r1 fix（Critical 1）：确认只执行 sheet 上仍然勾选的子集。
                    Task {
                        await viewModel.executeConfirmedCleanup(
                            sizes: nil, confirmedTargets: confirmed)
                        rehearsalPayload = nil
                    }
                },
                onCancel: {
                    // 取消 = 作废；下一次确认会重新预演覆盖 pendingTargets。
                    rehearsalPayload = nil
                },
                isExecuting: viewModel.isCleaning
            )
        }
        .confirmationDialog(
            "确认清理",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            switch confirmationLevel {
            case .low:
                Button("一键清理") { performCleanup() }
            case .medium:
                Button("确认清理（含注意项）") { performCleanup() }
            case .high:
                Button("警告：含危险项，确认清理") { performCleanup() }
                Button("取消", role: .cancel) { }
            case .irreversible:
                Button("永久删除（不可恢复！）", role: .destructive) { performCleanup() }
                Button("取消", role: .cancel) { }
            }
        } message: {
            switch confirmationLevel {
            case .low:
                Text("将清理选中的推荐项和可选项，文件将移入废纸篓。")
            case .medium:
                Text("包含注意项：清理后可能需要重新登录或重建缓存。")
            case .high:
                Text("包含危险项或运行中应用的文件。请确认已保存工作。")
            case .irreversible:
                Text("此操作将永久删除文件，不可通过废纸篓恢复！")
            }
        }
    }

    private var cleaningProgress: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("清理中...")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "trash.slash")
                .font(.system(size: 64))
                .foregroundColor(.textSecondary)
            Text("尚无清理记录")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
            Text("扫描并清理后，此处将显示清理历史，支持回滚")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.cleanupHistory, id: \.id) { record in
                    CleanupRecordRow(record: record)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func performCleanup() {
        // P1 T4 两段式第一段 —— 预演：把确认弹窗背后的清单（`urlsToCleanup`）
        // 显式传入 makeRehearsal（不依赖外部状态的静默 no-op 老坑不再复制），
        // 暂存 pendingTargets 并呈现逐项预演 sheet；真正执行走预演 sheet 的
        // onConfirm（`executeConfirmedCleanup`），历史/回滚/配额管线不变。
        Task {
            let items = await viewModel.makeRehearsal(sizes: nil, urls: viewModel.urlsToCleanup)
            rehearsalPayload = RehearsalSheetPayload(items: items)
        }
    }
}

struct CleanupRecordRow: View {
    let record: CleanupHistoryItem

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(.danger)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(FileSizeFormatter.abbreviated(from: record.size))
                        .font(AppFont.monoDigit)
                        .foregroundColor(.textPrimary)

                    Text(record.cleanedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
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
