import SwiftUI

/// The single navigation authority.
///
/// All navigation mutations (`appState.navigation`, presented sheets) go
/// through here so deep links, the icon rail, widget/intent opens, and the
/// menu bar cannot disagree. Views stop assigning `appState.navigation`
/// directly; they call ``navigate(to:)`` or a deep link.
///
/// P2 T9（spec §7 深链终态）：可导航面只剩 anatomy / history / settings。
/// 深链映射 ——
/// - `klaris://scan?path=` → anatomy（扫描即动作，hero 发起；Finder 扩展入口）
/// - `klaris://smartcare` → anatomy（hero「安全快捷回收」承接）
/// - `klaris://health`    → anatomy（DiskHealthCard 在画布上，点击出详情 sheet）
/// - `klaris://history`   → history（通知深链 / 时间线）
/// - `klaris://settings`  → settings
/// 已退役面的旧深链（clean/privacy/startup/uninstall/shred/tools/spacemap/
/// report/duplicates/largefiles/photoclean/maintenance）不再处理 —— 返回
/// false 走「未处理」，绝不把用户引向一个不存在的表面。P3：卸载/启动项
/// 的 UI 已重接入，但走「+」菜单 sheet（无外部深链消费者 —— widget 只用
/// smartcare），不为它们恢复路由。
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
            // spec §7：`scan?path=` 保留 —— Finder 扩展「用 Klaris 扫描」
            // 的上下文入口。落解剖画布（扫描即动作，hero 发起扫描）。
            navigate(to: .anatomy)
            return true
        case "smartcare":
            // Widget 一键清理按钮 → 画布 hero（快捷回收入口在 hero 上）。
            navigate(to: .anatomy)
            return true
        case "health":
            // DiskHealthCard 内嵌画布（spec §7）—— 深链落首屏，点击卡片
            // 打开详情 sheet。
            navigate(to: .anatomy)
            return true
        case "history":
            // 清理完成通知深链（CleanupNotificationSink）→ 时间线。
            navigate(to: .history)
            return true
        case "settings":
            navigate(to: .settings)
            return true
        case "report", "monthlyreport":
            // P2 T7：月报已并入历史页 —— 深链诚实落到历史（叙事头 + 本月区）。
            navigate(to: .history)
            return true
        // P2 T9：`clean/privacy/startup/uninstall/shred/tools/spacemap/
        // duplicates/largefiles/photoclean/maintenance` 随对应表面退役，
        // 一律落到 default → false（诚实未处理）。
        default:
            return false
        }
    }

    // MARK: - Navigation

    /// Navigate to a specific page.
    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
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
