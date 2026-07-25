import XCTest
@testable import FileScanner

final class FileHasherTests: XCTestCase {
    func testHashProducesString() async {
        let hasher = FileHasher()
        // Create a temporary file to hash
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-hash-\(UUID().uuidString).tmp")
        try? "Hello World".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let hash = try? await hasher.hash(file: tempURL)
        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.count, 64) // SHA-256 hex = 64 chars
    }
}
