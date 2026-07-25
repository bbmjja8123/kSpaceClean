import SwiftUI

struct StartupItemsView: View {
    @StateObject private var viewModel = StartupItemsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("启动项管理")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if viewModel.isLoading {
                LoadingStateView(message: "正在加载启动项...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                EmptyStateView(title: "无启动项", subtitle: "未发现登录项或启动代理")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(StartupItemType.allCases, id: \.self) { type in
                        let filtered = viewModel.items.filter { $0.type == type }
                        if !filtered.isEmpty {
                            Section(type.rawValue) {
                                ForEach(filtered) { item in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .fontWeight(.medium)
                                            Text(item.url.path)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("移除") {
                                            Task { await viewModel.remove(item: item) }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(item.isProtected)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.load() }
    }
}
