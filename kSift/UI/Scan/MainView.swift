import SwiftUI
import UniformTypeIdentifiers
import DesignSystem

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ScanViewModel
    /// Live Full Disk Access state; refreshed on appear and on every scan
    /// attempt so the guard banner never goes stale.
    @State private var fdaStatus: FDAStatus = .unknown
    /// Set by "Scan anyway" so the user can keep working without the banner
    /// nagging on every scan while Full Disk Access stays off.
    @State private var isFdaBannerDismissed = false
    /// Roots the next scan will walk, mirrored from the persisted profile so
    /// the range preview refreshes when the user edits directories in Settings
    /// and comes back.
    @State private var previewDirectories: [String] = []
    /// True while a Finder drag is hovering over the idle surface. Drives the
    /// dashed drop-zone overlay so users get instant feedback that the drop
    /// will be accepted. Only meaningful while `scanState == .idle` because we
    /// detach the drop destination during active scans.
    @State private var isDropTargeted = false

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
                    ScanProgressView(
                        progress: progress,
                        groupsFound: viewModel.groupsFound,
                        elapsed: viewModel.elapsed,
                        isPaused: viewModel.controllerIsPaused,
                        onCancel: { viewModel.cancelScan() },
                        onPause: { viewModel.pauseScan() },
                        onResume: { viewModel.resumeScan() }
                    )
                }
            case .completed:
                ScanResultsView(
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
        // Drag-and-drop scan entry point. Only fires while idle; while a scan
        // is in flight or showing results we ignore the drop so the user
        // can't accidentally clobber an in-progress job. The destination
        // accepts `URL` payloads (Finder passes file URLs), so we can pull
        // the directory path straight off the URL.
        .dropDestination(for: URL.self) { urls, _ in
            // Pattern-match instead of an `isIdle` helper because `ScanState`
            // is a plain enum without that accessor. Keeping the check inline
            // avoids touching the shared state type for a single-callsite use.
            guard case .idle = viewModel.scanState else { return false }
            let directoryPaths = urls
                .filter { $0.hasDirectoryPath }
                .map { $0.path }
            guard !directoryPaths.isEmpty else { return false }
            startScan(at: directoryPaths)
            return true
        } isTargeted: { isHovering in
            // Only show the hover overlay during idle — a targeted drop
            // while scanning would be misleading because we reject it.
            let isIdle: Bool
            if case .idle = viewModel.scanState { isIdle = true } else { isIdle = false }
            isDropTargeted = isHovering && isIdle
        }
        .onAppear {
            refreshFdaStatus()
            refreshPreviewDirectories()
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
        startScan(at: [path])
    }

    /// Multi-path entry point used by the drag-and-drop destination and any
    /// future surface that wants to scan several directories at once. We
    /// re-probe FDA first (mirroring the single-path overload) so the guard
    /// banner reflects live permission state, then build a config that
    /// keeps the user's profile choices (exclusions / size threshold /
    /// perceptual / build-artifact flags) but replaces the target roots
    /// with the dragged paths. A single dropped directory is identical in
    /// behavior to the Finder-Sync / Settings path; multiple directories
    /// exercise the orchestrator's multi-root walk in a single pass.
    private func startScan(at paths: [String]) {
        guard !paths.isEmpty else { return }
        // Re-probe before every scan attempt so the guard banner reflects
        // the live permission state.
        refreshFdaStatus()
        let base = ProfileConfigStore.load()
        let config = ProfileConfig(
            type: base.type,
            customDirectories: paths,
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

            if showsFdaBanner {
                fdaBanner
            }

            ScanRangePreview(directories: previewDirectories)

            Button(action: { startIdleScan() }) {
                Label("Start Scan", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
        // The outer `onAppear` does not re-fire when the state machine returns
        // to idle, so re-read the profile here as well to catch directory
        // edits made while the user was away on Settings.
        .onAppear { refreshPreviewDirectories() }
        // Drag-hover visual: dashed brand-colored border + centered label.
        // Layered via overlay so the existing idle layout stays intact; only
        // the framing and an instructional label appear when targeted.
        .overlay(dropOverlay)
    }

    /// Visible only while a Finder drag is hovering over the idle surface.
    /// Uses `.brandPrimary` to match the CTA tint and DesignSystem radii.
    private var dropOverlay: some View {
        ZStack {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 36))
                        .foregroundColor(.brandPrimary)
                    Text("Drop to start scanning")
                        .font(.title3).bold()
                        .foregroundColor(.brandPrimary)
                }
                .padding(AppSpacing.lg)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .allowsHitTesting(false)
    }

    /// The non-blocking FDA guard. Visible only when access is denied and
    /// the user has not explicitly chosen to proceed anyway.
    private var showsFdaBanner: Bool {
        fdaStatus == .denied && !isFdaBannerDismissed
    }

    /// Re-probes Full Disk Access and re-arms the dismissable banner. Called
    /// on appear and at the start of every scan so stale state never lingers.
    private func refreshFdaStatus() {
        fdaStatus = FDAChecker.status()
        isFdaBannerDismissed = false
    }

    /// Mirrors the persisted profile's roots into `previewDirectories`. Must
    /// match `ScanOrchestrator.run`'s target so the preview describes the scan
    /// that will actually run.
    private func refreshPreviewDirectories() {
        let config = ProfileConfigStore.load()
        previewDirectories = config.type.scanningDirectories + config.customDirectories
    }

    /// Scan from the idle state. Guards FDA first, but never blocks: the scan
    /// still runs even when access is denied.
    private func startIdleScan() {
        refreshFdaStatus()
        viewModel.startScan(config: ProfileConfigStore.load())
    }

    private var fdaBanner: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(AppFont.title2)
                .foregroundColor(.warning)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Full Disk Access required")
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Text("kSift needs Full Disk Access to scan protected folders like Desktop, Documents, and Downloads.")
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.md)

            Button("Open System Settings") { FDAChecker.openSystemSettings() }
            Button("Re-check") { refreshFdaStatus() }
            Button("Scan anyway") { isFdaBannerDismissed = true }
        }
        .padding(AppSpacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .stroke(Color.warning.opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: 600)
    }
}