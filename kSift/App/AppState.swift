import SwiftUI
import DesignSystem
import DetectionCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .onboarding
    @Published public var scanState: ScanState = .idle
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var isOnboardingComplete = false
    /// Most recent completed scan's duplicate groups, published so ResultView
    /// can survive RootView's per-navigation view recreation.
    @Published public var latestGroups: [DuplicateGroup] = []
    /// Most recent completed scan's large files (≥ configured threshold).
    /// Feeds the Large Files section of the results screen and the
    /// Show Large Files intent.
    @Published public var latestLargeFiles: [FileItem] = []
    /// Which section of the results screen is showing.
    @Published public var resultsSection: ResultsSection = .duplicates

    public enum ResultsSection: String, CaseIterable {
        case duplicates
        case largeFiles

        public var title: String {
            switch self {
            case .duplicates: return NSLocalizedString("Duplicates", comment: "Results section title")
            case .largeFiles: return NSLocalizedString("Large Files", comment: "Results section title")
            }
        }
    }
    /// Set by AppCoordinator when the Finder Sync extension (or a deep link)
    /// asks us to scan a specific folder. MainView consumes and clears it.
    @Published public var pendingScanPath: String?

    /// The most recent cleanup batch, kept so Edit ▸ Undo can restore every
    /// file to its original location within the vault retention window.
    @Published public var lastCleanupSession: CleanupSession?
    /// Failures from the last undo attempt, surfaced as an alert by RootView.
    @Published public var lastUndoFailures: [VaultMoveFailure] = []

    public enum NavigationItem: String, CaseIterable {
        case onboarding, scan, results, photos, history, vault, settings

        public var iconName: String {
            switch self {
            case .onboarding: return "wand.and.stars"
            case .scan: return "magnifyingglass"
            case .results: return "doc.on.doc"
            case .photos: return "photo.on.rectangle.angled"
            case .history: return "clock"
            case .vault: return "shippingbox"
            case .settings: return "gear"
            }
        }

        public var title: String {
            switch self {
            case .onboarding:
                return NSLocalizedString("Welcome", comment: "Navigation title")
            case .scan:
                return NSLocalizedString("Scan", comment: "Navigation title")
            case .results:
                return NSLocalizedString("Results", comment: "Navigation title")
            case .photos:
                return NSLocalizedString("Photos", comment: "Navigation title")
            case .history:
                return NSLocalizedString("History", comment: "Navigation title")
            case .vault:
                return NSLocalizedString("Vault", comment: "Navigation title")
            case .settings:
                return NSLocalizedString("Settings", comment: "Navigation title")
            }
        }

        /// Digit for the Go-menu shortcut (⌘1 … ⌘6). Nil for onboarding,
        /// which is not reachable from the menu bar.
        public var commandDigit: String? {
            switch self {
            case .onboarding: return nil
            case .scan: return "1"
            case .results: return "2"
            case .photos: return "3"
            case .history: return "4"
            case .vault: return "5"
            case .settings: return "6"
            }
        }
    }

    /// Restores every file of `lastCleanupSession` back to its original
    /// location. Failures land in `lastUndoFailures` for RootView's alert.
    public func undoLastCleanup() {
        guard let session = lastCleanupSession else { return }
        lastCleanupSession = nil
        Task { @MainActor in
            let manager = CleanupStack.makeCleanupManager()
            lastUndoFailures = await manager.restoreSession(session)
        }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }
}
