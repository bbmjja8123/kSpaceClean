import SwiftUI

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var searchQuery = ""
    @Published var filter: AppFilter = .all
    @Published var isLoading = true

    enum AppFilter: String, CaseIterable {
        case all = "全部"
        case user = "用户"
        case system = "系统"
        case recent = "最近安装"
    }

    private let scanner = ResidueScanner()

    var filteredApps: [InstalledApp] {
        var result = apps
        if !searchQuery.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(searchQuery) || $0.bundleID.localizedCaseInsensitiveContains(searchQuery) }
        }
        switch filter {
        case .all: break
        case .user: result = result.filter { $0.source == .userInstalled || $0.source == .mas }
        case .system: result = result.filter { $0.source == .system || $0.source == .appleBuiltIn }
        case .recent: result = result.filter { $0.lastUsedDate ?? .distantPast > Date().addingTimeInterval(-86400 * 30) }
        }
        return result
    }

    func loadApps() async {
        isLoading = true
        let scanned = await scanner.scanAll()
        await MainActor.run {
            self.apps = scanned
            self.isLoading = false
        }
    }
}
