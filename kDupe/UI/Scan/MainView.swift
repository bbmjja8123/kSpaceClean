import SwiftUI
import DesignSystem

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ScanViewModel

    init(paidFlag: PaidUserFlag? = nil) {
        // Build the ScanViewModel eagerly here so its orchestrator picks up
        // the `IncrementalIndex` for paid users. SwiftUI evaluates `init`
        // before `body`, so the `paidFlag` is passed in by `RootView` from
        // its own `@Environment(\.paidUserFlag)` read.
        _viewModel = StateObject(wrappedValue: ScanViewModel(paidFlag: paidFlag))
    }

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
                    onRescan: { viewModel.startScan(config: ProfileConfigStore.load()) }
                )
            case .failed(let msg):
                ErrorStateView(
                    title: NSLocalizedString("Scan Failed", comment: "Error state title"),
                    message: msg,
                    retryAction: { viewModel.startScan(config: ProfileConfigStore.load()) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.onScanCompleted = { groups in
                appState.latestGroups = groups
            }
            // Drain a pending Finder Sync scan request: when the user picks
            // "Scan with kSift" in Finder while the app is running, the
            // AppCoordinator lands us here with a folder path waiting.
            if let path = appState.pendingScanPath {
                appState.pendingScanPath = nil
                startScan(at: path)
            }
        }
        .onChange(of: appState.pendingScanPath) { newValue in
            // Catches requests that arrive after onAppear has already run
            // (e.g., the user is on Settings when they click the Finder menu).
            guard let path = newValue else { return }
            appState.pendingScanPath = nil
            startScan(at: path)
        }
    }

    private func startScan(at path: String) {
        let base = ProfileConfigStore.load()
        let config = ProfileConfig(
            type: base.type,
            customDirectories: [path],
            exclusions: base.exclusions,
            minFileSize: base.minFileSize,
            enablePerceptualScan: base.enablePerceptualScan,
            enableBuildArtifacts: base.enableBuildArtifacts
        )
        viewModel.startScan(config: config)
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

            Button(action: { viewModel.startScan(config: ProfileConfigStore.load()) }) {
                Label("Start Scan", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
    }
}