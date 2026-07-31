import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @StateObject private var viewModel: DetailViewModel
    @EnvironmentObject private var coordinator: AppCoordinator

    init(app: InstalledApp) {
        self.app = app
        _viewModel = StateObject(wrappedValue: DetailViewModel(app: app, coordinator: AppCoordinator()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                sizeSection
                    .cardStyle()
                if !app.residues.isEmpty {
                    ResidueSectionView(residues: app.residues, selectedResidues: $viewModel.selectedResidues)
                }
                Spacer()
                uninstallButton
            }
            .padding(24)
        }
        .sheet(isPresented: $viewModel.showConfirmSheet) {
            UninstallConfirmSheet(viewModel: viewModel)
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUninstallToast {
                uninstallToast
            }
        }
    }

    private var heroSection: some View {
        HStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if app.isProtected {
                        Label("系统", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.warning)
                    }
                }
                Text("\(app.bundleID) • v\(app.version)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                sourceLabel
                analysisBadge
            }
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        switch app.source {
        case .mas:
            Label("来自 App Store", systemImage: "bag")
                .font(.caption)
                .foregroundColor(.brandSecondary)
        case .userInstalled:
            Label("第三方 App", systemImage: "arrow.down.app")
                .font(.caption)
                .foregroundColor(.textSecondary)
        case .system:
            Label("系统组件", systemImage: "gearshape.2")
                .font(.caption)
                .foregroundColor(.danger)
        case .appleBuiltIn:
            Label("Apple 内置", systemImage: "applelogo")
                .font(.caption)
                .foregroundColor(.textSecondary)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder private var analysisBadge: some View {
        if let action = viewModel.analysis?.suggestedAction {
            HStack(spacing: 4) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.caption)
                switch action {
                case "never_used":
                    Text("很少使用")
                        .font(.caption)
                case "uninstall":
                    Text("超过 90 天未使用")
                        .font(.caption)
                default:
                    EmptyView()
                }
            }
            .foregroundColor(action == "never_used" ? Color.warning : .danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((action == "never_used" ? Color.warning : Color.danger).opacity(0.12))
            .cornerRadius(6)
        }
    }

    private var sizeSection: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Text(app.sizeFormatted)
                    .font(.system(size: 24, weight: .bold))
                Text("App 本体")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: app.residues.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))
                    .font(.system(size: 24, weight: .bold))
                Text("残留文件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if app.isRunning {
                Label("运行中", systemImage: "play.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var uninstallButton: some View {
        Button(action: {
            viewModel.showConfirmSheet = true
        }) {
            HStack {
                Image(systemName: "trash")
                Text("卸载 \(app.displayName)")
            }
        }
        .buttonStyle(.destructive)
        .controlSize(.large)
        .disabled(app.isProtected)
    }

    private var uninstallToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("已卸载 \(app.displayName)")
                .fontWeight(.medium)
            Spacer()
            Button("撤销 (\(viewModel.undoRemainingSeconds)s)") {
                Task { await viewModel.restore() }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}
