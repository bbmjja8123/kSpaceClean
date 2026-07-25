import SwiftUI

struct UninstallConfirmSheet: View {
    @ObservedObject var viewModel: DetailViewModel
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 20) {
            Text("确认卸载")
                .font(.title2)
                .fontWeight(.bold)
            Text("将卸载 \(viewModel.app.displayName) 及其残留文件")
                .foregroundColor(.secondary)
            HStack {
                Button("取消") {
                    viewModel.showConfirmSheet = false
                }
                Button("确认卸载") {
                    Task { await viewModel.uninstall() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
