import XCTest
@testable import kDupe

final class PerceptualDetectorTests: XCTestCase {
    func testIdenticalImagesDetected() async throws {
        guard #available(macOS 14, *) else {
            throw XCTSkip("Perceptual detection requires macOS 14+")
        }

        let detector = PerceptualDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let img1 = dir.appendingPathComponent("photo_a.jpg")
        let img2 = dir.appendingPathComponent("photo_b.jpg")
        try createTestImage(at: img1, color: .red)
        try createTestImage(at: img2, color: .red)

        let groups = try await detector.detect([img1, img2], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .perceptual)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testDifferentImagesNotGrouped() async throws {
        guard #available(macOS 14, *) else {
            throw XCTSkip("Perceptual detection requires macOS 14+")
        }

        let detector = PerceptualDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let img1 = dir.appendingPathComponent("red.jpg")
        let img2 = dir.appendingPathComponent("blue.jpg")
        try createTestImage(at: img1, color: .red)
        try createTestImage(at: img2, color: .blue)

        // Different solid colors produce different image hashes, so they
        // should not be grouped. We primarily verify the API completes
        // without error.
        let groups = try await detector.detect([img1, img2], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Different images should not be perceptually similar")
    }

    func testSingleImageNotGrouped() async throws {
        guard #available(macOS 14, *) else {
            throw XCTSkip("Perceptual detection requires macOS 14+")
        }

        let detector = PerceptualDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let img = dir.appendingPathComponent("solo.jpg")
        try createTestImage(at: img, color: .green)

        let groups = try await detector.detect([img], controller: controller)
        XCTAssertTrue(groups.isEmpty, "A single image cannot form a duplicate group")
    }

    func testEmptyURLs() async throws {
        guard #available(macOS 14, *) else {
            throw XCTSkip("Perceptual detection requires macOS 14+")
        }

        let detector = PerceptualDetector()
        let controller = ScanController()
        let groups = try await detector.detect([], controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        guard #available(macOS 14, *) else {
            throw XCTSkip("Perceptual detection requires macOS 14+")
        }

        let detector = PerceptualDetector()
        let controller = ScanController()
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let img = dir.appendingPathComponent("test.jpg")
        try createTestImage(at: img, color: .white)

        let groups = try await detector.detect([img], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan should return empty results")
    }

    // MARK: - Helpers

    /// Creates a small solid-color JPEG file at the given URL.
    @available(macOS 14, *)
    private func createTestImage(at url: URL, color: NSColor) throws {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "PerceptualDetectorTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from NSImage"])
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NSError(domain: "PerceptualDetectorTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
        try data.write(to: url)
    }
}
