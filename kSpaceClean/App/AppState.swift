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
        case largeFiles = "largeFiles"
        case duplicateFiles = "duplicateFiles"
        case uninstall = "uninstall"
        case privacy = "privacy"
        case photoClean = "photoClean"
        case maintenance = "maintenance"
        case settings = "settings"

        public var iconName: String {
            switch self {
            case .galaxy: return "sparkles"
            case .scan: return "magnifyingglass"
            case .cleanup: return "trash"
            case .history: return "clock"
            case .largeFiles: return "doc.circle"
            case .duplicateFiles: return "doc.on.doc"
            case .uninstall: return "trash.slash"
            case .privacy: return "hand.raised"
            case .photoClean: return "photo"
            case .maintenance: return "wrench.and.screwdriver"
            case .settings: return "gear"
            }
        }

        public var tooltip: String {
            switch self {
            case .galaxy: return "星系"
            case .scan: return "扫描"
            case .cleanup: return "清理"
            case .history: return "历史"
            case .largeFiles: return "大文件"
            case .duplicateFiles: return "重复文件"
            case .uninstall: return "卸载"
            case .privacy: return "隐私"
            case .photoClean: return "照片清理"
            case .maintenance: return "维护"
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
