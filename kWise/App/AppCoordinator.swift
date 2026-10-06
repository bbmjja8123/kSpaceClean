import SwiftUI

/// The single navigation authority.
///
/// All navigation mutations (`appState.navigation`, presented sheets) go
/// through here so deep links, the icon rail, widget/intent opens, and the
/// menu bar cannot disagree. Views stop assigning `appState.navigation`
/// directly; they call ``navigate(to:)`` or a deep link.
@MainActor
public final class AppCoordinator: ObservableObject {
    public weak var appState: AppState?

    /// Presented sheet, if any (e.g. PaywallView triggered by the free tier).
    @Published public var presentedSheet: SheetKind?

    public enum SheetKind: Equatable {
        case paywall
    }

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Deep links (klaris://)

    /// Handle an incoming deep link URL. Returns `true` when handled.
    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme,
              scheme == "klaris"
        else { return false }
        // klaris://scan → host "scan"
        guard let host = url.host else { return false }

        switch host {
        case "scan":
            navigate(to: .scan)
            return true
        case "clean":
            return handleCleanLink(url)
        case "smartcare":
            // P1 T1: SmartCare 降级 — 深链与 Widget 一键清理按钮落在解剖
            // 首屏（R1），其快捷回收入口由 T5/T6 在 anatomy 视图内承接。
            navigate(to: .anatomy)
            return true
        case "privacy":
            navigate(to: .privacy)
            return true
        case "health":
            // P2 T1: DiskHealthCard 已内嵌解剖画布（spec §7）—— 深链落
            // 首屏而非独立磁盘健康详情页。
            navigate(to: .anatomy)
            return true
        case "startup":
            navigate(to: .startupItems)
            return true
        case "uninstall":
            openToolTab(.appUninstall)
            return true
        case "shred":
            openToolTab(.shredder)
            return true
        case "tools":
            navigate(to: .tools)
            return true
        case "spacemap":
            navigate(to: .spaceMap)
            return true
        case "report", "monthlyreport":
            // P2 T7: 月报已并入历史页 —— 深链诚实落到历史（叙事头 + 本月区）。
            navigate(to: .history)
            return true
        // P1 T8: klaris://assistant 随聊天框退役（问答内嵌 DetailPanel，
        // 无独立导航面）。未知 host 走 default → false。
        case "duplicates":
            openToolTab(.duplicates)
            return true
        case "largefiles":
            openToolTab(.largeOld)
            return true
        case "photoclean":
            openToolTab(.photoClean)
            return true
        case "maintenance":
            openToolTab(.maintenance)
            return true
        case "history":
            navigate(to: .history)
            return true
        case "settings":
            navigate(to: .settings)
            return true
        default:
            return false
        }
    }

    /// `klaris://clean?path=/some/file` — the Finder extension's context-menu
    /// deep link. The `path` parameter was historically ignored; it now
    /// pre-seeds the cleanup surface with that file (v2.0 Phase 2).
    private func handleCleanLink(_ url: URL) -> Bool {
        navigate(to: .cleanup)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
           !path.isEmpty {
            cleanLinkSeed = path
        }
        return true
    }

    /// Last path received via a clean deep link, consumed by the cleanup
    /// surface (`CleanupContentView`) to pre-select the target.
    @Published public var cleanLinkSeed: String?

    // MARK: - Navigation

    /// Navigate to a specific page.
    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }

    /// 打开一个工具 Tab（v2.5）：已开激活、未开新建，然后导航。
    /// 工具箱卡片与工具类 deep link 都走这里（导航唯一权威）。
    public func openToolTab(_ item: AppState.NavigationItem) {
        appState?.openToolTab(item)
    }

    /// Present the paywall sheet (free-tier gate — never ad hoc from views).
    public func presentPaywall() {
        presentedSheet = .paywall
    }
}

/// `.sheet(item:)` requires Identifiable; the kind itself is the identity
/// (there is at most one sheet of each kind on screen).
extension AppCoordinator.SheetKind: Identifiable {
    public var id: Self { self }
}
