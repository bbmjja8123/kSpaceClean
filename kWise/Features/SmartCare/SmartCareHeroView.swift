import SwiftUI
import DesignSystem
import PowerScope

/// 「安全快捷回收」次级页（P1 T6 降级 — spec §3.1）。
///
/// 首屏已让位给解剖视图（P1 T5）；本页从导航枢纽收缩为单卡次级页：
/// 只保留 Smart Care 3 步流（scan → recommend → 预演 sheet 确认 → clean，
/// P2 T5 R-统一：确认面板退役，`.confirming` 由根部预演 sheet 接管）的
/// 状态机卡片 + 一行诚实说明。不再渲染模块网格、不再承担页面跳转 ——
/// 入口只剩解剖视图的「安全快捷回收」按钮、菜单栏 quickClean 与扫描
/// 结果页内嵌面板。container-only 用户看到的是授权卡（controller
/// ruling R1），绝不是一次空跑。
///
/// - C-2 (SHOULD): hero CTA occupies ≤30% of available vertical area.
struct SmartCareHeroView: View {
    @ObservedObject var viewModel: SmartCareViewModel
    @ObservedObject private var appScope = AppScope.shared

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            heroCard
            Text("attr.safeclean.subtitle")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: - Hero (state-driven, C-2 ≤30% area)

    @ViewBuilder
    private var heroCard: some View {
        // Scope fast-fail: without the home grant a scan would find almost
        // nothing. Show the grant card instead of a pointless run.
        if appScope.capability.level == .containerOnly {
            scopeGrantCard
        } else {
            stateCard
        }
    }

    private var scopeGrantCard: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "lock.open")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandAccent)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("授权后开始安全快捷回收")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("授权主目录后，kWise 才能发现可清理的缓存与残留。")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("授权主目录") {
                Task { await appScope.grant() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    @ViewBuilder
    private var stateCard: some View {
        HStack(spacing: AppSpacing.md) {
            switch viewModel.state {
            case .idle:
                idleHero
            case .scanning(let progress):
                busyHero(phase: "正在扫描", progress: progress)
            case .recommending:
                busyHero(phase: "正在挑选可清理项", progress: nil)
            case .confirming(let itemCount, let totalSize):
                confirmingHero(itemCount: itemCount, totalSize: totalSize)
            case .cleaning(let progress):
                busyHero(phase: "正在清理", progress: progress)
            case .done(let freedBytes, _):
                doneHero(freedBytes: freedBytes)
            case .failed(let message):
                failedHero(message: message)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var idleHero: some View {
        Button {
            viewModel.runSmartCare()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.brandPrimary)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("nav.smartCare")
                        .font(AppFont.title2)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func busyHero(phase: String, progress: Double?) -> some View {
        HStack(spacing: AppSpacing.md) {
            if let progress {
                ProgressRing(progress: min(max(progress, 0), 1))
                    .frame(width: 40, height: 40)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("nav.smartCare")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(phase)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("取消") { viewModel.reset() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    /// R-统一（P2 T5）：确认面板退役 —— `.confirming` 由根部的预演 sheet
    /// （``CleanupRehearsalSheet``）接管，本卡片只渲染被动说明；不再有
    /// 绕过预演的「一键清理」直执行按钮。
    private func confirmingHero(itemCount: Int, totalSize: Int64) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("发现 \(itemCount) 项可清理")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("预计释放 \(Self.formatBytes(totalSize))。请在预演清单中确认要回收的项目（移入废纸篓，可随时还原）。")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("取消") { viewModel.reset() }
                .buttonStyle(.bordered)
        }
    }

    private func doneHero(freedBytes: Int64) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.success)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("已释放 \(Self.formatBytes(freedBytes))")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("项目已移入废纸篓，30 天内可在历史中还原。")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("再来一次") { viewModel.reset() }
                .buttonStyle(.bordered)
        }
    }

    private func failedHero(message: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color.warning)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("未能完成")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("重试") {
                viewModel.reset()
                viewModel.runSmartCare()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    /// C-3 freed-bytes formatting — one shared formatter so the hero, the
    /// menu bar and the history view never disagree.
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

#if DEBUG
#Preview {
    SmartCareHeroView(viewModel: SmartCareViewModel())
        .frame(width: 700, height: 500)
}
#endif
