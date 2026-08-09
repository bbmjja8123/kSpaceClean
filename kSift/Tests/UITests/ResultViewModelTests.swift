import XCTest
@testable import kSift

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

    func testLoadGroupsReplacesAndResetsSelection() {
        let vm = ResultViewModel()
        let a = makeGroup(cat: .identical, size: 100)
        let b = makeGroup(cat: .largeFile, size: 2000)
        vm.groups = [a]
        vm.activeCategory = .largeFile
        vm.autoSelectGroups()

        vm.loadGroups([b])
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups[0].id, b.id)
        XCTAssertTrue(vm.selectedGroupIds.isEmpty, "Selection must not leak across loads")
        XCTAssertNil(vm.activeCategory, "Category filter must not leak across loads")
    }

    // MARK: - removeSelected

    private func makeVaultCleanupManager(
        in dir: URL
    ) -> (CleanupManager, TrashRedirectingFileManager) {
        let trash = TrashRedirectingFileManager(trashRoot: dir.appendingPathComponent("trash"))
        let vault = VaultManager(
            vaultRoot: dir.appendingPathComponent("vault"),
            repository: MockVaultRepository(),
            fileManager: trash,
            hashFile: VaultManager.sha256(of:)
        )
        return (CleanupManager(vault: vault), trash)
    }

    private func makeFilePair(in dir: URL) throws -> (oldest: FileItem, newest: FileItem) {
        let oldestURL = try createTempFile(named: "old.bin", in: dir, withSize: 1024)
        let newestURL = try createTempFile(named: "new.bin", in: dir, withSize: 1024)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-3600)], ofItemAtPath: oldestURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: newestURL.path)
        return (
            oldest: .mock(
                url: oldestURL, size: 1024,
                modificationDate: now.addingTimeInterval(-3600),
                hash: try VaultManager.sha256(of: oldestURL)
            ),
            newest: .mock(
                url: newestURL, size: 1024,
                modificationDate: now,
                hash: try VaultManager.sha256(of: newestURL)
            )
        )
    }

    func testRemoveSelectedKeepsNewestCopy() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (oldest, newest) = try makeFilePair(in: dir)
        let group = DuplicateGroup.mock(
            totalSize: 2048,
            fileCount: 2,
            files: [oldest, newest]
        )
        let vm = ResultViewModel()
        vm.groups = [group]
        vm.autoSelectGroups()

        let (manager, trash) = makeVaultCleanupManager(in: dir)
        let failures = await vm.removeSelected(using: manager)

        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(vm.groups.isEmpty, "Fully-successful groups leave the list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldest.url.path), "Oldest copy must be trashed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.url.path), "Newest copy must be kept")
        XCTAssertEqual(trash.trashedPaths.count, 1)
    }

    func testRemoveSelectedSurfacesFailuresAndKeepsGroup() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (oldest, newest) = try makeFilePair(in: dir)
        let group = DuplicateGroup.mock(
            totalSize: 2048,
            fileCount: 2,
            files: [oldest, newest]
        )
        let vm = ResultViewModel()
        vm.groups = [group]
        vm.autoSelectGroups()

        let (manager, trash) = makeVaultCleanupManager(in: dir)
        trash.failTrashPaths = [oldest.url.path]
        let failures = await vm.removeSelected(using: manager)

        // Asserted invariants:
        //   1. Exactly one failure surfaces, attributed to the URL that
        //      failTrashPaths refused (oldest).
        //   2. vm.groups keeps the failed group so the user can retry.
        //   3. selectedGroupIds clears so the user re-selects consciously.
        //   4. Original files stay in place: oldest because trash threw,
        //      newest because it's the kept copy.
        //   5. The redirector's trashedPaths is empty — phase-2 throw
        //      happened before _trashedPaths.append.
        XCTAssertEqual(failures.count, 1, "The failed trash is surfaced, not swallowed")
        XCTAssertEqual(failures[0].url, oldest.url)
        XCTAssertEqual(vm.groups.count, 1, "Group with a failed file stays for retry")
        XCTAssertTrue(vm.selectedGroupIds.isEmpty, "Selection clears so the user re-selects consciously")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldest.url.path), "Failed trash leaves the original in place")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.url.path), "The newest copy is the one kept — untouched")
        XCTAssertEqual(trash.trashedPaths.count, 0)
    }

    private func makeGroup(cat: DuplicateCategory, size: Int64) -> DuplicateGroup {
        .mock(
            category: cat,
            totalSize: size,
            fileCount: 1,
            files: [.mock(url: URL(filePath: "/tmp/a"), size: size)]
        )
    }
}
