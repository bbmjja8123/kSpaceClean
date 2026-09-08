import CoreGraphics
import XCTest
import DetectionCore
@testable import kSift

final class PhotosLibraryScannerTests: XCTestCase {
    // MARK: - Stub

    private final class StubProvider: PhotoLibraryProviding, PhotoLibraryDeleting {
        var status: PhotoAuthorizationStatus = .authorized
        var snapshots: [PhotoAssetSnapshot] = []
        /// id → sha256 (locally-available assets only)
        var hashes: [String: String] = [:]
        /// id → dHash (thumbnail-able assets only)
        var thumbs: [String: UInt64] = [:]
        var deletedIDs: [String] = []

        func authorizationStatus() -> PhotoAuthorizationStatus { status }
        func requestAccess() async -> Bool { true }
        func fetchPhotoSnapshots() -> [PhotoAssetSnapshot] { snapshots }

        func sha256IfLocallyAvailable(id: String) async -> String? {
            hashes[id]
        }

        func thumbnail(id: String, maxPixelSize: Int) async -> CGImage? {
            nil // real CGImage rendering not needed; perceptual tests use prehashed assets
        }

        func deleteAssets(ids: [String]) async throws {
            deletedIDs.append(contentsOf: ids)
        }
    }

    private func snapshot(_ id: String, width: Int = 100, height: Int = 100) -> PhotoAssetSnapshot {
        PhotoAssetSnapshot(id: id, pixelWidth: width, pixelHeight: height, creationDate: Date())
    }

    // MARK: - Authorization gating

    func testScanFailsClosedWhenNotAuthorized() async {
        let provider = StubProvider()
        provider.status = .denied
        let scanner = PhotosLibraryScanner(provider: provider)
        let outcome = await scanner.scan(controller: ScanController())
        XCTAssertNil(outcome, "Denied library must not be scanned")
    }

    func testLimitedAccessStillScans() async {
        let provider = StubProvider()
        provider.status = .limited
        let scanner = PhotosLibraryScanner(provider: provider)
        let outcome = await scanner.scan(controller: ScanController())
        XCTAssertNotNil(outcome, "Limited access is a valid scan scope")
    }

    // MARK: - Exact pass

    func testByteIdenticalAssetsGroupAsIdentical() async {
        let provider = StubProvider()
        provider.snapshots = [snapshot("a"), snapshot("b"), snapshot("c", width: 200, height: 200)]
        provider.hashes = ["a": "deadbeef", "b": "deadbeef", "c": "cafebabe"]
        let scanner = PhotosLibraryScanner(provider: provider)
        let outcome = await scanner.scan(controller: ScanController())

        let identical = outcome?.groups.filter { $0.category == .identical } ?? []
        XCTAssertEqual(identical.count, 1)
        XCTAssertEqual(identical[0].files.count, 2)
        XCTAssertTrue(identical[0].files.allSatisfy { $0.photosLocalIdentifier != nil })
    }

    func testCloudOnlyAssetsSkippedAndCounted() async {
        let provider = StubProvider()
        provider.snapshots = [snapshot("local"), snapshot("cloud"), snapshot("cloud2")]
        provider.hashes = ["local": "deadbeef"]
        let scanner = PhotosLibraryScanner(provider: provider)
        let outcome = await scanner.scan(controller: ScanController())

        XCTAssertEqual(outcome?.cloudSkipped, 2, "Assets without local bytes are iCloud-only: skipped, not downloaded")
        XCTAssertEqual(outcome?.totalAssets, 3)
        XCTAssertTrue(outcome?.groups.isEmpty ?? true)
    }

    // MARK: - FileItem bridging

    func testPhotosAssetURLRoundTrip() {
        let id = "ABC/DEF==123"
        let url = FileItem.photosAssetURL(id)
        XCTAssertEqual(url.scheme, "photos-asset")
        XCTAssertNotNil(url.host)
    }

    func testFileItemCodableBackCompatWithPhotosID() throws {
        let item = FileItem(
            id: UUID(),
            url: FileItem.photosAssetURL("abc"),
            size: 0,
            modificationDate: Date(),
            photosLocalIdentifier: "abc"
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(FileItem.self, from: data)
        XCTAssertEqual(decoded.photosLocalIdentifier, "abc")

        // Legacy payloads (v1.2) without the photosLocalIdentifier key
        // decode to nil — isAPFSClone was already present back then.
        let legacy = """
        {"id":"\(item.id.uuidString)","url":"file:///tmp/x","size":1,"modificationDate":0,"isAPFSClone":false}
        """
        let legacyItem = try JSONDecoder().decode(FileItem.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyItem.photosLocalIdentifier)
    }

    // MARK: - Cleanup

    func testCleanupRoutesThroughLibraryDelete() async {
        let provider = StubProvider()
        let manager = PhotosCleanupManager(library: provider)
        let files = [
            FileItem(id: UUID(), url: FileItem.photosAssetURL("p1"), size: 0, modificationDate: Date(), photosLocalIdentifier: "p1"),
            FileItem(id: UUID(), url: FileItem.photosAssetURL("p2"), size: 0, modificationDate: Date(), photosLocalIdentifier: "p2"),
            FileItem(id: UUID(), url: URL(fileURLWithPath: "/tmp/plain"), size: 0, modificationDate: Date()),
        ]
        let failures = await manager.delete(files)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(Set(provider.deletedIDs), ["p1", "p2"], "Only Photos-backed items go to Recently Deleted")
    }

    func testCleanupReportsFailures() async {
        final class FailingLibrary: PhotoLibraryDeleting {
            func deleteAssets(ids: [String]) async throws {
                throw NSError(domain: "ksift.tests", code: 1)
            }
        }
        let manager = PhotosCleanupManager(library: FailingLibrary())
        let files = [FileItem(id: UUID(), url: FileItem.photosAssetURL("p1"), size: 0, modificationDate: Date(), photosLocalIdentifier: "p1")]
        let failures = await manager.delete(files)
        XCTAssertEqual(failures, ["p1"])
    }
}
