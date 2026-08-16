import SwiftUI

/// Main page of kFresh: a `NavigationSplitView` with a category sidebar, a
/// searchable / sortable app list, and the detail pane.
struct AppListView: View {
    @StateObject private var viewModel: AppListViewModel
    @State private var selectedApp: InstalledApp?
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var services: AppServices

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
        // Wave 2 P1 (G-KF-03): drag-and-drop an `.app` bundle from Finder
        // to surface it as a virtual entry in the list. The drop is the
        // primary "low-friction" interaction promised by AppCleaner /
        // Pearcleaner / CleanMyMac X — pick the file, drop it on the
        // window, see the app surface, click uninstall.
        //
        // Strategy: ingest the dropped URL synchronously into the view
        // model via a `viewModel.ingestDroppedApp(url:)` seam. The view
        // model handles all classification + duplicate detection so the
        // drop handler stays a one-liner and is trivially testable.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(alignment: .top) {
            if isDropTargeted {
                DropTargetOverlay()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: KFAnimation.durationFast), value: isDropTargeted)
    }

    /// True while a Finder drag is hovering over the window — drives the
    /// highlight overlay.
    @State private var isDropTargeted: Bool = false

    /// Resolves the first file URL in `providers` (most drops are
    /// single-app; multi-app drops ignore the trailing items) and asks
    /// the view model to ingest it. Returns `true` when a URL was found
    /// and forwarded, `false` when no provider yielded a file URL.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let typeIdentifier = "public.file-url"
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            return false
        }
        let semaphore = DispatchSemaphore(value: 0)
        var loadedURL: URL?
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            defer { semaphore.signal() }
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                loadedURL = url
            } else if let url = item as? URL {
                loadedURL = url
            }
        }
        // Synchronous loadItem is fine here — provider.loadItem is
        // documented to complete synchronously for file URLs when the
        // item is already local (Finder drags over a running app).
        semaphore.wait()
        guard let url = loadedURL else { return false }
        viewModel.ingestDroppedApp(url: url)
        return true
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            ScanProgressBanner(state: viewModel.scanState) {
                Task { await viewModel.refresh() }
            }
            List(selection: $selectedApp) {
                ForEach(viewModel.filteredApps, id: \.bundleID) { app in
                    AppRowView(app: app, sizeBytes: viewModel.sizeBytes(for: app))
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

                    // Pro entry — non-Pro users see the button but tapping
                    // raises the paywall sheet so they get an upgrade prompt
                    // instead of a silently-no-op tap (mirrors the
                    // `AppDetailView.proEntries` row pattern).
                    Button {
                        if services.store.state == .pro {
                            coordinator.showDeepClean = true
                        } else {
                            coordinator.showPaywall = true
                        }
                    } label: {
                        Label("深度清理", systemImage: "trash.square")
                    }

                    Button {
                        if services.store.state == .pro {
                            coordinator.showStartupItems = true
                        } else {
                            coordinator.showPaywall = true
                        }
                    } label: {
                        Label("启动项", systemImage: "power")
                    }
                }
            }
        }
    }

    @ViewBuilder private var detailPane: some View {
        if let app = selectedApp {
            AppDetailView(app: app, mover: services.mover, sizeBytes: viewModel.sizeBytes(for: app))
        } else {
            EmptyStateView(
                title: "选择一个 App",
                subtitle: "从左侧列表选择以查看详情和卸载",
                icon: "app.badge.checkmark"
            )
        }
    }
}

/// Highlight banner shown while a Finder drag is hovering over the
/// window — signals "this drop will work" without forcing the user to
/// read documentation. Wave 2 P1 (G-KF-03).
private struct DropTargetOverlay: View {
    var body: some View {
        Label("拖入 .app 即可扫描", systemImage: "square.and.arrow.down.on.square")
            .font(AppFont.callout)
            .foregroundStyle(Color.textPrimary)
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.brandPrimary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            )
            .padding(AppSpacing.md)
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
