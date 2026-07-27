import SwiftUI
import DesignSystem
import CommonUtils

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

// MARK: - Tree View

/// Lemon-style expandable scan results tree (Category → Action → File)
/// with summary bar at bottom.
struct ScanResultsTreeView: View {
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.resultGroups) { group in
                    if group.actionGroups.isEmpty {
                        // Legacy 1-level fallback
                        Section {
                            CategoryHeader(group: group, viewModel: viewModel)
                            ForEach(group.items) { node in
                                FileResultRow(node: node, viewModel: viewModel)
                                    .padding(.leading, AppSpacing.lg)
                            }
                        }
                    } else {
                        Section {
                            CategoryHeader(group: group, viewModel: viewModel)
                            ForEach(group.actionGroups) { actionGroup in
                                ActionHeader(actionGroup: actionGroup, viewModel: viewModel)
                                if actionGroup.isExpanded {
                                    ForEach(actionGroup.items) { node in
                                        FileResultRow(node: node, viewModel: viewModel)
                                            .padding(.leading, AppSpacing.lg)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)

            ScanSummaryBar(
                totalItems: viewModel.scanResults.count,
                totalSize: viewModel.scanResults.reduce(0) { $0 + $1.size },
                selectedItems: viewModel.selectedCount,
                selectedSize: viewModel.selectedSize,
                onCleanup: { viewModel.startCleanup() }
            )
        }
    }
}

// MARK: - Category Header (Top Level)

private struct CategoryHeader: View {
    let group: ScanResultGroup
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.appName ?? group.title)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                if group.appName != nil {
                    Text(group.title)
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Item count summary
            if group.actionGroups.isEmpty {
                Text("\(group.items.count) 项")
                    .font(AppFont.caption).foregroundColor(.textSecondary)
            } else {
                Text("\(group.actionGroups.count) 类 · \(group.totalItems) 项")
                    .font(AppFont.caption).foregroundColor(.textSecondary)
            }

            Text(FileSizeFormatter.abbreviated(from: group.totalSize))
                .font(AppFont.monoDigit)
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 8)
        .background(Color.brandPrimary.opacity(0.05))
    }
}

// MARK: - Action Header (2nd Level)

private struct ActionHeader: View {
    let actionGroup: ActionGroup
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Expand/collapse chevron
            Image(systemName: actionGroup.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)
                .onTapGesture { viewModel.toggleActionExpanded(actionGroup.id) }

            // Select-all checkbox
            Image(systemName: actionGroup.isAllSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(actionGroup.isAllSelected ? .brandPrimary : .textSecondary)
                .onTapGesture { viewModel.toggleActionGroup(actionGroup.id) }

            // Title
            Text(actionGroup.title)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            // Badges
            if actionGroup.cautionID != nil && actionGroup.cautionID != 0 {
                Text("注意")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            } else if !actionGroup.isRecommended {
                Text("可选")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.textSecondary.opacity(0.2))
                    .foregroundColor(.textSecondary)
                    .clipShape(Capsule())
            } else {
                Text("推荐")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.success.opacity(0.2))
                    .foregroundColor(.success)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: actionGroup.totalSize))
                .font(AppFont.monoDigit).foregroundColor(.textSecondary)
            Text("\(actionGroup.items.count)")
                .font(AppFont.caption).foregroundColor(.textSecondary)
        }
        .padding(.vertical, 4)
        .padding(.leading, AppSpacing.lg)
    }
}

// MARK: - File Result Row (3rd Level)

private struct FileResultRow: View {
    let node: ScanResultNode
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Checkbox
            Image(systemName: node.isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(node.isSelected ? .brandPrimary : .textSecondary)
                .onTapGesture { viewModel.toggleItem(node.id) }

            // Risk badge
            if node.isCaution {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            // File icon by category
            if let cat = FileCategory(rawValue: node.fileEntry.category ?? "") {
                Image(systemName: cat.icon)
                    .font(.system(size: 10))
                    .foregroundColor(cat.color)
            }

            // File name
            Text(node.fileName)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer()

            // Size
            Text(FileSizeFormatter.abbreviated(from: node.size))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Summary Bar

struct ScanSummaryBar: View {
    let totalItems: Int
    let totalSize: Int64
    let selectedItems: Int
    let selectedSize: Int64
    let onCleanup: () -> Void

    var body: some View {
        HStack {
            Text("共 \(totalItems) 项 · \(FileSizeFormatter.abbreviated(from: totalSize))")
                .font(AppFont.caption).foregroundColor(.textSecondary)
            Text("|")
                .font(AppFont.caption).foregroundColor(.separatorColor)
            Text("已选 \(selectedItems) 项 · \(FileSizeFormatter.abbreviated(from: selectedSize))")
                .font(AppFont.caption).foregroundColor(.brandPrimary)
            Spacer()
            Button(action: onCleanup) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("清理 (\(selectedItems))")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.danger)
            .disabled(selectedItems == 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 6)
    }
}
