import SwiftUI

/// Main page of kFresh: a `NavigationSplitView` with a category sidebar, a
/// searchable / sortable app list, and the detail pane.
struct AppListView: View {
    @StateObject private var viewModel: AppListViewModel
    @State private var selectedApp: InstalledApp?
    @EnvironmentObject private var coordinator: AppCoordinator

    init(viewModel: AppListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            AppListSidebar(
                category: $viewModel.category,
                scanState: viewModel.scanState,
                totalCount: viewModel.apps.count
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            contentColumn
        } detail: {
            detailPane
        }
        .task {
            await viewModel.startScan()
        }
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            ScanProgressBanner(state: viewModel.scanState) {
                Task { await viewModel.refresh() }
            }
            List(selection: $selectedApp) {
                ForEach(viewModel.filteredApps, id: \.bundleID) { app in
                    AppRowView(app: app)
                        .tag(app)
                }
                if !viewModel.uninstalledApps.isEmpty {
                    Section("最近卸载（30 天内可恢复）") {
                        ForEach(viewModel.uninstalledApps, id: \.id) { record in
                            HistoryRow(record: record)
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "搜索 App 或 Bundle ID")
            .navigationTitle("kFresh")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("排序", selection: $viewModel.sortKey) {
                            ForEach(AppListViewModel.SortKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        Toggle("升序", isOn: $viewModel.sortAscending)
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        coordinator.showHistory = true
                    } label: {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        coordinator.showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let app = selectedApp {
            AppDetailView(app: app)
        } else {
            EmptyStateView(
                title: "选择一个 App",
                subtitle: "从左侧列表选择以查看详情和卸载",
                icon: "app.badge.checkmark"
            )
        }
    }
}

extension AppListViewModel.SortKey {
    /// User-facing sort label shown in the toolbar picker.
    var displayName: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .installDate: return "安装时间"
        case .lastUsedDate: return "最近使用"
        }
    }
}
