import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    // P2 T9（spec §2 单一主画布）：导航收敛为 3 面 —— 解剖画布（首屏）/
    // 历史 / 设置。下钻页（GroupDrillDownView）在 AnatomyView 内部路由，
    // 粉碎窗 / 磁盘健康详情以 sheet 呈现，不再占据导航枚举。
    @Published public var navigation: NavigationItem = .anatomy
    /// v2.1 UX 重构遗留的选中态（detail panel 已随 `.scan` 独立页在 P2 T9
    /// 退役；属性保留供既有状态测试 —— 恒 nil，无 UI 消费者）。
    @Published public var selectedCategory: FileCategory?
    @Published public var scanState: ScanState = .idle

    public enum NavigationItem: String, CaseIterable {
        // P2 T9（spec §2/§9）：`.scan/.cleanup/.smartCare/.privacy/.diskHealth/
        // .startupItems/.appUninstall/.shredder/.tools/.spaceMap/.duplicates/
        // .largeOld/.photoClean/.maintenance` 全部退役 —— 扫描/清理/工具折进
        // 解剖画布，隐私/维护并入设置，粉碎走「+」菜单 sheet，月报并入历史。
        // 更早退役：`.galaxy`（2D 空间地图替代）、`.monthlyReport`（并入历史
        // 叙事头，P2 T7）、`.assistant` / `.attribution`（P1 T8/T5）。
        case anatomy = "anatomy"
        case history = "history"
        case settings = "settings"

        /// Fixed icon-rail order（P2 T1 收敛为 3 项；T9 起与 `allCases` 恒等）。
        public static var railItems: [NavigationItem] {
            [.anatomy, .history, .settings]
        }

        public var iconName: String {
            switch self {
            case .anatomy: return "scale.3d"
            case .history: return "clock"
            case .settings: return "gear"
            }
        }

        public var tooltip: String {
            switch self {
            case .anatomy: return String(localized: "nav.anatomy")
            case .history: return String(localized: "nav.history")
            case .settings: return String(localized: "nav.settings")
            }
        }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }
}
