// kWise/Features/SmartScan/ScanResultGroups.swift
//
// Legacy scan-result grouping model, extracted from the deleted
// ScanResultsTreeView (UX 重构 Phase 1). The legacy `ScanViewModel` still
// builds these for its remaining consumers (`Intents/ScanIntent.swift`,
// `PrivacyView`); the main scan surface no longer uses this shape.
import SwiftUI

// MARK: - Tree Data Models

/// A single file result in the scan results tree (3rd level)
@MainActor
public struct ScanResultNode: Identifiable {
    public let fileEntry: FileEntry
    public let subCategoryID: Int
    public let actionID: Int
    public let appName: String?
    public let isRecommended: Bool
    public let isCaution: Bool
    public let cautionID: Int?
    public let size: Int64
    public let path: String
    public let fileName: String
    public var isSelected: Bool

    public var id: UUID { fileEntry.id ?? UUID() }

    /// 4-level risk classification (v3 spec)
    public var riskLevel: RiskLevel {
        RiskLevel.from(recommended: isRecommended, cautionID: cautionID)
    }

    public init(fileEntry: FileEntry, appName: String? = nil, cautionID: Int? = nil) {
        self.fileEntry = fileEntry
        self.subCategoryID = Int(fileEntry.subCategoryID)
        self.actionID = Int(fileEntry.actionID)
        self.appName = appName
        self.isRecommended = fileEntry.isRecommended
        self.isCaution = cautionID != nil && cautionID != 0
        self.cautionID = cautionID
        self.size = fileEntry.size
        self.path = fileEntry.path ?? ""
        self.fileName = URL(fileURLWithPath: self.path).lastPathComponent
        self.isSelected = fileEntry.isRecommended
    }
}

/// Single action-level grouping (2nd level — ex: "微信聊天图片", "微信日志").
@MainActor
public struct ActionGroup: Identifiable {
    public let id: Int          // actionID
    public let title: String
    public let appName: String?
    public let isRecommended: Bool
    public let cautionID: Int?
    public var items: [ScanResultNode]
    public var isExpanded: Bool = true

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    public var isAllSelected: Bool { !items.isEmpty && items.allSatisfy(\.isSelected) }

    /// Risk level = worst (highest) risk among all items
    public var riskLevel: RiskLevel {
        items.map(\.riskLevel).max() ?? .recommended
    }

    /// 3-state checkbox computed from item selection
    public var checkState: CheckState {
        let total = items.count
        guard total > 0 else { return .unchecked }
        let selectedCount = items.filter(\.isSelected).count
        return CheckState.from(selected: false, total: total, selectedCount: selectedCount)
    }

    public init(id: Int, title: String, appName: String? = nil,
                isRecommended: Bool = true, cautionID: Int? = nil,
                items: [ScanResultNode]) {
        self.id = id
        self.title = title
        self.appName = appName
        self.isRecommended = isRecommended
        self.cautionID = cautionID
        self.items = items
    }
}

/// A grouped category (top level) — contains a list of ActionGroup (2nd level),
/// with an optional flat `items` for backward compatibility.
@MainActor
public struct ScanResultGroup: Identifiable {
    public let id: Int  // subCategoryID
    public let title: String
    public let appName: String?
    public var items: [ScanResultNode]
    public var actionGroups: [ActionGroup]

    public var totalSize: Int64 {
        actionGroups.isEmpty
            ? items.reduce(0) { $0 + $1.size }
            : actionGroups.reduce(0) { $0 + $1.totalSize }
    }
    public var selectedSize: Int64 {
        actionGroups.isEmpty
            ? items.filter(\.isSelected).reduce(0) { $0 + $1.size }
            : actionGroups.reduce(0) { $0 + $1.selectedSize }
    }
    public var totalItems: Int {
        actionGroups.isEmpty
            ? items.count
            : actionGroups.reduce(0) { $0 + $1.items.count }
    }

    /// Highest risk level among all action groups
    public var highestRisk: RiskLevel {
        actionGroups.map(\.riskLevel).max() ?? .recommended
    }

    public init(id: Int, title: String, appName: String? = nil,
                items: [ScanResultNode] = [], actionGroups: [ActionGroup] = []) {
        self.id = id
        self.title = title
        self.appName = appName
        self.items = items
        self.actionGroups = actionGroups
    }
}
