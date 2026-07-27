import XCTest
import CoreData
@testable import kSpaceClean

@MainActor
final class GalaxyViewModelTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        context = createTestContext()
    }

    func test_update_withEmptyResults() {
        let vm = GalaxyViewModel()
        vm.update(with: [])
        XCTAssertTrue(vm.categories.isEmpty)
    }

    func test_update_groupsByCategory() {
        let vm = GalaxyViewModel()
        let entries = [
            makeEntry(category: "image", size: 100),
            makeEntry(category: "image", size: 200),
            makeEntry(category: "document", size: 300),
        ]
        vm.update(with: entries)
        XCTAssertEqual(vm.categories.count, 2)
        XCTAssertEqual(vm.categories.first { $0.category == .image }?.totalSize, 300)
        XCTAssertEqual(vm.categories.first { $0.category == .image }?.fileCount, 2)
        XCTAssertEqual(vm.categories.first { $0.category == .document }?.totalSize, 300)
        XCTAssertEqual(vm.categories.first { $0.category == .document }?.fileCount, 1)
    }

    func test_update_sortedBySizeDescending() {
        let vm = GalaxyViewModel()
        let entries = [
            makeEntry(category: "cache", size: 50),
            makeEntry(category: "image", size: 500),
            makeEntry(category: "document", size: 100),
        ]
        vm.update(with: entries)
        XCTAssertEqual(vm.categories.map(\.category), [.image, .document, .cache])
    }

    func test_selectCategory() {
        let vm = GalaxyViewModel()
        vm.selectCategory("image")
        XCTAssertEqual(vm.selectedCategory, .image)
    }

    func test_deselectAll() {
        let vm = GalaxyViewModel()
        vm.selectCategory("image")
        vm.deselectAll()
        XCTAssertNil(vm.selectedCategory)
    }

    func test_drillDown_appendsToBreadcrumb() {
        let vm = GalaxyViewModel()
        vm.drillDown("document")
        XCTAssertEqual(vm.breadcrumb, ["/", "document"])
    }

    // MARK: - Helpers
    func makeEntry(category: String, size: Int64) -> FileEntry {
        let e = FileEntry(context: context)
        e.id = UUID()
        e.path = "/test/\(category)/file"
        e.size = size
        e.category = category
        e.confidence = 0.95
        return e
    }
}
