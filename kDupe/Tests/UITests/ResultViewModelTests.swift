import XCTest
@testable import kDupe

@MainActor
final class ResultViewModelTests: XCTestCase {
    func testFilterByCategory() {
        let vm = ResultViewModel()
        let groups = [
            makeGroup(cat: .identical, size: 100),
            makeGroup(cat: .largeFile, size: 2000),
            makeGroup(cat: .identical, size: 50),
        ]
        vm.groups = groups

        vm.activeCategory = .identical
        XCTAssertEqual(vm.filteredGroups.count, 2)

        vm.activeCategory = .largeFile
        XCTAssertEqual(vm.filteredGroups.count, 1)

        vm.activeCategory = nil
        XCTAssertEqual(vm.filteredGroups.count, 3)
    }

    func testSortBySizeDesc() {
        let vm = ResultViewModel()
        vm.groups = [
            makeGroup(cat: .identical, size: 100),
            makeGroup(cat: .largeFile, size: 2000),
            makeGroup(cat: .buildArtifact, size: 50),
        ]
        vm.sortOrder = .sizeDesc
        XCTAssertEqual(vm.filteredGroups[0].totalSize, 2000)
    }

    func testAutoSelect() {
        let vm = ResultViewModel()
        vm.groups = [makeGroup(cat: .identical, size: 100)]
        vm.autoSelectGroups()
        XCTAssertEqual(vm.selectedGroupIds.count, 1)
    }

    private func makeGroup(cat: DuplicateCategory, size: Int64) -> DuplicateGroup {
        DuplicateGroup(
            id: UUID(),
            category: cat,
            totalSize: size,
            fileCount: 1,
            files: [FileItem(id: UUID(), url: URL(filePath: "/tmp/a"), size: size,
                           modificationDate: Date(), hash: nil)],
            title: "Test \(cat)"
        )
    }
}
