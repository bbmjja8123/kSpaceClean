import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .galaxy
    @Published public var rightPanelTab: RightPanelTab = .overview
    @Published public var rightPanelVisible = true
    @Published public var selectedCategory: FileCategory?
    @Published public var scanState: ScanState = .idle

    public enum NavigationItem: String, CaseIterable {
        case galaxy = "galaxy"
        case scan = "scan"
        case cleanup = "cleanup"
        case history = "history"
        case settings = "settings"

        // I12: deferred v2 modules — keep the enum cases only on the
        // Debug-only stub icon rail so the UI still parses. Production
        // iconRail already iterates `NavigationItem.allCases`; the
        // cases below are hidden behind `#if DEBUG` in the AppState
        // model. We do not ship a route for them in RootView.

        public var iconName: String {
            switch self {
            case .galaxy: return "sparkles"
            case .scan: return "magnifyingglass"
            case .cleanup: return "trash"
            case .history: return "clock"
            case .settings: return "gear"
            }
        }

        public var tooltip: String {
            switch self {
            case .galaxy: return "星系"
            case .scan: return "扫描"
            case .cleanup: return "清理"
            case .history: return "历史"
            case .settings: return "设置"
            }
        }
    }

    public enum RightPanelTab: String, CaseIterable {
        case overview = "\u{6982}\u{89C8}"
        case results = "\u{7ED3}\u{679C}\u{6811}"
        case suggestions = "\u{5EFA}\u{8BAE}"
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }
}
