import Foundation
import PowerScope

/// App-level holder for the shared `PowerScope` actor plus a
/// SwiftUI-observable capability snapshot.
///
/// Phase 1 stopgap until Phase 2's `AppGraph` becomes the single DI root —
/// the scan engine, settings surface, and (later) the onboarding grant flow
/// all read through here so there is exactly one bookmark store and one
/// probe per process.
@MainActor
final class AppScope: ObservableObject {
    static let shared = AppScope()

    let scope: PowerScope

    @Published private(set) var capability: ScopeCapability

    private init() {
        scope = PowerScope()
        capability = ScopeCapability(level: .containerOnly)
    }

    /// Resolve any persisted bookmark and probe public dirs. Call once per
    /// session at app start.
    func refresh() async {
        capability = await scope.refresh()
    }

    /// Present the home-folder grant panel and adopt the new capability.
    func grant() async {
        capability = (try? await scope.grantHomeFolder()) ?? capability
    }

    func revoke() async {
        await scope.revoke()
        capability = await scope.capability()
    }
}
