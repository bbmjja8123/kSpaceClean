import SwiftUI
import DesignSystem
import CommonUtils

// MARK: - Overview ViewModel

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var diskUsage = DiskUsage.current()
    @Published var isAnimating = false

    func refresh() {
        diskUsage = DiskUsage.current()
    }
}

// MARK: - Overview Tab (Hybrid Twin-Ring Design)

struct OverviewTabView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scanViewModel: ScanViewModel
    @StateObject private var overviewVM = OverviewViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if scanViewModel.resultGroups.isEmpty {
                    emptyState
                } else {
                    // Twin rings comparison
                    TwinRingView(
                        usedSpace: overviewVM.diskUsage.usedSpace,
                        totalSpace: overviewVM.diskUsage.totalSpace,
                        estimatedAfter: overviewVM.diskUsage.usedSpace - scanViewModel.selectedSize
                    )

                    // One-line summary
                    summarySection

                    // Priority cards (top 3 by size)
                    prioritySection

                    // "Other suggestions" link
                    if scanViewModel.resultGroups.count > 3 {
                        otherSuggestionsLink
                    }
                }
            }
            .padding(AppSpacing.md)
        }
        .onAppear { overviewVM.refresh() }
        .onReceive(scanViewModel.$scanDidComplete) { _ in overviewVM.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("点击\"开始扫描\"检查磁盘空间")
                .font(AppFont.body).foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("扫描完成")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
            Text("您可清理 **\(FileSizeFormatter.abbreviated(from: scanViewModel.selectedSize))**")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            Text("已预选推荐 + 可选项，排除危险项")
                .font(AppFont.caption).foregroundColor(.textSecondary)

            HStack(spacing: 6) {
                let stats = scanViewModel.riskGroupedStats
                if stats.recommended.count + stats.optional.count > 0 {
                    Label("\(stats.recommended.count + stats.optional.count) 项已预选", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.success.opacity(0.12)).foregroundColor(.success)
                        .clipShape(Capsule())
                }
                if stats.dangerous.count > 0 {
                    Label("\(stats.dangerous.count) 项已排除", systemImage: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.danger.opacity(0.12)).foregroundColor(.danger)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("按影响力排序建议")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)

            // Flatten action groups and sort by size
            let topActions = scanViewModel.resultGroups
                .flatMap { $0.actionGroups }
                .sorted { $0.totalSize > $1.totalSize }
                .prefix(3)

            ForEach(topActions) { action in
                PriorityCardView(actionGroup: action)
            }
        }
    }

    private var otherSuggestionsLink: some View {
        Button {
            appState.rightPanelTab = .suggestions
        } label: {
            Text("+ 还有 \(scanViewModel.resultGroups.flatMap { $0.actionGroups }.count - 3) 项其他建议 查看全部 →")
                .font(.system(size: 12))
                .foregroundColor(.brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Twin Ring View (Apple Watch style)

struct TwinRingView: View {
    let usedSpace: Int64
    let totalSpace: Int64
    let estimatedAfter: Int64

    private var usedRatio: CGFloat {
        totalSpace > 0 ? min(CGFloat(usedSpace) / CGFloat(totalSpace), 1.0) : 0
    }
    private var afterRatio: CGFloat {
        totalSpace > 0 ? min(max(CGFloat(estimatedAfter) / CGFloat(totalSpace), 0), 1.0) : 0
    }
    private var freedGB: Double {
        Double(usedSpace - estimatedAfter) / 1_000_000_000
    }

    var body: some View {
        HStack(spacing: 12) {
            // Current ring
            ringCard(
                label: "当前",
                value: FileSizeFormatter.abbreviated(from: usedSpace),
                sublabel: "已用 \(Int(usedRatio * 100))%",
                progress: usedRatio,
                color: usedRatio > 0.9 ? .danger : usedRatio > 0.7 ? .warning : .success
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.textSecondary)

            // After ring
            ringCard(
                label: "清理后",
                value: FileSizeFormatter.abbreviated(from: estimatedAfter),
                sublabel: String(format: "-%.1f GB 可用", freedGB),
                progress: afterRatio,
                color: .success
            )
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func ringCard(label: String, value: String, sublabel: String,
                          progress: CGFloat, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.separatorColor.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)
                // Value text
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
    }
}

// MARK: - Priority Card View

@MainActor
struct PriorityCardView: View {
    let actionGroup: ActionGroup

    private var impactTag: String {
        switch actionGroup.riskLevel {
        case .dangerous: return "HIGH"
        case .caution: return "MED"
        default: return actionGroup.totalSize > 1_000_000_000 ? "HIGH" : "MED"
        }
    }

    private var tagColor: Color {
        switch impactTag {
        case "HIGH": return .warning
        case "MED": return .brandPrimary
        default: return .success
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(impactTag)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(tagColor.opacity(0.15))
                .foregroundColor(tagColor)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(actionGroup.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                if let app = actionGroup.appName {
                    Text("\(actionGroup.items.count) 个文件 · \(app)")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                } else {
                    Text("\(actionGroup.items.count) 个文件")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: actionGroup.totalSize))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(10)
        .background(Color.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
