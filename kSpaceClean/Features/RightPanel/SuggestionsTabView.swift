import SwiftUI
import DesignSystem
import CommonUtils

/// Impact level for "other suggestions" (non-primary selections)
enum ImpactLevel: Int, CaseIterable {
    case high = 0
    case med = 1
    case low = 2

    var title: String {
        switch self {
        case .high: return "HIGH"
        case .med: return "MED"
        case .low: return "LOW"
        }
    }

    var color: Color {
        switch self {
        case .high: return .warning
        case .med: return .brandPrimary
        case .low: return .success
        }
    }

    var displayName: String {
        switch self {
        case .high: return "高影响"
        case .med: return "中影响"
        case .low: return "低影响"
        }
    }
}

struct SuggestionsTabView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @State private var diskUsage = DiskUsage.current()
    @State private var selectedSuggestions: Set<Int> = []
    /// Memoized copy of `scanViewModel.resultGroups` flattened into
    /// `[(ImpactLevel, ActionGroup)]` tuples. Recomputed only on
    /// `.onAppear` and on `scanDidComplete`; previously this was a
    /// computed property that ran on every body call.
    @State private var otherSuggestions: [(ImpactLevel, ActionGroup)] = []
    /// Memoized bucket keyed by `ImpactLevel.rawValue` so the inner
    /// `ForEach` no longer needs to filter `otherSuggestions` per row.
    @State private var suggestionsByLevel: [Int: [(ImpactLevel, ActionGroup)]] = [:]

    /// Rebuilds `otherSuggestions` and `suggestionsByLevel` from the
    /// current `scanViewModel.resultGroups`. Called on appear and on
    /// every `scanDidComplete` emission.
    private func refreshSuggestions() {
        let flat = scanViewModel.resultGroups
            .flatMap { $0.actionGroups }
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(12)
            .map { action -> (ImpactLevel, ActionGroup) in
                let impact: ImpactLevel
                switch action.riskLevel {
                case .dangerous: impact = .high
                case .caution: impact = .med
                default:
                    impact = action.totalSize > 500_000_000 ? .high : action.totalSize > 100_000_000 ? .med : .low
                }
                return (impact, action)
            }
        otherSuggestions = Array(flat)
        // Bucket once. SwiftUI's ForEach reads by key so this lookup
        // is O(1) instead of O(n) per row.
        var bucketed: [Int: [(ImpactLevel, ActionGroup)]] = [:]
        for entry in otherSuggestions {
            bucketed[entry.0.rawValue, default: []].append(entry)
        }
        suggestionsByLevel = bucketed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("其他建议")
                    .font(AppFont.title3).foregroundColor(.textPrimary)

                // Grouped by impact
                ForEach(ImpactLevel.allCases, id: \.rawValue) { level in
                    let items = suggestionsByLevel[level.rawValue] ?? []
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Circle().fill(level.color).frame(width: 8, height: 8)
                                Text("\(level.displayName) · \(items.count) 项")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                            }

                            ForEach(items, id: \.1.id) { impact, action in
                                SuggestionRow(actionGroup: action, impact: impact,
                                              isSelected: selectedSuggestions.contains(action.id))
                            }
                        }
                    }
                }

                if otherSuggestions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.title2).foregroundColor(.textSecondary)
                        Text("完成扫描后这里将显示清理建议")
                            .font(AppFont.body).foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .padding(AppSpacing.md)
        }
        .onAppear { refreshSuggestions(); diskUsage = DiskUsage.current() }
        .onReceive(scanViewModel.$scanDidComplete) { _ in
            refreshSuggestions()
            diskUsage = DiskUsage.current()
        }
    }
}

@MainActor
private struct SuggestionRow: View {
    let actionGroup: ActionGroup
    let impact: ImpactLevel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .brandPrimary : .textSecondary)
                .font(.system(size: 14))

            Text(impact.title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(impact.color.opacity(0.15))
                .foregroundColor(impact.color)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(actionGroup.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                if let app = actionGroup.appName {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: actionGroup.totalSize))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(8)
        .background(Color.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
