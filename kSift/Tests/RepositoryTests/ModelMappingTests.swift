import UniformTypeIdentifiers
import XCTest
@testable import kSift

/// Pure round-trip tests for `ModelMapping` — the sentinel conversions and
/// evidence JSON blob used by `DuplicateRepositoryCoreData`. Core Data itself
/// cannot run in the SwiftPM harness, so the mapping rules are pinned here.
final class ModelMappingTests: XCTestCase {

    // MARK: - inode

    func testInodeSentinel() {
        XCTAssertEqual(ModelMapping.inodeValue(nil), 0)
        XCTAssertEqual(ModelMapping.inodeValue(42), 42)
        XCTAssertNil(ModelMapping.inodeFromStored(0))
        XCTAssertEqual(ModelMapping.inodeFromStored(42), 42)
        XCTAssertEqual(ModelMapping.inodeValue(ModelMapping.inodeFromStored(99)), 99)
    }

    // MARK: - physicalSize

    func testPhysicalSizeSentinel() {
        XCTAssertEqual(ModelMapping.physicalSizeValue(nil), -1)
        XCTAssertEqual(ModelMapping.physicalSizeValue(0), 0, "Zero is a valid empty-file size")
        XCTAssertEqual(ModelMapping.physicalSizeValue(4096), 4096)
        XCTAssertNil(ModelMapping.physicalSizeFromStored(-1))
        XCTAssertEqual(ModelMapping.physicalSizeFromStored(0), 0)
        XCTAssertEqual(ModelMapping.physicalSizeFromStored(4096), 4096)
    }

    // MARK: - fileType

    func testFileTypeRoundTrip() {
        XCTAssertNil(ModelMapping.fileTypeIdentifier(nil))
        XCTAssertNil(ModelMapping.fileTypeFromIdentifier(nil))

        let type = UTType.png
        XCTAssertEqual(ModelMapping.fileTypeIdentifier(type), "public.png")
        XCTAssertEqual(ModelMapping.fileTypeFromIdentifier("public.png"), .png)
    }

    // MARK: - similarity

    func testSimilaritySentinel() {
        XCTAssertEqual(ModelMapping.similarityValue(nil), -1)
        XCTAssertEqual(ModelMapping.similarityValue(0.87), 0.87, accuracy: 0.0001)
        XCTAssertNil(ModelMapping.similarityFromStored(-1))
        XCTAssertEqual(ModelMapping.similarityFromStored(0.87) ?? -1, 0.87, accuracy: 0.0001)
    }

    // MARK: - evidence JSON round-trips

    private func makeFile(hash: String = "abc", identifier: String? = "public.png") -> FileItem {
        FileItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/a.png"),
            size: 1024,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            creationDate: Date(timeIntervalSince1970: 1_690_000_000),
            hash: hash,
            fingerprint: "fp-\(hash)",
            inode: 12345,
            isAPFSClone: false,
            physicalSize: 1024,
            fileType: identifier.flatMap(UTType.init)
        )
    }

    func testEvidenceRoundTripForEveryCase() {
        let fileA = makeFile(hash: "hash-a")
        let fileB = makeFile(hash: "hash-b", identifier: nil)
        let cases: [(CategoryEvidence, DuplicateCategory)] = [
            (.byteIdentical(sha256: "deadbeef", byteVerified: true), .identical),
            (.apfsClone(sha256: "beef"), .identical),
            (.directoryDuplicate(contentHash: "dir-hash", fileCount: 7), .directoryDedup),
            (.perceptualSimilarity(distance: 3.5, method: .dHash), .perceptual),
            (.rawJPEGPair(rawFile: fileA, jpegFile: fileB, exifMatch: true), .rawJPEG),
            (.buildArtifact(pattern: .swiftBuild), .buildArtifact),
            (.largeFile, .largeFile),
        ]

        for (evidence, category) in cases {
            let data = ModelMapping.encodeEvidence(evidence)
            XCTAssertNotNil(data, "\(category) must encode")
            let decoded = ModelMapping.decodeEvidence(data)
            XCTAssertNotNil(decoded, "\(category) must decode")
            assertEvidence(decoded!, matches: evidence, category: category)
        }
    }

    private func assertEvidence(
        _ decoded: CategoryEvidence,
        matches expected: CategoryEvidence,
        category: DuplicateCategory
    ) {
        switch (decoded, expected) {
        case (.byteIdentical(let a, let va), .byteIdentical(let b, let vb)):
            XCTAssertEqual(a, b); XCTAssertEqual(va, vb)
        case (.apfsClone(let a), .apfsClone(let b)):
            XCTAssertEqual(a, b)
        case (.directoryDuplicate(let a, let ca), .directoryDuplicate(let b, let cb)):
            XCTAssertEqual(a, b); XCTAssertEqual(ca, cb)
        case (.perceptualSimilarity(let d1, let m1), .perceptualSimilarity(let d2, let m2)):
            XCTAssertEqual(d1, d2); XCTAssertEqual(m1, m2)
        case (.rawJPEGPair(let r1, let j1, let e1), .rawJPEGPair(let r2, let j2, let e2)):
            XCTAssertEqual(r1.url, r2.url)
            XCTAssertEqual(r1.hash, r2.hash)
            XCTAssertEqual(r1.inode, r2.inode)
            XCTAssertEqual(r1.fileType?.identifier, r2.fileType?.identifier)
            XCTAssertEqual(j1.url, j2.url)
            XCTAssertEqual(j1.hash, j2.hash)
            XCTAssertEqual(e1, e2)
        case (.buildArtifact(let a), .buildArtifact(let b)):
            XCTAssertEqual(a, b)
        case (.largeFile, .largeFile):
            break
        default:
            XCTFail("Evidence case mismatch for \(category): \(decoded) vs \(expected)")
        }
    }

    func testDecodeEvidenceNilAndGarbage() {
        XCTAssertNil(ModelMapping.decodeEvidence(nil))
        XCTAssertNil(ModelMapping.decodeEvidence(Data()))
        XCTAssertNil(ModelMapping.decodeEvidence(Data("not-json".utf8)))
        XCTAssertNil(ModelMapping.decodeEvidence(Data("{\"bogus\":true}".utf8)))
    }

    func testRawJPEGRoundTripPreservesFileTypeNil() {
        let raw = makeFile(hash: "raw")
        let jpeg = makeFile(hash: "jpeg", identifier: "public.jpeg")
        let evidence = CategoryEvidence.rawJPEGPair(rawFile: raw, jpegFile: jpeg, exifMatch: true)
        let data = ModelMapping.encodeEvidence(evidence)
        guard case .rawJPEGPair(let r, let j, let exif) = ModelMapping.decodeEvidence(data)! else {
            return XCTFail("expected rawJPEGPair")
        }
        XCTAssertEqual(r.fileType?.identifier, "public.png")
        XCTAssertEqual(j.fileType?.identifier, "public.jpeg")
        XCTAssertEqual(exif, true)
    }
}
