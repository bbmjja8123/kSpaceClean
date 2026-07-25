import SwiftUI

struct AppListView: View {
    @StateObject private var viewModel = AppListViewModel()
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var isPro = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 App...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.filteredApps.isEmpty {
                    Button(isSelecting ? "完成" : "选择") {
                        withAnimation {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
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

            // Batch action bar
            if isSelecting && !selectedIDs.isEmpty {
                HStack {
                    Text("已选择 \(selectedIDs.count) 个 App")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await performBatchUninstall() }
                    } label: {
                        Label("批量卸载", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isPro ? Color.red.opacity(0.8) : Color.gray)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPro)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor).opacity(0.5))
            }

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
                    HStack {
                        if isSelecting {
                            Image(systemName: selectedIDs.contains(app.bundleID) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedIDs.contains(app.bundleID) ? .accentColor : .secondary)
                                .onTapGesture {
                                    if selectedIDs.contains(app.bundleID) {
                                        selectedIDs.remove(app.bundleID)
                                    } else {
                                        guard !app.isProtected else { return }
                                        selectedIDs.insert(app.bundleID)
                                    }
                                }
                        }
                        AppRowView(app: app)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelecting {
                                    guard !app.isProtected else { return }
                                    if selectedIDs.contains(app.bundleID) {
                                        selectedIDs.remove(app.bundleID)
                                    } else {
                                        selectedIDs.insert(app.bundleID)
                                    }
                                } else {
                                    coordinator.selectApp(app)
                                }
                            }
                    }
                    .listRowInsets(EdgeInsets())
                    .opacity(app.isProtected && isSelecting ? 0.5 : 1)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadApps()
            isPro = await StoreManager.shared.isPro
        }
    }

    private func performBatchUninstall() async {
        let apps = viewModel.filteredApps.filter { selectedIDs.contains($0.bundleID) }
        guard !apps.isEmpty else { return }
        for app in apps {
            guard TrashMover.canMoveToTrash(app: app) else { continue }
            let mover = TrashMover()
            let result = await mover.moveToTrash(app: app, residues: [])
            if case .success = result {
                await viewModel.loadApps()
            }
        }
        await MainActor.run {
            selectedIDs.removeAll()
            isSelecting = false
        }
    }
}
