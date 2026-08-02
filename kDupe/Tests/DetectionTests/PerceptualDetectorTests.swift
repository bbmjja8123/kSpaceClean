import AppKit
import XCTest
@testable import kSift

final class PerceptualDetectorTests: XCTestCase {
    func testIdenticalImagesPassVisionVerification() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try writeImage(at: first, pattern: .checkerboard)
        try writeImage(at: second, pattern: .checkerboard)

        let groups = await PerceptualDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].fileCount, 2)
        let similarity = try XCTUnwrap(groups[0].similarity)
        XCTAssertEqual(similarity, 1, accuracy: 0.001)
        guard case .perceptualSimilarity(let distance, let method) = groups[0].categoryEvidence else {
            return XCTFail("Expected perceptual evidence")
        }
        XCTAssertEqual(distance, 0, accuracy: 0.001)
        XCTAssertEqual(method, .visionFeaturePrint)
    }

    func testVisuallyDifferentImagesAreNotGrouped() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("checkerboard.png")
        let second = directory.appendingPathComponent("split.png")
        try writeImage(at: first, pattern: .checkerboard)
        try writeImage(at: second, pattern: .verticalSplit)

        let groups = await PerceptualDetector(
            maximumHammingDistance: 64,
            visionDistanceThreshold: 0.01
        ).detect([first, second], controller: ScanController())

        XCTAssertTrue(groups.isEmpty)
    }

    func testDHashIsDeterministic() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("image.png")
        try writeImage(at: image, pattern: .verticalSplit)
        let detector = PerceptualDetector()

        let first = await detector.dHash(of: image)
        let second = await detector.dHash(of: image)

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testHammingDistanceCountsChangedBits() async {
        let detector = PerceptualDetector()

        let distance = await detector.hammingDistance(0b0000, 0b1011)

        XCTAssertEqual(distance, 3)
    }

    func testSingleImageCannotCreateGroup() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("single.png")
        try writeImage(at: image, pattern: .checkerboard)

        let groups = await PerceptualDetector().detect(
            [image],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testNonImageFileIsIgnored() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = try createTextFile(named: "notes.txt", in: directory, content: "not an image")

        let groups = await PerceptualDetector().detect(
            [text],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testCorruptImageIsIgnoredWithoutFailingBatch() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        let corrupt = try createTextFile(named: "corrupt.jpg", in: directory, content: "invalid")
        try writeImage(at: first, pattern: .checkerboard)
        try writeImage(at: second, pattern: .checkerboard)

        let groups = await PerceptualDetector().detect(
            [corrupt, first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), Set([first, second]))
    }

    func testRAWExtensionIsSkippedEvenWhenImageIOCanDecodeIt() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("photo.dng")
        try writeImage(at: raw, pattern: .checkerboard)
        let detector = PerceptualDetector()

        let groups = await detector.detect([raw, raw], controller: ScanController())

        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("image.png")
        try writeImage(at: image, pattern: .checkerboard)
        let controller = ScanController()
        controller.cancel()

        let groups = await PerceptualDetector().detect([image, image], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }

    private enum Pattern {
        case checkerboard
        case verticalSplit
    }

    private func writeImage(at url: URL, pattern: Pattern) throws {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        switch pattern {
        case .checkerboard:
            NSColor.black.setFill()
            for row in 0..<8 {
                for column in 0..<8 where (row + column).isMultiple(of: 2) {
                    NSRect(x: column * 16, y: row * 16, width: 16, height: 16).fill()
                }
            }
        case .verticalSplit:
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 64, height: 128).fill()
        }
        image.unlockFocus()

        guard let representation = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: representation),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PerceptualDetectorTests", code: 1)
        }
        try data.write(to: url)
    }
}
