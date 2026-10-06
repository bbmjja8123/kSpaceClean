import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    // P1 T1: SmartCare 降级为深链面（klaris://smartcare / Widget 按钮）——
    // 首屏让位给空间解剖（Klaris "explainable storage" 主轴）。
    @Published public var navigation: NavigationItem = .anatomy
    /// Selection detail panel (UX 重构 Phase 1/3): auto-hidden until a row
    /// is selected; ⌘I toggles it manually.
    @Published public var rightPanelVisible = false
    /// Row whose context the detail panel shows. Holds the node *id* —
    /// resolved live through `ScanResultsViewModel.node(for:)` so cascade
    /// changes never render stale values.
    @Published public var detailSelection: DetailSelection?
    // v2.5 Tab 化工具箱：打开的工具各自持一个 Tab（状态常驻不丢失）。
    @Published public private(set) var toolTabs: [ToolTab] = []
    @Published public private(set) var activeToolTabID: UUID?
    @Published public var selectedCategory: FileCategory?
    @Published public var scanState: ScanState = .idle

    public struct DetailSelection: Equatable {
        public enum Kind: Equatable { case category, app, file }
        public let nodeID: UUID
        public let kind: Kind

        public init(nodeID: UUID, kind: Kind) {
            self.nodeID = nodeID
            self.kind = kind
        }

        public static func == (lhs: DetailSelection, rhs: DetailSelection) -> Bool {
            lhs.nodeID == rhs.nodeID && lhs.kind == rhs.kind
        }
    }

    public enum NavigationItem: String, CaseIterable {
        case scan = "scan"
        case cleanup = "cleanup"
        case history = "history"
        case settings = "settings"
        // P1（Klaris）— 空间解剖首屏：解释"空间去哪儿了"（归因 → T5 视图）。
        case anatomy = "anatomy"
        case smartCare = "smartCare"
        case privacy = "privacy"
        case diskHealth = "diskHealth"
        // v2.0 — module surfaces (see plan: kWise 全面深度优化).
        case startupItems = "startupItems"
        case appUninstall = "appUninstall"
        case shredder = "shredder"
        // v2.0 — toolbox + creative surfaces. `.galaxy` (3D) was removed:
        // the 2D space map is `.spaceMap`. P2 T7: `.monthlyReport` 退役 ——
        // 月报并入历史页（叙事头 + 「本月」可展开区）。
        case tools = "tools"
        case spaceMap = "spaceMap"
        case duplicates = "duplicates"
        case largeOld = "largeOld"
        case photoClean = "photoClean"
        case maintenance = "maintenance"
        // P1 T8: `.assistant` 退役（问答内嵌 DetailPanel，AssistantNodePanel）。
        // P0 的 `.attribution` 验证面也已在 P1 T5 退役（工具箱卡直达 `.anatomy`），
        // 枚举残留一并清除。

        /// Fixed icon-rail order. P2 T1 (Klaris 单一主画布)：rail 收敛至
        /// 3 项 —— 扫描/清理/工具全部折进解剖画布（spec §2），深链/工具箱
        /// 面仍经 `allCases` 可达（case 保留至 W4 清扫）。
        public static var railItems: [NavigationItem] {
            [.anatomy, .history, .settings]
        }

        /// 工具箱八件套 —— 这些导航项以 Tab 方式打开（v2.5）。
        public var isToolboxTool: Bool {
            switch self {
            case .appUninstall, .duplicates, .largeOld, .photoClean,
                 .shredder, .startupItems, .spaceMap, .maintenance:
                return true
            default:
                return false
            }
        }

        public var iconName: String {
            switch self {
            case .scan: return "magnifyingglass"
            case .cleanup: return "trash"
            case .history: return "clock"
            case .settings: return "gear"
            case .anatomy: return "scale.3d"
            case .smartCare: return "wand.and.stars"
            case .privacy: return "lock.shield"
            case .diskHealth: return "internaldrive"
            case .startupItems: return "power"
            case .appUninstall: return "app.badge.checkmark"
            case .shredder: return "document.badge.ellipsis"
            case .tools: return "square.grid.2x2"
            case .spaceMap: return "circle.hexagongrid.circle"
            case .duplicates: return "doc.on.doc"
            case .largeOld: return "arrow.up.left.and.arrow.down.right"
            case .photoClean: return "photo.on.rectangle"
            case .maintenance: return "wrench.and.screwdriver"
            }
        }

        public var tooltip: String {
            switch self {
            case .scan: return String(localized: "nav.scan")
            case .cleanup: return String(localized: "nav.cleanup")
            case .history: return String(localized: "nav.history")
            case .settings: return String(localized: "nav.settings")
            case .anatomy: return String(localized: "nav.anatomy")
            case .smartCare: return String(localized: "nav.smartCare")
            case .privacy: return String(localized: "nav.privacy")
            case .diskHealth: return String(localized: "nav.diskHealth")
            case .startupItems: return String(localized: "nav.startupItems")
            case .appUninstall: return String(localized: "nav.appUninstall")
            case .shredder: return String(localized: "nav.shredder")
            case .tools: return String(localized: "nav.tools")
            case .spaceMap: return String(localized: "nav.spaceMap")
            case .duplicates: return String(localized: "nav.duplicates")
            case .largeOld: return String(localized: "nav.largeOld")
            case .photoClean: return String(localized: "nav.photoClean")
            case .maintenance: return String(localized: "nav.maintenance")
            }
        }
    }

    /// 一个打开的工具 Tab（工具箱根 Tab 固定存在，不入列）。
    public struct ToolTab: Identifiable, Equatable {
        public let id = UUID()
        public let item: NavigationItem
        public var title: String { item.tooltip }
        public var icon: String { item.iconName }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }

    // MARK: - Tool tab lifecycle (v2.5)

    /// 打开（或激活）一个工具 Tab；已开则激活既有 Tab（状态不重建）。
    public func openToolTab(_ item: NavigationItem) {
        guard item.isToolboxTool else {
            navigation = item
            return
        }
        if let existing = toolTabs.first(where: { $0.item == item }) {
            activeToolTabID = existing.id
        } else {
            let tab = ToolTab(item: item)
            toolTabs.append(tab)
            activeToolTabID = tab.id
        }
        navigation = item
    }

    /// 点击某个 Tab 激活。
    public func activateToolTab(_ id: UUID) {
        guard let tab = toolTabs.first(where: { $0.id == id }) else { return }
        activeToolTabID = id
        navigation = tab.item
    }

    /// 关闭 Tab；关掉激活中的 Tab 时落到最后一个剩余 Tab，没有则回工具箱。
    public func closeToolTab(_ id: UUID) {
        let wasActive = activeToolTabID == id
        toolTabs.removeAll { $0.id == id }
        guard wasActive else { return }
        if let last = toolTabs.last {
            activeToolTabID = last.id
            navigation = last.item
        } else {
            activeToolTabID = nil
            navigation = .tools
        }
    }
}
