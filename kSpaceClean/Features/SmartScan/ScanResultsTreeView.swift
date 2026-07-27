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

// MARK: - Risk Filter

/// Risk level filter tabs
enum RiskFilter: Int, CaseIterable {
    case all = 0
    case recommended = 1
    case optional = 2
    case caution = 3
    case dangerous = 4

    var title: String {
        switch self {
        case .all: return "全部"
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "注意"
        case .dangerous: return "危险"
        }
    }

    func matches(_ level: RiskLevel) -> Bool {
        switch self {
        case .all: return true
        case .recommended: return level == .recommended
        case .optional: return level == .optional
        case .caution: return level == .caution
        case .dangerous: return level == .dangerous
        }
    }
}

// MARK: - Tree View

/// Lemon-style expandable scan results tree (Category → Action → File)
/// with risk filter tabs, search, and summary bar at bottom.
struct ScanResultsTreeView: View {
    @ObservedObject var viewModel: ScanViewModel
    @State private var riskFilter: RiskFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Risk filter tabs
            RiskFilterBar(riskFilter: $riskFilter, stats: viewModel.riskGroupedStats)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("搜索文件名 / 路径 / 应用名...", text: $searchText)
                    .textFieldStyle(.plain).font(AppFont.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.bgTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 4)

            // Filtered tree
            List {
                ForEach(filteredGroups) { group in
                    Section {
                        CategoryHeader(group: group, viewModel: viewModel)
                        ForEach(group.actionGroups) { actionGroup in
                            if riskFilter.matches(actionGroup.riskLevel) {
                                ActionHeader(actionGroup: actionGroup, viewModel: viewModel)
                                if actionGroup.isExpanded {
                                    ForEach(actionGroup.items) { node in
                                        if riskFilter.matches(node.riskLevel) {
                                            FileResultRow(node: node, viewModel: viewModel)
                                                .padding(.leading, AppSpacing.lg)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)

            // Summary bar
            ScanSummaryBar(
                totalItems: filteredItemCount,
                totalSize: filteredGroupSize,
                selectedItems: viewModel.selectedCount,
                selectedSize: viewModel.selectedSize,
                onCleanup: { viewModel.startCleanup() }
            )
        }
        .modifier(ScanResultsKeyboardShortcuts(riskFilter: $riskFilter, onCleanup: { viewModel.startCleanup() }))
    }

    private var filteredGroups: [ScanResultGroup] {
        var groups = viewModel.resultGroups
        if !searchText.isEmpty {
            groups = groups.compactMap { group in
                let filteredActions = group.actionGroups.compactMap { ag -> ActionGroup? in
                    let filteredItems = ag.items.filter {
                        $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                        $0.path.localizedCaseInsensitiveContains(searchText) ||
                        (ag.appName ?? "").localizedCaseInsensitiveContains(searchText)
                    }
                    guard !filteredItems.isEmpty else { return nil }
                    var copy = ag
                    copy.items = filteredItems
                    return copy
                }
                guard !filteredActions.isEmpty else { return nil }
                var copy = group
                copy.actionGroups = filteredActions
                return copy
            }
        }
        return groups
    }

    private var filteredItemCount: Int {
        filteredGroups.reduce(0) { $0 + $1.totalItems }
    }

    private var filteredGroupSize: Int64 {
        filteredGroups.reduce(0) { $0 + $1.totalSize }
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

            // Risk level badges (4-level)
            if actionGroup.riskLevel == .dangerous {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("危险")
                }
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.danger.opacity(0.2))
                .foregroundColor(.danger)
                .clipShape(Capsule())
            } else if actionGroup.riskLevel == .caution {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("注意")
                }
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .clipShape(Capsule())
            } else if actionGroup.riskLevel == .optional {
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
            if node.riskLevel == .dangerous {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.danger)
            } else if node.isCaution {
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

// MARK: - Risk Filter Bar

struct RiskFilterBar: View {
    @Binding var riskFilter: RiskFilter
    let stats: ScanViewModel.RiskGroupedStats

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterButton(.all, count: stats.totalCount, size: stats.totalSize)
                filterButton(.recommended, count: stats.recommended.count, size: stats.recommended.size)
                filterButton(.optional, count: stats.optional.count, size: stats.optional.size)
                filterButton(.caution, count: stats.caution.count, size: stats.caution.size)
                filterButton(.dangerous, count: stats.dangerous.count, size: stats.dangerous.size)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func filterButton(_ filter: RiskFilter, count: Int, size: Int64) -> some View {
        Button {
            riskFilter = filter
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(filterColor(filter))
                    .frame(width: 6, height: 6)
                Text(filter.title)
                    .font(.system(size: 11, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(filterColor(filter).opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(riskFilter == filter ? filterColor(filter).opacity(0.15) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    riskFilter == filter ? filterColor(filter) : Color.separatorColor.opacity(0.3),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func filterColor(_ filter: RiskFilter) -> Color {
        switch filter {
        case .all: return .brandPrimary
        case .recommended: return .success
        case .optional: return .textSecondary
        case .caution: return .orange
        case .dangerous: return .danger
        }
    }
}

// MARK: - Keyboard Shortcuts

/// macOS 13+ keyboard shortcuts for scan results using NSEvent monitor.
private struct ScanResultsKeyboardShortcuts: ViewModifier {
    @Binding var riskFilter: RiskFilter
    let onCleanup: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCommand = flags == .command

                    guard isCommand else { return event }

                    switch event.charactersIgnoringModifiers {
                    case "0": riskFilter = .all; return nil
                    case "1": riskFilter = .recommended; return nil
                    case "2": riskFilter = .optional; return nil
                    case "3": riskFilter = .caution; return nil
                    case "4": riskFilter = .dangerous; return nil
                    case "\r": onCleanup(); return nil
                    default: return event
                    }
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }
}
