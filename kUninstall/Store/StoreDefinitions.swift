import Foundation

// MARK: - Product Identifiers

enum StoreProduct: String, CaseIterable {
    case proUnlock = "app.kraftly.kuninstall.pro"

    var displayName: String {
        switch self {
        case .proUnlock: return "kUninstall Pro"
        }
    }

    var priceTier: String { "$9.99" }
}

// MARK: - Pro Feature Definitions

enum ProFeature: String, CaseIterable {
    case deepClean
    case startupManagement
    case batchUninstall
    case visualization
    case widget
    case shortcuts
    case aiAnalysis

    var displayDescription: String {
        switch self {
        case .deepClean:           return "深度系统清理"
        case .startupManagement:   return "启动项管理"
        case .batchUninstall:      return "批量卸载"
        case .visualization:       return "应用体积可视化"
        case .widget:              return "桌面 Widget"
        case .shortcuts:           return "Shortcuts 集成"
        case .aiAnalysis:          return "AI 使用分析"
        }
    }

    var icon: String {
        switch self {
        case .deepClean:           return "gearshape.2"
        case .startupManagement:   return "power"
        case .batchUninstall:      return "trash.slash"
        case .visualization:       return "chart.pie"
        case .widget:              return "square.grid.2x2"
        case .shortcuts:           return "command"
        case .aiAnalysis:          return "brain"
        }
    }
}
