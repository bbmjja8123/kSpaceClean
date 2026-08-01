import Foundation

/// Drives the five-page first-launch onboarding flow.
///
/// Owns which page is showing, the last known Full Disk Access status, and
/// whether onboarding has been completed. The completion flag is persisted so
/// returning users go straight to the app.
///
/// The page sequence is fixed by the brand guidelines in `CLAUDE.md` §5.4:
/// Welcome → 价值主张 → 权限申请 → 隐私承诺 → Ready.
@MainActor
public final class FDAGuideController: ObservableObject {
    /// A page in the onboarding flow, ordered by `rawValue`.
    public enum Page: Int, CaseIterable, Equatable {
        /// Introduces kFresh.
        case welcome
        /// States what the app does for the user.
        case value
        /// Lists the permissions kFresh asks for, and why.
        case permission
        /// The privacy commitment: no network, no collection.
        case privacy
        /// Confirms setup is finished.
        case ready
    }

    /// `UserDefaults` key recording that onboarding finished.
    ///
    /// Namespaced to kFresh so the four Kraftly apps cannot collide if they
    /// ever share a defaults suite.
    public static let onboardingKey = "kFresh.hasCompletedOnboarding"

    /// The page currently on screen.
    @Published public private(set) var currentPage: Page = .welcome

    /// Last known Full Disk Access status.
    ///
    /// Starts as ``FDAStatus/unknown`` and is filled in by ``refreshFDAStatus()``.
    @Published public private(set) var fdaStatus: FDAStatus = .unknown

    /// Whether onboarding has been completed.
    ///
    /// Published rather than read straight from `UserDefaults` so SwiftUI can
    /// observe it and dismiss the onboarding sheet.
    @Published public private(set) var isCompleted: Bool

    private let probe: FDAPermissionProbe
    private let defaults: UserDefaults

    /// Creates a controller.
    ///
    /// - Parameters:
    ///   - probe: Supplies the Full Disk Access status shown on the permission page.
    ///   - defaults: Store for the completion flag. Injectable for testing.
    public init(probe: FDAPermissionProbe, defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
        self.isCompleted = defaults.bool(forKey: Self.onboardingKey)
    }

    /// Re-checks Full Disk Access and republishes ``fdaStatus``.
    ///
    /// Call when onboarding appears and again after returning from System
    /// Settings, so the permission page reflects a grant the user just made.
    public func refreshFDAStatus() async {
        fdaStatus = await probe.probe()
    }

    /// Moves to the next page, completing onboarding if already on the last one.
    public func advance() {
        guard let next = Page(rawValue: currentPage.rawValue + 1) else {
            markCompleted()
            return
        }
        currentPage = next
    }

    /// Skips the permission request and jumps to the final page.
    ///
    /// Chosen by users who decline Full Disk Access. kFresh stays usable in
    /// basic mode, so this finishes the tour rather than blocking it.
    public func skipFromPermission() {
        currentPage = .ready
    }

    /// Marks onboarding complete and persists the flag.
    public func markCompleted() {
        defaults.set(true, forKey: Self.onboardingKey)
        isCompleted = true
    }
}
