import SwiftUI
import DesignSystem

struct RightPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppState.RightPanelTab = .overview
    let galaxyViewModel: GalaxyViewModel
    let scanViewModel: ScanViewModel

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
                    case .allFiles: AllFilesTabView(scanViewModel: scanViewModel)
                    case .suggestions: SuggestionsTabView(scanViewModel: scanViewModel)
                    }
                }
            }
        }
    }
}
