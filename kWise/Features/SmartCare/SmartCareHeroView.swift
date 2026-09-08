import SwiftUI
import DesignSystem
import PowerScope

/// Hybrid UI first screen (v1.5 hero + v2.0 Phase 3 wiring).
///
/// Renders the home surface: a hero card driving the Smart Care 3-step
/// flow (scan → recommend → confirm → clean) + a module grid. The hero
/// CTA used to be `Button(action: {})` — it now runs the orchestrator
/// end-to-end and honestly surfaces the scope state (container-only users
/// see a grant card, never an empty scan).
///
/// - C-2 (SHOULD): hero CTA occupies ≤30% of available vertical area.
struct SmartCareHeroView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: SmartCareViewModel
    @ObservedObject var diskHealthViewModel: DiskHealthViewModel
    @ObservedObject private var appScope = AppScope.shared

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            heroCard
            moduleGrid
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
                Text("授权后开始 Smart Care")
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
                confirmHero(itemCount: itemCount, totalSize: totalSize)
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
                    Text("Smart Care")
                        .font(AppFont.title2)
                        .foregroundStyle(Color.textPrimary)
                    Text("一键扫描 · 智能清理 · 焕然如新")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
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
                Text("Smart Care")
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

    private func confirmHero(itemCount: Int, totalSize: Int64) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("发现 \(itemCount) 项可清理")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("预计释放 \(Self.formatBytes(totalSize))（移入废纸篓，可随时还原）")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("一键清理") { viewModel.confirm() }
                .buttonStyle(.borderedProminent)
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

    // MARK: - Module grid

    /// Module grid — Disk Health card (live grade) + Privacy + Assistant + Settings.
    private var moduleGrid: some View {
        HStack(spacing: AppSpacing.md) {
            DiskHealthCard(viewModel: diskHealthViewModel) {
                appState.navigation = .diskHealth
            }
            moduleCard(
                icon: "lock.shield",
                title: "隐私",
                subtitle: "浏览器 · 权限",
                destination: .privacy
            )
            moduleCard(
                icon: "sparkles",
                title: "清理助手",
                subtitle: "问一句就找到",
                destination: .assistant
            )
            moduleCard(
                icon: "gear",
                title: "设置",
                subtitle: "",
                destination: .settings
            )
        }
    }

    private func moduleCard(
        icon: String,
        title: String,
        subtitle: String,
        destination: AppState.NavigationItem
    ) -> some View {
        Button {
            appState.navigation = destination
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandPrimary)
                Spacer(minLength: 0)
                Text(title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AppSpacing.md)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
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
    SmartCareHeroView(
        viewModel: SmartCareViewModel(),
        diskHealthViewModel: DiskHealthViewModel()
    )
    .environmentObject(AppState())
    .frame(width: 700, height: 500)
}
#endif
