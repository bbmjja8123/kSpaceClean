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
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                sizeSection
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
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if app.isProtected {
                        Label("系统", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Text("\(app.bundleID) • v\(app.version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                sourceLabel
            }
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        switch app.source {
        case .mas:
            Label("来自 App Store", systemImage: "bag")
                .font(.caption)
                .foregroundColor(.blue)
        case .userInstalled:
            Label("第三方 App", systemImage: "arrow.down.app")
                .font(.caption)
                .foregroundColor(.secondary)
        case .system:
            Label("系统组件", systemImage: "gearshape.2")
                .font(.caption)
                .foregroundColor(.red)
        case .appleBuiltIn:
            Label("Apple 内置", systemImage: "applelogo")
                .font(.caption)
                .foregroundColor(.secondary)
        case .unknown:
            EmptyView()
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
                Text("卸载")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(app.isProtected ? Color.gray : Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
                Task { await viewModel.restore(record: UninstallRecord(
                    id: UUID(), appName: app.displayName, bundleID: app.bundleID,
                    appPath: app.url.path, appSize: app.sizeBytes,
                    totalResidueSize: 0, residueCount: 0, uninstalledAt: Date(),
                    isRestored: false, backupPath: "", residues: []
                )) }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}
