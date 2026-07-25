import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
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
