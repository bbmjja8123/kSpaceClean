import SwiftUI

struct AppListView: View {
    @StateObject private var viewModel = AppListViewModel()
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 App...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))

            // Filter bar
            Picker("", selection: $viewModel.filter) {
                ForEach(AppListViewModel.AppFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // List
            if viewModel.isLoading {
                Spacer()
                LoadingStateView(message: "正在扫描已安装应用...")
                Spacer()
            } else if viewModel.filteredApps.isEmpty {
                Spacer()
                EmptyStateView(title: "没有找到 App", subtitle: "尝试调整筛选条件")
                Spacer()
            } else {
                List(viewModel.filteredApps) { app in
                    AppRowView(app: app)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.selectApp(app)
                        }
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadApps()
        }
    }
}
