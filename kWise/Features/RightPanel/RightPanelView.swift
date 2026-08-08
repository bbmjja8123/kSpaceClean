import SwiftUI
import DesignSystem

/// Trailing inspector panel (⌘F) with the overview / results / suggestions
/// tabs.
///
/// C3: the panel now owns its own legacy ``ScanViewModel`` instead of
/// borrowing the root's. The root's scan triggers were migrated to the v3
/// ``ScanResultsViewModel`` pipeline, which the legacy right-panel tabs
/// cannot read (they consume Core Data `FileEntry` rows produced by
/// `LegacyScanEngine`). Owning the model locally keeps the panel
/// self-contained until the tabs are migrated (Task B5+); until then the
/// tabs render their own "点击开始扫描" empty state.
struct RightPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppState.RightPanelTab = .overview
    /// Legacy v2 scan model backing the three tabs. Local to the panel.
    @StateObject private var scanViewModel = ScanViewModel()

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(AppState.RightPanelTab.allCases, id: \.self) { tab in
                        Button(tab.rawValue) {
                            selectedTab = tab
                            appState.rightPanelTab = tab
                        }
                        .buttonStyle(.plain)
                        .font(AppFont.callout)
                        .foregroundColor(selectedTab == tab ? .textPrimary : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.brandPrimary.opacity(0.15) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                Divider().padding(.vertical, 4)

                // Tab content — using switch for macOS compatibility
                // (TabView on macOS renders its own native tab bar, conflicting with custom tabs above)
                Group {
                    switch selectedTab {
                    case .overview: OverviewTabView(scanViewModel: scanViewModel)
                    case .results: ScanResultsTreeView(viewModel: scanViewModel)
                    case .suggestions: SuggestionsTabView(scanViewModel: scanViewModel)
                    }
                }
            }
        }
    }
}
