import XCTest
@testable import kSpaceClean

@MainActor
final class StoreManagerTests: XCTestCase {
    func test_storeManager_conformsToStoreProtocol() {
        let manager = StoreManager()
        XCTAssertTrue(manager is StoreProtocol)
    }

    func test_storeManager_initialState() {
        let manager = StoreManager()
        XCTAssertFalse(manager.isSubscribed)
        XCTAssertTrue(manager.isEligibleForTrial)
    }
}
