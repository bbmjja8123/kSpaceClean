import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("卸载历史")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if viewModel.records.isEmpty {
                EmptyStateView(title: "暂无卸载记录", subtitle: "卸载 App 后将在此显示")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.records) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.appName)
                                .fontWeight(.medium)
                            Text("\(record.bundleID) • \(record.uninstalledAt.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: record.appSize + record.totalResidueSize, countStyle: .file))
                            .font(.caption)

                        if !record.isRestored {
                            Button("恢复") {
                                Task { await viewModel.restore(record: record) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isRestoring)
                        } else {
                            Text("已恢复")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadHistory()
        }
    }
}
