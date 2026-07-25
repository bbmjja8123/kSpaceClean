import SwiftUI

struct DeepCleanView: View {
    @StateObject private var viewModel = DeepCleanViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("深度清理")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                if !viewModel.groups.isEmpty {
                    Button("清理选中项") {
                        Task { await viewModel.clean() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            if !viewModel.hasFDA {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32))
                    Text("需要全盘访问权限")
                    Text("深度清理需要 FDA 授权才能扫描系统级残留")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("授权 FDA") {
                        FDAuthorizer().requestFDA()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isScanning {
                LoadingStateView(message: "正在扫描系统残留...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                EmptyStateView(title: "未发现系统残留", subtitle: "系统状态良好")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.groups) { group in
                        SystemCleanGroupView(group: group)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.checkFDA()
            if viewModel.hasFDA {
                await viewModel.scan()
            }
        }
        .proGate(featureName: "深度清理", featureIcon: "gearshape.2")
    }
}
