import SwiftUI
import DesignSystem
import CommonUtils

/// Scan content view — shows progress and results when scanning.
struct ScanContentView: View {
    @ObservedObject var viewModel: ScanViewModel
    @State private var isScanningAnimating = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Header
            HStack {
                Text("扫描")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                Spacer()
                if case .scanning = viewModel.progress.state {
                    Button("取消") {
                        viewModel.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .tint(.danger)
                } else {
                    Button("开始扫描") {
                        viewModel.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 16)

            // Progress / Content
            switch viewModel.progress.state {
            case .idle:
                idleState
            case .scanning, .analysing:
                scanningState
            case .completed:
                completedState
            case .cancelled:
                cancelledState
            case .failed(let msg):
                failedState(msg)
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("点击\"开始扫描\"检查磁盘空间")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
            Text("将扫描系统缓存、应用剩余和大文件")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Lemon-style Scanning State

    private var scanningState: some View {
        let progress = viewModel.progress
        return VStack(spacing: 0) {
            // Top: scanning indicator with file count + speed
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.brandPrimary)
                    .opacity(isScanningAnimating ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isScanningAnimating)
                    .onAppear { isScanningAnimating = true }
                    .onDisappear { isScanningAnimating = false }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.currentCategory.isEmpty ? "正在扫描..." : progress.currentCategory)
                        .font(AppFont.title3)
                        .foregroundColor(.textPrimary)
                    if !progress.currentSubCategory.isEmpty {
                        Text(progress.currentSubCategory)
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Real-time stats
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(progress.filesDiscovered) 个文件")
                        .font(AppFont.monoDigit)
                        .foregroundColor(.textPrimary)
                    Text(FileSizeFormatter.abbreviated(from: progress.totalBytes))
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                    if progress.stats.filesPerSecond > 0 {
                        Text("\(Int(progress.stats.filesPerSecond)) 文件/秒")
                            .font(AppFont.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)

            // 8-stage progress pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ScanStage.allCases, id: \.rawValue) { stage in
                        StagePill(stage: stage, currentStage: progress.currentStage,
                                  categoryProgress: progress.categoryProgress)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }

            // Current file path bar (dark bg, blinking cursor)
            if let filePath = progress.currentNodePath {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 6, height: 6)
                        .opacity(isScanningAnimating ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isScanningAnimating)
                    Text(filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.head)
                    // Blinking cursor
                    Text("\u{258C}")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.brandPrimary)
                        .opacity(isScanningAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isScanningAnimating)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }

            // Bottom: Lemon-style category progress list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(progress.categoryProgress) { catProgress in
                        CategoryProgressRow(
                            catProgress: catProgress,
                            isCurrentCategory: catProgress.title == progress.currentCategory
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Completed / Cancelled / Failed

    private var completedState: some View {
        ScanResultsTreeView(viewModel: viewModel)
            .frame(maxHeight: .infinity)
    }

    private var cancelledState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.warning)
            Text("扫描已取消")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
            Button("重新扫描") {
                viewModel.startScan()
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
        .frame(maxHeight: .infinity)
    }

    private func failedState(_ msg: String) -> some View {
        ErrorStateView(
            title: "扫描失败",
            message: msg,
            retryAction: { viewModel.startScan() }
        )
    }
}

// MARK: - Category Progress Row

private struct CategoryProgressRow: View {
    let catProgress: CategoryProgress
    let isCurrentCategory: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status icon
            statusIcon
                .frame(width: 20)

            // Category name
            Text(catProgress.title)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
                .fontWeight(isCurrentCategory ? .bold : .regular)

            Spacer()

            // Sub-category progress
            if catProgress.status == .scanning {
                Text(activeSubCategory)
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            // Files count
            if catProgress.filesFound > 0 {
                Text("\(catProgress.filesFound)")
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrentCategory ? Color.brandPrimary.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch catProgress.status {
        case .pending:
            Circle()
                .strokeBorder(Color.textSecondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 12, height: 12)
        case .scanning:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.success)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.danger)
        }
    }

    private var activeSubCategory: String {
        catProgress.subCategories
            .first { $0.status == .scanning }
            .map { $0.title } ?? ""
    }
}

// MARK: - 8-Stage Progress Pill

private struct StagePill: View {
    let stage: ScanStage
    let currentStage: ScanStage
    let categoryProgress: [CategoryProgress]

    private var status: ScanItemStatus {
        if let cp = categoryProgress.first(where: { $0.id == stage.rawValue }) {
            return cp.status
        }
        return .pending
    }

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            Text(stage.title)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
        case .scanning:
            ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
        case .failed:
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
        case .pending:
            EmptyView()
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .completed: return Color.success.opacity(0.15)
        case .scanning: return Color.brandPrimary.opacity(0.15)
        case .failed: return Color.danger.opacity(0.15)
        case .pending: return Color.separatorColor.opacity(0.3)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .completed: return .success
        case .scanning: return .brandPrimary
        case .failed: return .danger
        case .pending: return .textSecondary
        }
    }
}
