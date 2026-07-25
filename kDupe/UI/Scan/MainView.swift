import SwiftUI
import DesignSystem

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        VStack {
            switch viewModel.scanState {
            case .idle:
                idleState
            case .scanning:
                if let progress = viewModel.progress {
                    ScanProgressView(progress: progress)
                }
            case .completed:
                ScanResultView(
                    groups: viewModel.scanResult,
                    onReview: { appState.navigation = .results },
                    onRescan: { viewModel.startScan(config: ProfileConfig.default) }
                )
            case .failed(let msg):
                ErrorStateView(message: msg, retryAction: { viewModel.startScan(config: ProfileConfig.default) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleState: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("Ready to Scan")
                .font(.title).bold()
            Text("Choose a profile in Settings or start with Developer mode")
                .foregroundColor(.secondary)

            Button(action: { viewModel.startScan(config: ProfileConfig.default) }) {
                Label("Start Scan", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
    }
}
