import SwiftUI
import DesignSystem
import DetectionCore

/// Photos-library dedup screen: explicit permission flow (mirroring the
/// FDA onboarding pattern, including the macOS "limited" state), a local
/// scan (cloud-only assets are skipped and reported), and cleanup that
/// lands in the Photos "Recently Deleted" album — the system's own
/// 30-day undo, not the kSift vault.
struct PhotosScanView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager
    @StateObject private var model = PhotosScanModel()
    @State private var selectedIds: Set<UUID> = []
    @State private var showPaywall = false
    @State private var deleteFailures: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .notAuthorized:
                permissionFlow
            case .scanning:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Scanning your photo library locally…")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
            case .scanned(let outcome):
                resultsView(outcome)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshAuthorization() }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .alert(
            NSLocalizedString("Some photos could not be deleted", comment: "Photos delete failure title"),
            isPresented: Binding(
                get: { !deleteFailures.isEmpty },
                set: { if !$0 { deleteFailures = [] } }
            )
        ) {
            Button("OK", role: .cancel) { deleteFailures = [] }
        } message: {
            Text(String(
                format: NSLocalizedString("%lld photo(s) could not be deleted. They may already be removed.", comment: "Photos delete failure message"),
                deleteFailures.count
            ))
        }
    }

    // MARK: - Permission flow

    private var permissionFlow: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.brandPrimary)
            Text("Find duplicates in your photo library")
                .font(.title2).bold()
            Text("kSift scans your photo library entirely on this Mac. Cloud-only photos are skipped — nothing is downloaded or uploaded.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if model.lastAuthorizationDenied {
                Label(
                    NSLocalizedString("Access was denied. Grant it in System Settings → Privacy & Security → Photos.", comment: "Photos denied hint"),
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundColor(.warning)
            }

            Button {
                Task { await model.requestAccessAndScan() }
            } label: {
                Label("Grant Access & Scan", systemImage: "lock.open")
                    .frame(width: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)

            Button(NSLocalizedString("Open System Settings", comment: "Open System Settings action")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Results

    private func resultsView(_ outcome: PhotosScanOutcome) -> some View {
        VStack(spacing: 0) {
            GlassPanel {
                HStack {
                    StatItem(title: "Groups", value: "\(outcome.groups.count)")
                    StatItem(title: "Assets scanned", value: "\(outcome.totalAssets)")
                    if outcome.cloudSkipped > 0 {
                        StatItem(
                            title: "iCloud-only skipped",
                            value: "\(outcome.cloudSkipped)"
                        )
                    }
                    Spacer()
                    Button(NSLocalizedString("Re-scan", comment: "Photos re-scan button")) {
                        Task { await model.scan() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if outcome.cloudSkipped > 0 {
                Text(String(
                    format: NSLocalizedString("%lld iCloud-only photo(s) were skipped — enable Download originals on this Mac to include them.", comment: "Cloud-skipped note"),
                    outcome.cloudSkipped
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            if outcome.groups.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: NSLocalizedString("No duplicate photos found", comment: "Photos empty result title"),
                    subtitle: NSLocalizedString("Your photo library has no duplicate or near-duplicate images.", comment: "Photos empty result subtitle")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(outcome.groups) { group in
                            GroupRowView(
                                group: group,
                                isSelected: selectedIds.contains(group.id),
                                onToggle: {
                                    if selectedIds.contains(group.id) {
                                        selectedIds.remove(group.id)
                                    } else {
                                        selectedIds.insert(group.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(16)
                }

                HStack {
                    Text("\(selectedIds.count) groups selected")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(deleteButtonLabel(for: outcome)) {
                        Task { await deleteSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selectedIds.isEmpty)
                }
                .padding(16)
            }
        }
    }

    private func deleteButtonLabel(for outcome: PhotosScanOutcome) -> String {
        let base = NSLocalizedString("Remove from Library", comment: "Photos delete button")
        let selectedGroups = outcome.groups.filter { selectedIds.contains($0.id) }
        let bytes = selectedGroups.reduce(Int64(0)) { $0 + $1.totalSize }
        if !store.isPaidUser,
           store.freeTierBytesCleaned + bytes > StoreManager.freeCleanupQuotaBytes {
            return base + NSLocalizedString(" · Upgrade", comment: "Upgrade hint appended to delete label")
        }
        return base
    }

    private func deleteSelected() async {
        let outcome = model.outcome
        let selectedGroups = (outcome?.groups ?? []).filter { selectedIds.contains($0.id) }
        let files = selectedGroups.flatMap(\.files)
        let manager = PhotosCleanupManager()
        let failures = await manager.delete(files)
        // Photos "Recently Deleted" keeps undo native; drop cleaned groups
        // from the visible list.
        let failedIds = Set(failures)
        let succeededGroups = Set(
            selectedGroups
                .filter { group in
                    group.files.allSatisfy { file in
                        guard let id = file.photosLocalIdentifier else { return true }
                        return !failedIds.contains(id)
                    }
                }
                .map(\.id)
        )
        if var current = model.outcome {
            current.groups.removeAll { succeededGroups.contains($0.id) }
            model.outcome = current
        }
        if !failures.isEmpty { deleteFailures = failures }
        selectedIds.removeAll()
    }
}

// MARK: - Model

@MainActor
final class PhotosScanModel: ObservableObject {
    enum State {
        case notAuthorized
        case scanning
        case scanned(PhotosScanOutcome)
    }

    @Published var state: State = .notAuthorized
    @Published private(set) var lastAuthorizationDenied = false
    /// Read/written by the view when groups are cleaned from the list.
    var outcome: PhotosScanOutcome? {
        get {
            if case .scanned(let outcome) = state { return outcome }
            return nil
        }
        set {
            if let newValue { state = .scanned(newValue) }
        }
    }

    private let scanner: PhotosLibraryScanner
    private let provider: any PhotoLibraryProviding

    init(provider: any PhotoLibraryProviding = PHAssetLibraryProvider()) {
        self.provider = provider
        self.scanner = PhotosLibraryScanner(provider: provider)
    }

    func refreshAuthorization() {
        if case .scanned = state { return }
        let status = provider.authorizationStatus()
        lastAuthorizationDenied = (status == .denied || status == .restricted)
    }

    func requestAccessAndScan() async {
        let granted = await provider.requestAccess()
        lastAuthorizationDenied = !granted
        guard granted else {
            state = .notAuthorized
            return
        }
        await scan()
    }

    func scan() async {
        state = .scanning
        if let outcome = await scanner.scan(controller: ScanController()) {
            state = .scanned(outcome)
        } else {
            state = .notAuthorized
        }
    }
}
