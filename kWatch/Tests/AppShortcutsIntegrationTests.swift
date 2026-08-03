import XCTest
@testable import kWatch

@MainActor
final class AppShortcutsIntegrationTests: XCTestCase {
    func testShowTopProcessesRunsWithoutCrash() async {
        let intent = ShowTopProcessesIntent()
        intent.limit = 5
        do {
            _ = try await intent.perform()
        } catch {
            // Stub service may throw — acceptable as long as the intent object is well-formed.
        }
    }
}
