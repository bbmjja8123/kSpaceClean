import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .onboarding
    @Published public var scanState: ScanState = .idle
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var isOnboardingComplete = false
    /// Most recent completed scan's duplicate groups, published so ResultView
    /// can survive RootView's per-navigation view recreation.
    @Published public var latestGroups: [DuplicateGroup] = []
    /// Set by AppCoordinator when the Finder Sync extension (or a deep link)
    /// asks us to scan a specific folder. MainView consumes and clears it.
    @Published public var pendingScanPath: String?

    public enum NavigationItem: String, CaseIterable {
        case onboarding, scan, results, history, settings

        public var iconName: String {
            switch self {
            case .onboarding: return "wand.and.stars"
            case .scan: return "magnifyingglass"
            case .results: return "doc.on.doc"
            case .history: return "clock"
            case .settings: return "gear"
            }
        }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }
}
