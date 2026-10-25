import SwiftUI
import DesignSystem

// MARK: - Page 1: Value Proposition

struct OnboardingPage1: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Color.brandPrimary)

            VStack(spacing: AppSpacing.sm) {
                Text("更快,更干净")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text("智能磁盘清理，让您的 Mac 存储空间回到\"足够\"")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Page 2: Scan Promises + Home Folder Grant (merged)
//
// P2 T8 5→3 页收敛：原「核心功能」页、「隐私承诺」页与「主目录授权」页
// 合并为一页 —— 扫描开始前把三件事一次说清楚：
// 1. 三类承诺：智能扫描 / 智能归因（本机规则归因，零网络）/ 一键清理；
// 2. 隐私承诺：所有计算在本机完成，零数据上报；
// 3. 授权：一次性主目录授权（PowerScope security-scoped bookmark，见
//    kFoundation `PowerScope`），可跳过 —— 跳过后扫描在 container-only
//    范围内仍可运行，能清理的组会变少（诚实降级，不空跑）。

/// PowerScope grant page — replaces the old Full Disk Access instructions.
///
/// MAS sandboxing makes FDA unobtainable; the honest ask is a one-time
/// NSOpenPanel grant of the home folder, persisted as a security-scoped
/// bookmark (see `PowerScope` in kFoundation).
struct OnboardingPage2: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var appScope = AppScope.shared

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: String.LocalizationValue("ob3.promiseTitle")))
                        .font(AppFont.largeTitle)
                        .foregroundColor(.textPrimary)
                }
                .padding(.top, AppSpacing.xl)

                VStack(spacing: AppSpacing.xs) {
                    FeatureRow(
                        icon: "magnifyingglass",
                        title: String(localized: String.LocalizationValue("onboarding.page2.feature.scan.title")),
                        description: String(localized: String.LocalizationValue("onboarding.page2.feature.scan.body"))
                    )
                    FeatureRow(
                        icon: "brain",
                        title: String(localized: String.LocalizationValue("onboarding.page2.feature.attribution.title")),
                        description: String(localized: String.LocalizationValue("onboarding.page2.feature.attribution.body"))
                    )
                    FeatureRow(
                        icon: "trash",
                        title: String(localized: String.LocalizationValue("onboarding.page2.feature.clean.title")),
                        description: String(localized: String.LocalizationValue("onboarding.page2.feature.clean.body"))
                    )
                }
                .padding(.horizontal, AppSpacing.xxl)

                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "lock.shield")
                        .font(.title3)
                        .foregroundStyle(Color.success)
                    Text(String(localized: String.LocalizationValue("onboarding.page2.privacyNote")))
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xxl)

                Divider()
                    .padding(.horizontal, AppSpacing.xxl)

                grantBlock
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.bottom, AppSpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgCanvas)
    }

    // MARK: Grant block（原独立授权页迁入）
    //
    // P3 双渠道：MAS 版走 PowerScope 主目录书签授权；直营版无沙盒，
    // 授权块替换为静态说明面板（Full Disk Access 由系统 TCC 自管，
    // 不弹 NSOpenPanel，跳过按钮无意义因此隐藏）。

    @ViewBuilder
    private var grantBlock: some View {
        if DistributionChannel.isSandboxed {
            sandboxGrantBlock
        } else {
            directEditionBlock
        }
    }

    private var sandboxGrantBlock: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "folder.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)

            VStack(spacing: AppSpacing.xs) {
                Text(String(localized: String.LocalizationValue("授权主目录访问")))
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)

                Text("kWise 在沙箱内运行，需要你一次性授权主目录才能扫描缓存、日志与应用残留。文件不会被上传，扫描全部在本机完成。")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await appScope.grant() }
            } label: {
                Label(appScope.capability.level == .homeGranted
                      ? String(localized: String.LocalizationValue("onboarding.grant.rechoose"))
                      : String(localized: String.LocalizationValue("common.grantHome")),
                      systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
                    .font(AppFont.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPrimary)
            .controlSize(.large)

            if appScope.capability.level == .homeGranted {
                Label(String(localized: String.LocalizationValue("onboarding.grant.granted")),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.stateSuccess)
                    .font(AppFont.callout)
            }

            Button(String(localized: String.LocalizationValue("onboarding.grant.skipButton")),
                   action: coordinator.skipGrant)
                .buttonStyle(.plain)
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)
                .underline()
        }
    }

    /// 直营版：无沙盒，磁盘访问由系统 Full Disk Access 语义覆盖 ——
    /// 静态说明 + 主目录就绪状态，无授权按钮。
    private var directEditionBlock: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)

            VStack(spacing: AppSpacing.xs) {
                Text(String(localized: String.LocalizationValue("common.scope.fullAccess.title")))
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)

                Text(String(localized: String.LocalizationValue("onboarding.grant.directBody")))
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Label(String(localized: String.LocalizationValue("onboarding.grant.directHomeReady")),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.stateSuccess)
                .font(AppFont.callout)
        }
    }
}

