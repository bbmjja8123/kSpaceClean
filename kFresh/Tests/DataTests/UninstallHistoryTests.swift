import CoreData
import XCTest
@testable import kFresh

final class UninstallHistoryTests: XCTestCase {
    func testCorruptedResidueDataReturnsEmptyAndLogs() throws {
        // Build an in-memory Core Data store using the production entity schema.
        let container = NSPersistentContainer(
            name: "UninstallHistory",
            managedObjectModel: UninstallHistoryRepository.makeModel()
        )
        container.persistentStoreDescriptions.first?.type = NSInMemoryStoreType

        let expectation = XCTestExpectation(description: "load stores")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let context = container.viewContext
        let history = UninstallHistory(context: context)

        // Set corrupted (non-JSON) data
        history.residueData = Data("not-valid-json".utf8) as NSData

        // Should return empty, not crash
        let residues = history.residues
        XCTAssertTrue(residues.isEmpty)
    }
}
