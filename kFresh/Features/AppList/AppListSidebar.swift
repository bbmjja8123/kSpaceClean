import SwiftUI

/// Left sidebar of the AppList main page: the category filter plus a scan
/// status readout.
struct AppListSidebar: View {
    @Binding var category: AppListViewModel.Category
    let scanState: AppListViewModel.ScanState
    let totalCount: Int

    var body: some View {
        List(selection: $category) {
            Section("分类") {
                ForEach(AppListViewModel.Category.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.systemImage)
                        .tag(cat)
                }
            }
            Section("状态") {
                scanStatusRow
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var scanStatusRow: some View {
        switch scanState {
        case .idle:
            Label("未扫描", systemImage: "clock")
        case .scanning:
            Label("扫描中", systemImage: "magnifyingglass")
        case .completed:
            Label("共 \(totalCount) 个", systemImage: "checkmark.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.danger)
        }
    }
}

extension AppListViewModel.Category {
    /// User-facing category label shown in the sidebar.
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .user: return "用户"
        case .system: return "系统"
        case .recentlyInstalled: return "最近安装"
        }
    }

    /// Sidebar row icon for this category.
    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .user: return "person"
        case .system: return "gearshape.2"
        case .recentlyInstalled: return "clock.arrow.circlepath"
        }
    }
}