// MARK: - Page 3: Ready to Scan
//
// 完成即扫（P2 T8）：本页收尾的「开始首次扫描」/「完成」都会走
// coordinator.next() → onComplete → RootView 经 FirstScanGate 触发一次
// anatomyViewModel.startScan() —— 扫描在主画布 hero 上进行，用户落地即见进度。

struct OnboardingPage3: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.success)

            VStack(spacing: AppSpacing.sm) {
                Text("准备就绪")
                    .font(AppFont.largeTitle)
                    .foregroundColor(.textPrimary)

                Text(String(localized: String.LocalizationValue("ob3.firstScanSubtitle")))
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Button {
                coordinator.next()
            } label: {
                Text("开始首次扫描")
                    .frame(maxWidth: .infinity)
                    .font(AppFont.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Container

struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @StateObject private var coordinator = OnboardingCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            // UX 重构 Phase 1: a switch instead of a label-less TabView —
            // the native tab strip rendered as an empty artifact strip.
            ZStack {
                switch coordinator.currentPage {
                case 0: OnboardingPage1()
                case 1: OnboardingPage2(coordinator: coordinator)
                default: OnboardingPage3(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(KFAnimation.easeInOut, value: coordinator.currentPage)
            .transition(.opacity)

            StepIndicatorView(count: coordinator.totalPages,
                              current: coordinator.currentPage)
                .padding(.vertical, AppSpacing.md)

            Divider()
                .foregroundColor(.separatorColor)

            // Bottom navigation bar — unconditional; last page shows 完成.
            HStack(spacing: AppSpacing.md) {
                Button(String(localized: String.LocalizationValue("onboarding.nav.back"))) {
                    withAnimation(KFAnimation.easeInOut) { coordinator.back() }
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.currentPage == 0)

                Spacer()

                Text(String(format: String(localized: String.LocalizationValue("onboarding.nav.step")),
                            coordinator.currentPage + 1, coordinator.totalPages))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)

                Button(coordinator.currentPage == coordinator.totalPages - 1
                       ? String(localized: String.LocalizationValue("onboarding.nav.done"))
                       : String(localized: String.LocalizationValue("onboarding.nav.next"))) {
                    withAnimation(KFAnimation.easeInOut) { coordinator.next() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .background(Color.bgPrimary)
        }
        .frame(minWidth: 540, minHeight: 500)
        .background(Color.bgPrimary)
        .onAppear {
            coordinator.onComplete = onComplete
        }
    }
}

// MARK: - Step Indicator

/// 3 dots + current highlight, so the user always knows where they are
/// (UX 重构 Phase 1 — fixes "不知道有几个步骤，当前处于哪个").
struct StepIndicatorView: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.brandPrimary : Color.bgSecondary)
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(KFAnimation.easeInOut, value: current)
            }
        }
    }
}
