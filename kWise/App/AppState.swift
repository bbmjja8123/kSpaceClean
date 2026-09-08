import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .smartCare  // v1.5: home is the Smart Care surface (Q1 Hybrid UI)
    /// Selection detail panel (UX 重构 Phase 1/3): auto-hidden until a row
    /// is selected; ⌘I toggles it manually.
    @Published public var rightPanelVisible = false
    /// Row whose context the detail panel shows. Holds the node *id* —
    /// resolved live through `ScanResultsViewModel.node(for:)` so cascade
    /// changes never render stale values.
    @Published public var detailSelection: DetailSelection?
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
        case smartCare = "smartCare"
        case privacy = "privacy"
        case diskHealth = "diskHealth"
        // v2.0 — module surfaces (see plan: kWise 全面深度优化).
        case startupItems = "startupItems"
        case appUninstall = "appUninstall"
        case shredder = "shredder"
        // v2.0 — toolbox + creative surfaces. `.galaxy` (3D) was removed:
        // the 2D space map is `.spaceMap`.
        case tools = "tools"
        case spaceMap = "spaceMap"
        case monthlyReport = "monthlyReport"
        case assistant = "assistant"
        case duplicates = "duplicates"
        case largeOld = "largeOld"
        case photoClean = "photoClean"
        case maintenance = "maintenance"

        /// Fixed icon-rail order (v2.0 Phase 2). The rail no longer grows
        /// with every module — deep surfaces live in the toolbox and are
        /// reachable via deep links + `allCases`.
        public static var railItems: [NavigationItem] {
            [.smartCare, .scan, .tools, .cleanup, .history, .settings]
        }

        public var iconName: String {
            switch self {
            case .scan: return "magnifyingglass"
            case .cleanup: return "trash"
            case .history: return "clock"
            case .settings: return "gear"
            case .smartCare: return "wand.and.stars"
            case .privacy: return "lock.shield"
            case .diskHealth: return "internaldrive"
            case .startupItems: return "power"
            case .appUninstall: return "app.badge.checkmark"
            case .shredder: return "document.badge.ellipsis"
            case .tools: return "square.grid.2x2"
            case .spaceMap: return "circle.hexagongrid.circle"
            case .monthlyReport: return "chart.bar.doc.horizontal"
            case .assistant: return "sparkles"
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
            case .smartCare: return String(localized: "nav.smartCare")
            case .privacy: return String(localized: "nav.privacy")
            case .diskHealth: return String(localized: "nav.diskHealth")
            case .startupItems: return String(localized: "nav.startupItems")
            case .appUninstall: return String(localized: "nav.appUninstall")
            case .shredder: return String(localized: "nav.shredder")
            case .tools: return String(localized: "nav.tools")
            case .spaceMap: return String(localized: "nav.spaceMap")
            case .monthlyReport: return String(localized: "nav.monthlyReport")
            case .assistant: return String(localized: "nav.assistant")
            case .duplicates: return String(localized: "nav.duplicates")
            case .largeOld: return String(localized: "nav.largeOld")
            case .photoClean: return String(localized: "nav.photoClean")
            case .maintenance: return String(localized: "nav.maintenance")
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
