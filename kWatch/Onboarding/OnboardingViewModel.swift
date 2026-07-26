import Foundation
import Combine
import MetricsKit

/// Drives the four-step first-launch onboarding flow.
///
/// State changes are published so SwiftUI views can re-render the active
/// page, and the current `selectedMode` / `enabledKinds` choices are
/// persisted through the `PreferencesRepositoryProtocol` on `complete()`.
///
/// The view model is `@MainActor` because it owns `@Published` state that
/// SwiftUI binds to from view bodies; all public methods must therefore be
/// invoked on the main actor.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    /// The four onboarding pages, traversed in order.
    public enum Page: Int, CaseIterable {
        case welcome, customize, proIntro, complete
    }

    @Published public private(set) var page: Page = .welcome
    @Published public var selectedMode: MenuBarMode = .trend
    @Published public var enabledKinds: Set<MetricKind> = [.cpu, .memory, .disk, .network]

    private let preferences: any PreferencesRepositoryProtocol

    public init(preferences: any PreferencesRepositoryProtocol) {
        self.preferences = preferences
        self.selectedMode = preferences.menuBarMode
        self.enabledKinds = preferences.enabledKinds
    }

    /// Whether the user can navigate back from the current page.
    public var canGoBack: Bool { page != .welcome }

    /// Advance to the next page if one exists.
    public func next() {
        guard let next = Page(rawValue: page.rawValue + 1) else { return }
        page = next
    }

    /// Return to the previous page if one exists.
    public func back() {
        guard let prev = Page(rawValue: page.rawValue - 1) else { return }
        page = prev
    }

    /// Skip applies only to the Pro intro page; other pages require
    /// advancing explicitly so the user actually sees the welcome and
    /// customization steps.
    public func skip() {
        guard page == .proIntro else { return }
        page = .complete
    }

    /// Persist the selected preferences and mark onboarding complete.
    ///
    /// Calling `complete()` more than once is safe — the preference writes
    /// are idempotent and the flag is just set to `true`.
    public func complete() {
        preferences.menuBarMode = selectedMode
        preferences.enabledKinds = enabledKinds
        preferences.onboardingCompleted = true
        page = .complete
    }

    /// Whether the user has previously finished onboarding.
    public var isComplete: Bool {
        preferences.onboardingCompleted
    }
}