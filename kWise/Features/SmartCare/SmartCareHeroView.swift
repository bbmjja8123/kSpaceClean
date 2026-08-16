import SwiftUI
import DesignSystem

/// Hybrid UI first screen (v1.5).
///
/// Renders the home surface: a hero CTA for Smart Care + a 3-card module
/// grid (Privacy / Disk Health / Settings). Replaces the prior
/// "default ScanResults" first screen per Q1 of the v1.5 grill-me
/// convergence.
///
/// - C-2 (SHOULD): hero CTA occupies ≤30% of available vertical area.
///
/// Phase B (Task 3+) wires the hero CTA action to
/// `SmartCareOrchestrator.start()`. For now (Task 2 shell), the CTA is
/// a no-op.
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 2.
struct SmartCareHeroView: View {
    @EnvironmentObject var appState: AppState

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

    /// Hero CTA — C-2 SHOULD ≤30% visual area.
    /// Phase B replaces this empty action with `SmartCareOrchestrator.start()`.
    private var heroCard: some View {
        Button(action: {}) {
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
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color.brandPrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
    }

    /// Module grid — Privacy / Disk Health / Settings.
    private var moduleGrid: some View {
        HStack(spacing: AppSpacing.md) {
            moduleCard(
                icon: "lock.shield",
                title: "隐私",
                subtitle: "浏览器 · 权限",
                destination: .privacy
            )
            moduleCard(
                icon: "internaldrive",
                title: "磁盘健康",
                subtitle: "S.M.A.R.T. · 卷",
                destination: .diskHealth
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
}

#if DEBUG
#Preview {
    SmartCareHeroView()
        .environmentObject(AppState())
        .frame(width: 700, height: 500)
}
#endif