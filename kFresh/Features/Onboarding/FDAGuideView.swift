import SwiftUI

/// Five-page first-launch onboarding, per `CLAUDE.md` §5.4.
///
/// Walks the user from a welcome screen through the value proposition, the
/// permission request, the privacy commitment, and a final ready screen.
/// Page state lives in ``FDAGuideController``.
///
/// - Note: The pages are laid out with an animated `switch` rather than a
///   paged `TabView`. `tabViewStyle(.page)` is unavailable on macOS, so the
///   transition is driven directly from ``KFAnimation`` tokens instead.
struct FDAGuideView: View {
    @StateObject private var controller: FDAGuideController

    /// Called once the user finishes or skips to the end of onboarding.
    private let onFinished: () -> Void

    /// Opens System Settings so the user can grant Full Disk Access.
    private let authorizer = FDAuthorizer()

    /// Creates the onboarding flow.
    ///
    /// - Parameters:
    ///   - controller: State machine backing the flow.
    ///   - onFinished: Invoked when onboarding completes, so the host can dismiss it.
    init(controller: FDAGuideController, onFinished: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: controller)
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            pageIndicator
                .padding(.bottom, AppSpacing.xl)
        }
        .frame(width: 560, height: 520)
        .brandBackground()
        .task { await controller.refreshFDAStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refreshFDAStatus() }
        }
        .onChange(of: controller.isCompleted) { completed in
            if completed { onFinished() }
        }
    }

    // MARK: - Pages

    @ViewBuilder private var pageContent: some View {
        ZStack {
            switch controller.currentPage {
            case .welcome: welcomePage
            case .value: valuePage
            case .permission: permissionPage
            case .privacy: privacyPage
            case .ready: readyPage
            }
        }
        .animation(KFAnimation.easeInOut, value: controller.currentPage)
    }

    private var welcomePage: some View {
        FDAGuidePage(
            icon: "sparkles",
            title: "kFresh",
            subtitle: "让 App 卸载彻底干净",
            message: "删一个 App，连它留下的所有痕迹一起清干净。",
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
        .transition(pageTransition)
    }

    private var valuePage: some View {
        FDAGuidePage(
            icon: "checklist",
            title: "三件套",
            message: """
            • 残留文件扫描 — 找出卸载后遗留的配置与缓存
            • 启动项管理 — 停掉不再需要的后台项目
            • 30 天可回滚 — 删错了随时还原
            """,
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
        .transition(pageTransition)
    }

    private var permissionPage: some View {
        FDAGuidePage(
            icon: "lock.shield",
            title: "需要的权限",
            subtitle: "所有权限仅在本地使用，绝不上传",
            message: """
            • 完全磁盘访问权限 — 扫描 ~/Library 下的残留文件
            • 自动化（可选）— Finder 右键菜单集成
            """,
            ctaTitle: "打开系统设置授权",
            ctaAction: requestFullDiskAccess,
            secondaryTitle: "跳过（仅基础模式）",
            secondaryAction: controller.skipFromPermission,
            accessory: AnyView(fdaStatusBadge)
        )
        .transition(pageTransition)
    }

    private var privacyPage: some View {
        FDAGuidePage(
            icon: "hand.raised",
            title: "隐私承诺",
            message: """
            • 零网络 — 已在 entitlements 中禁用联网
            • 本地计算 — 所有扫描与分析都在你的 Mac 上完成
            • 不收集数据 — App Store 隐私标签为 Data Not Collected
            """,
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
        .transition(pageTransition)
    }

    private var readyPage: some View {
        FDAGuidePage(
            icon: "checkmark.seal",
            title: "准备好了",
            message: "你可以随时在「设置 → FDA 状态」中重新授权。",
            ctaTitle: "开始使用",
            ctaAction: controller.advance
        )
        .transition(pageTransition)
    }

    // MARK: - Supporting views

    /// Live Full Disk Access status, so the user can confirm the grant took
    /// effect without leaving onboarding.
    @ViewBuilder private var fdaStatusBadge: some View {
        switch controller.fdaStatus {
        case .unknown:
            EmptyView()
        case .basic:
            Label("尚未授权 — 将以基础模式运行", systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.callout)
                .foregroundColor(.warning)
        case .full:
            Label("已获得完全磁盘访问权限", systemImage: "checkmark.circle.fill")
                .font(AppFont.callout)
                .foregroundColor(.success)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(FDAGuideController.Page.allCases, id: \.rawValue) { page in
                Circle()
                    .fill(page == controller.currentPage ? Color.brandPrimary : Color.separatorColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(page == controller.currentPage ? KFAnimation.scaleHover : 1)
                    .animation(KFAnimation.easeInOut, value: controller.currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "第 \(controller.currentPage.rawValue + 1) 页，共 \(FDAGuideController.Page.allCases.count) 页"
        )
    }

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: KFAnimation.scaleInsert))
    }

    // MARK: - Actions

    /// Opens System Settings, then re-probes so the badge reflects the result
    /// when the user comes back.
    ///
    /// The status also refreshes when the app regains activation from System
    /// Settings (via ``didBecomeActiveNotification``), so a grant made while
    /// onboarding stays open is picked up without a manual re-trigger.
    private func requestFullDiskAccess() {
        authorizer.requestFDA()
        Task { await controller.refreshFDAStatus() }
    }
}
