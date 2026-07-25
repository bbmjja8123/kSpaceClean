import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            sidebar
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { coordinator.showHistory = true }) {
                            Label("历史", systemImage: "clock.arrow.circlepath")
                        }

                        Button(action: { coordinator.showSettings = true }) {
                            Label("设置", systemImage: "gearshape")
                        }
                    }
                }
        } detail: {
            detailContent
        }
        .sheet(isPresented: $coordinator.showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $coordinator.showOnboarding) {
            FDAGuideView(
                onSkip: { coordinator.showOnboarding = false },
                onContinue: { coordinator.showOnboarding = false }
            )
        }
    }

    @ViewBuilder private var sidebar: some View {
        VStack(spacing: 0) {
            AppListView()
        }
        .frame(minWidth: 280)
    }

    @ViewBuilder private var detailContent: some View {
        if let selectedApp = coordinator.selectedApp {
            AppDetailView(app: selectedApp)
        } else {
            EmptyStateView(
                title: "选择 App",
                subtitle: "从左侧列表选择一个应用查看详情"
            )
        }
    }
}
