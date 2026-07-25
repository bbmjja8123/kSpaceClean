import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .onboarding
    @Published public var scanState: ScanState = .idle
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var isOnboardingComplete = false

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
