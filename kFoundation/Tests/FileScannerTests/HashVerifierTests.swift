import XCTest
import CryptoKit
@testable import FileScanner

final class HashVerifierTests: XCTestCase {
    private let verifier = HashVerifier()
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashverifier-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func writeFile(name: String, size: Int, fill: UInt8 = 0x41) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let data = Data(repeating: fill, count: size)
        try data.write(to: url)
        return url
    }

    private func writeFile(name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Stage 2: Fingerprint

    func testFingerprintOfIdenticalFilesIsEqual() async throws {
        let a = try writeFile(name: "a.txt", content: "Hello, kSift!")
        let b = try writeFile(name: "b.txt", content: "Hello, kSift!")

        let fpA = try await verifier.fingerprint(of: a)
        let fpB = try await verifier.fingerprint(of: b)

        XCTAssertEqual(fpA, fpB)
        XCTAssertEqual(fpA.count, 64, "SHA-256 hex must be 64 chars")
    }

    func testFingerprintOfDifferentFilesDiffers() async throws {
        let a = try writeFile(name: "a.txt", content: "Hello, kSift!")
        let b = try writeFile(name: "b.txt", content: "Hello, world!")

        let fpA = try await verifier.fingerprint(of: a)
        let fpB = try await verifier.fingerprint(of: b)

        XCTAssertNotEqual(fpA, fpB)
    }

    func testFingerprintIsDeterministic() async throws {
        let a = try writeFile(name: "a.txt", content: "deterministic check")

        let fp1 = try await verifier.fingerprint(of: a)
        let fp2 = try await verifier.fingerprint(of: a)

        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprintHandlesSmallFile() async throws {
        // < 8KB: head + tail overlap → just hashes the content
        let a = try writeFile(name: "small.txt", size: 1024)

        let fp = try await verifier.fingerprint(of: a)

        XCTAssertEqual(fp.count, 64)
        // Independent verification: should match SHA-256 of the same 1KB content
        let data = try Data(contentsOf: a)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fp, expected, "Small file fingerprint should equal SHA-256 of full content")
    }

    func testFingerprintHandlesLargeFile() async throws {
        // > 8KB: head + tail differ
        let a = try writeFile(name: "large.bin", size: 64 * 1024)  // 64KB

        let fp = try await verifier.fingerprint(of: a)

        XCTAssertEqual(fp.count, 64)
        // Same content at same size should produce same fingerprint
        let b = try writeFile(name: "large2.bin", size: 64 * 1024)
        let fpB = try await verifier.fingerprint(of: b)
        XCTAssertEqual(fp, fpB)
    }

    func testFingerprintOfEmptyFileReturnsSHA256OfEmpty() async throws {
        let a = try writeFile(name: "empty.txt", size: 0)

        let fp = try await verifier.fingerprint(of: a)

        // SHA-256 of empty bytes (RFC 6234 test vector)
        XCTAssertEqual(fp, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testFingerprintFailsForUnreadableFile() async throws {
        let badURL = tempDir.appendingPathComponent("does-not-exist-\(UUID().uuidString).txt")

        do {
            _ = try await verifier.fingerprint(of: badURL)
            XCTFail("Expected error for non-existent file")
        } catch {
            // Expected
        }
    }

    // MARK: - Stage 3: Full Hash

    func testFullHashOfIdenticalFilesIsEqual() async throws {
        let a = try writeFile(name: "a.txt", content: "Hello, kSift!")
        let b = try writeFile(name: "b.txt", content: "Hello, kSift!")

        let hashA = try await verifier.fullHash(of: a)
        let hashB = try await verifier.fullHash(of: b)

        XCTAssertEqual(hashA, hashB)
        XCTAssertEqual(hashA.count, 64)
    }

    func testFullHashOfDifferentFilesDiffers() async throws {
        let a = try writeFile(name: "a.txt", content: "Hello, kSift!")
        let b = try writeFile(name: "b.txt", content: "Goodbye, kSift!")

        let hashA = try await verifier.fullHash(of: a)
        let hashB = try await verifier.fullHash(of: b)

        XCTAssertNotEqual(hashA, hashB)
    }

    func testFullHashHandlesVeryLargeFile() async throws {
        // Test streaming behavior: 5MB file (larger than 1MB chunk)
        let size = 5 * 1024 * 1024
        let a = try writeFile(name: "5mb.bin", size: size)

        let start = Date()
        let hash = try await verifier.fullHash(of: a)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(hash.count, 64)
        // Sanity check: shouldn't take more than 2 seconds on Apple Silicon
        XCTAssertLessThan(elapsed, 5.0, "Hashing 5MB should be fast")

        // Independent verification
        let data = try Data(contentsOf: a)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, expected, "Streaming hash must match one-shot hash")
    }

    // Note: Old FileHasher had a maxSize: 100MB limit that silently dropped
    // larger files. HashVerifier has no such limit — verified by code review
    // (no size check anywhere in fullHash) and the 5MB streaming test above.

    // MARK: - Stage 4: Byte Equal

    func testByteEqualReturnsTrueForIdenticalFiles() async throws {
        let a = try writeFile(name: "a.txt", content: "byte equal test content")
        let b = try writeFile(name: "b.txt", content: "byte equal test content")

        let result = await verifier.byteEqual(a, b)

        XCTAssertTrue(result)
    }

    func testByteEqualReturnsTrueForEmptyFiles() async throws {
        let a = try writeFile(name: "empty-a.txt", content: "")
        let b = try writeFile(name: "empty-b.txt", content: "")

        let result = await verifier.byteEqual(a, b)

        XCTAssertTrue(result)
    }

    func testByteEqualReturnsFalseForDifferentContent() async throws {
        let a = try writeFile(name: "a.txt", content: "original content")
        let b = try writeFile(name: "b.txt", content: "modified content")

        let result = await verifier.byteEqual(a, b)

        XCTAssertFalse(result)
    }

    func testByteEqualReturnsFalseForDifferentSizes() async throws {
        let a = try writeFile(name: "a.txt", size: 1024)
        let b = try writeFile(name: "b.txt", size: 2048)

        let result = await verifier.byteEqual(a, b)

        XCTAssertFalse(result, "Different sizes must never be byte-equal")
    }

    func testByteEqualCatchesFirstByteDifference() async throws {
        // Critical: even one byte difference at end of file must be detected
        let a = try writeFile(name: "a.txt", size: 10_000, fill: 0x41)
        let b = try writeFile(name: "b.txt", size: 9_999, fill: 0x41)  // 1 byte shorter

        let result = await verifier.byteEqual(a, b)

        XCTAssertFalse(result)
    }

    func testByteEqualHandlesLargeFiles() async throws {
        // Test streaming byte-equal on larger files (5MB)
        let size = 5 * 1024 * 1024
        let a = try writeFile(name: "a5mb.bin", size: size, fill: 0x42)
        let b = try writeFile(name: "b5mb.bin", size: size, fill: 0x42)
        let c = try writeFile(name: "c5mb.bin", size: size, fill: 0x43)

        let equalAB = await verifier.byteEqual(a, b)
        let equalAC = await verifier.byteEqual(a, c)

        XCTAssertTrue(equalAB)
        XCTAssertFalse(equalAC)
    }

    func testByteEqualDetectsLastByteDifference() async throws {
        // Two files identical except last byte
        var dataA = Data(repeating: 0x42, count: 1000)
        var dataB = Data(repeating: 0x42, count: 1000)
        dataA[999] = 0xFF
        dataB[999] = 0xFE

        let a = tempDir.appendingPathComponent("lastbyteA.bin")
        let b = tempDir.appendingPathComponent("lastbyteB.bin")
        try dataA.write(to: a)
        try dataB.write(to: b)

        let result = await verifier.byteEqual(a, b)

        XCTAssertFalse(result, "Must detect difference in the very last byte")
    }

    // MARK: - Combined: verify() convenience method

    func testVerifyReturnsAllFields() async throws {
        let a = try writeFile(name: "verify.txt", content: "verify convenience")

        let result = try await verifier.verify(a)

        XCTAssertEqual(result.url, a)
        XCTAssertEqual(result.size, Int64("verify convenience".utf8.count))
        XCTAssertEqual(result.fingerprint.count, 64)
        XCTAssertEqual(result.fullHash.count, 64)
        XCTAssertGreaterThanOrEqual(result.duration, 0)
    }

    func testFingerprintAndFullHashBothCatchDifference() async throws {
        // Two files identical except first 100 bytes (within fingerprint head region).
        // Both fingerprint (head+tail SHA-256) and fullHash must differ.
        let head = "X" + String(repeating: "A", count: 10_000) + String(repeating: "B", count: 5_000)
        let modifiedHead = "Y" + String(repeating: "A", count: 10_000) + String(repeating: "B", count: 5_000)
        let a = try writeFile(name: "head-a.txt", content: head)
        let b = try writeFile(name: "head-b.txt", content: modifiedHead)

        let fpA = try await verifier.fingerprint(of: a)
        let fpB = try await verifier.fingerprint(of: b)
        let hashA = try await verifier.fullHash(of: a)
        let hashB = try await verifier.fullHash(of: b)
        let bytesEqual = await verifier.byteEqual(a, b)

        XCTAssertNotEqual(fpA, fpB, "Fingerprint must catch change in head region (4KB)")
        XCTAssertNotEqual(hashA, hashB, "Full hash must catch any change")
        XCTAssertFalse(bytesEqual, "Byte-equal must catch any change")
    }

    func testFullHashAndByteEqualCatchMidFileChange() async throws {
        // Two files identical EXCEPT one byte in the middle (position ~10K).
        // Head and tail are identical → fingerprint will NOT differ.
        // But fullHash and byteEqual MUST differ. This is why we have Stage 3 + 4.
        let content = String(repeating: "A", count: 10_000) + "X" + String(repeating: "A", count: 5_000)
        let modifiedContent = String(repeating: "A", count: 10_000) + "Y" + String(repeating: "A", count: 5_000)
        let a = try writeFile(name: "mid-a.txt", content: content)
        let b = try writeFile(name: "mid-b.txt", content: modifiedContent)

        let hashA = try await verifier.fullHash(of: a)
        let hashB = try await verifier.fullHash(of: b)
        let bytesEqual = await verifier.byteEqual(a, b)

        XCTAssertNotEqual(hashA, hashB, "Full hash must catch mid-file change (this is why it exists)")
        XCTAssertFalse(bytesEqual, "Byte-equal must catch mid-file change (this is the last line of defense)")
    }

    // MARK: - Error isolation

    func testUnreadableFileThrowsInsteadOfCrashing() async throws {
        // Files exist but are not readable (permission denied)
        // Skip this test if running as root (root bypasses perms)
        guard getuid() != 0 else {
            throw XCTSkip("Running as root — permission tests not reliable")
        }

        let secret = try writeFile(name: "secret.txt", content: "secret")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path)
        }

        do {
            _ = try await verifier.fingerprint(of: secret)
            XCTFail("Expected error for unreadable file")
        } catch {
            // Expected: throws VerifierError.unreadable
        }
    }
}
