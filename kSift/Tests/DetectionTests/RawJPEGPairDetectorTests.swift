import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import kSift

final class RawJPEGPairDetectorTests: XCTestCase {
    func testBasicPairUsesSameDirectoryAndStem() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = try createTempFile(named: "photo.cr3", in: directory, withSize: 5_000)
        let jpeg = try createTempFile(named: "photo.jpg", in: directory, withSize: 500)

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.map(\.url), [raw, jpeg])
        XCTAssertEqual(groups[0].totalSize, 0, "No keep choice has been made yet")
        guard case .rawJPEGPair(let evidenceRaw, let evidenceJPEG, let exifMatch) = groups[0].categoryEvidence else {
            return XCTFail("Expected RAW/JPEG evidence")
        }
        XCTAssertEqual(evidenceRaw.url, raw)
        XCTAssertEqual(evidenceJPEG.url, jpeg)
        XCTAssertFalse(exifMatch)
    }

    func testSameStemInDifferentDirectoriesDoesNotPair() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDirectory = root.appendingPathComponent("first")
        let secondDirectory = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let raw = try createTempFile(named: "photo.nef", in: firstDirectory, withSize: 100)
        let jpeg = try createTempFile(named: "photo.jpg", in: secondDirectory, withSize: 100)

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testDifferentStemsDoNotPair() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = try createTempFile(named: "photo-a.arw", in: directory, withSize: 100)
        let jpeg = try createTempFile(named: "photo-b.jpg", in: directory, withSize: 100)

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testPairingIsOneToOne() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rawA = try createTempFile(named: "photo.cr2", in: directory, withSize: 100)
        let rawB = try createTempFile(named: "photo.nef", in: directory, withSize: 100)
        let jpeg = try createTempFile(named: "photo.jpg", in: directory, withSize: 100)

        let groups = await RawJPEGPairDetector().detect(
            [rawA, rawB, jpeg],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
    }

    func testExtendedRAWExtensionsAreSupported() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = ["raf", "cr2", "cr3", "nef", "nrw", "arw", "dng", "orf", "rw2"]
        var urls: [URL] = []
        for (index, fileExtension) in extensions.enumerated() {
            urls.append(try createTempFile(
                named: "photo-\(index).\(fileExtension)",
                in: directory,
                withSize: 100
            ))
            urls.append(try createTempFile(
                named: "photo-\(index).jpg",
                in: directory,
                withSize: 10
            ))
        }

        let groups = await RawJPEGPairDetector().detect(urls, controller: ScanController())

        XCTAssertEqual(groups.count, extensions.count)
    }

    func testEXIFDatesWithinToleranceAreMarkedAsMatch() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("capture.dng")
        let jpeg = directory.appendingPathComponent("capture.jpg")
        try writeJPEG(at: raw, exifDate: "2026:08:01 10:00:00")
        try writeJPEG(at: jpeg, exifDate: "2026:08:01 10:00:02")

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        guard case .rawJPEGPair(_, _, let exifMatch) = groups[0].categoryEvidence else {
            return XCTFail("Expected RAW/JPEG evidence")
        }
        XCTAssertTrue(exifMatch)
    }

    func testEXIFDatesOutsideToleranceRejectPair() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("capture.dng")
        let jpeg = directory.appendingPathComponent("capture.jpg")
        try writeJPEG(at: raw, exifDate: "2026:08:01 10:00:00")
        try writeJPEG(at: jpeg, exifDate: "2026:08:01 10:00:03")

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testUnmatchedFilesAreExcluded() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = try createTempFile(named: "raw-only.raf", in: directory, withSize: 100)
        let jpeg = try createTempFile(named: "jpeg-only.jpg", in: directory, withSize: 100)

        let groups = await RawJPEGPairDetector().detect(
            [raw, jpeg],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = try createTempFile(named: "photo.raf", in: directory, withSize: 100)
        let jpeg = try createTempFile(named: "photo.jpg", in: directory, withSize: 100)
        let controller = ScanController()
        controller.cancel()

        let groups = await RawJPEGPairDetector().detect([raw, jpeg], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }

    private func writeJPEG(at url: URL, exifDate: String) throws {
        guard let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "RawJPEGPairDetectorTests", code: 1)
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: exifDate,
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "RawJPEGPairDetectorTests", code: 2)
        }
    }
}
