import AVFoundation
import CoreGraphics
import XCTest
@testable import DetectionCore

final class SimilarVideoDetectorTests: XCTestCase {
    // MARK: - Stub hasher

    /// Deterministic synthetic hashes — no media files needed for the
    /// grouping logic (prefilter, ratio threshold, union-find, cancel).
    private struct StubHasher: VideoFrameHashing {
        var hashesByPath: [String: [UInt64]]
        var durationByPath: [String: TimeInterval] = [:]

        func frameHashes(for url: URL, sampleCount: Int) async throws -> [UInt64] {
            hashesByPath[url.path] ?? []
        }

        func duration(of url: URL) async -> TimeInterval? {
            durationByPath[url.path]
        }
    }

    private func video(_ path: String, size: Int64 = 1_000_000) -> FileItem {
        .mock(url: URL(fileURLWithPath: path), size: size)
    }

    // MARK: - Grouping

    func testIdenticalFrameHashesGroup() async {
        let hashes: [UInt64] = [0b1111, 0b0011, 0b0101, 0b1110, 0b1001, 0b0110, 0b1010, 0b1100]
        let a = video("/Videos/a.mp4")
        let b = video("/Videos/copy/a.mp4")
        let detector = SimilarVideoDetector(
            hasher: StubHasher(hashesByPath: ["/Videos/a.mp4": hashes, "/Videos/copy/a.mp4": hashes])
        )
        let groups = await detector.detect(files: [a, b], controller: ScanController())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].category, .similarVideo)
        XCTAssertEqual(groups[0].files.count, 2)
        guard case .similarVideo(let ratio, let frames) = groups[0].categoryEvidence else {
            return XCTFail("Expected similarVideo evidence")
        }
        XCTAssertEqual(frames, 8)
        XCTAssertEqual(ratio, 0.7, accuracy: 0.0001)
    }

    func testDissimilarHashesDoNotGroup() async {
        let a = video("/Videos/a.mp4")
        let b = video("/Videos/b.mp4")
        let detector = SimilarVideoDetector(
            hasher: StubHasher(hashesByPath: [
                "/Videos/a.mp4": [0xFF00FF00FF00FF00, 0x0F0F0F0F0F0F0F0F, 0x1234567890ABCDEF, 0xDEADBEEFCAFE0001, 0x0, 0xF, 0xFF, 0xFFF],
                "/Videos/b.mp4": [0x00FF00FF00FF00FF, 0xF0F0F0F0F0F0F0F0, 0x0987654321FEDCBA, 0x1250000000000001, 0xFFFFFFFFFFFFFFFF, 0xF0, 0xFF0, 0xFFF0],
            ])
        )
        let groups = await detector.detect(files: [a, b], controller: ScanController())
        XCTAssertTrue(groups.isEmpty, "Unrelated clips must not group")
    }

    func testSizeMismatchPrefilterBlocksGrouping() async {
        let hashes: [UInt64] = Array(repeating: 0b1111, count: 8)
        let small = video("/Videos/small.mp4", size: 1_000_000)
        let huge = video("/Videos/huge.mp4", size: 50_000_000)
        let detector = SimilarVideoDetector(
            hasher: StubHasher(hashesByPath: [
                "/Videos/small.mp4": hashes, "/Videos/huge.mp4": hashes,
            ])
        )
        let groups = await detector.detect(files: [small, huge], controller: ScanController())
        XCTAssertTrue(groups.isEmpty, "20% size tolerance excludes a 50x size gap before frame matching")
    }

    func testDurationMismatchPrefilterBlocksGrouping() async {
        let hashes: [UInt64] = Array(repeating: 0b1111, count: 8)
        let short = video("/Videos/short.mp4")
        let long = video("/Videos/long.mp4")
        let detector = SimilarVideoDetector(
            hasher: StubHasher(
                hashesByPath: ["/Videos/short.mp4": hashes, "/Videos/long.mp4": hashes],
                durationByPath: ["/Videos/short.mp4": 10, "/Videos/long.mp4": 120]
            )
        )
        let groups = await detector.detect(files: [short, long], controller: ScanController())
        XCTAssertTrue(groups.isEmpty, "5% duration tolerance excludes a 12x length gap")
    }

    func testNonVideoExtensionsIgnored() async {
        let image = video("/Videos/photo.jpg")
        let detector = SimilarVideoDetector(hasher: StubHasher(hashesByPath: [:]))
        let groups = await detector.detect(files: [image], controller: ScanController())
        XCTAssertTrue(groups.isEmpty)
    }

    func testThreeWayClusterFormsSingleGroup() async {
        let base: [UInt64] = [0b1111, 0b0011, 0b0101, 0b1110, 0b1001, 0b0110, 0b1010, 0b1100]
        // Slight per-video frame variation that stays within hamming 10.
        func variant(_ salt: UInt64) -> [UInt64] { base.map { $0 ^ (salt & 0xF) } }
        let a = video("/Videos/a.mp4")
        let b = video("/Videos/b.mp4")
        let c = video("/Videos/c.mp4")
        let detector = SimilarVideoDetector(
            hasher: StubHasher(hashesByPath: [
                "/Videos/a.mp4": variant(0),
                "/Videos/b.mp4": variant(1),
                "/Videos/c.mp4": variant(2),
            ])
        )
        let groups = await detector.detect(files: [a, b, c], controller: ScanController())
        XCTAssertEqual(groups.count, 1, "Transitively similar videos cluster via union-find")
        XCTAssertEqual(groups[0].files.count, 3)
    }

    func testCancellationReturnsEarly() async {
        var hashes = [UInt64]()
        for index in 0..<8 { hashes.append(UInt64(index)) }
        let a = video("/Videos/a.mp4")
        let b = video("/Videos/b.mp4")
        let controller = ScanController()
        controller.cancel()
        let detector = SimilarVideoDetector(
            hasher: StubHasher(hashesByPath: ["/Videos/a.mp4": hashes, "/Videos/b.mp4": hashes])
        )
        let groups = await detector.detect(files: [a, b], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan produces no groups")
    }

    // MARK: - Shared dHash primitives

    func testPerceptualHashingHammingMatchesPopcount() {
        XCTAssertEqual(PerceptualHashing.hammingDistance(0, UInt64.max), 64)
        XCTAssertEqual(PerceptualHashing.hammingDistance(0b1010, 0b0101), 4)
        XCTAssertEqual(PerceptualHashing.hammingDistance(42, 42), 0)
    }

    // MARK: - AVAssetWriter integration (skipped on CI without media tools)

    func testRealVideoPairGroups() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urlA = dir.appendingPathComponent("a.mp4")
        let urlB = dir.appendingPathComponent("b.mp4")
        try await Self.writeSolidColorVideo(to: urlA, seconds: 1, gray: 0.5)
        try await Self.writeSolidColorVideo(to: urlB, seconds: 1, gray: 0.5)

        let a = FileItem.fromMetadata(urlA)!
        let b = FileItem.fromMetadata(urlB)!
        let detector = SimilarVideoDetector(hasher: AVAssetFrameHasher(), sampleCount: 4)
        let groups = await detector.detect(files: [a, b], controller: ScanController())
        XCTAssertEqual(groups.count, 1, "Two identical solid-color videos must group")
    }

    /// Renders a tiny H.264 clip of a solid gray frame.
    static func writeSolidColorVideo(to url: URL, seconds: Double, gray: Double) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        guard let buffer = pixelBuffer else { throw NSError(domain: "ksift.tests", code: 1) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let value = UInt8((gray * 255).rounded())
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            memset(base + row * stride, Int32(value), stride)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let fps = 10
        let frames = Int(seconds) * fps
        for frame in 0..<max(1, frames) {
            while !input.isReadyForMoreMediaData { usleep(10_000) }
            let time = CMTime(seconds: Double(frame) / Double(fps), preferredTimescale: 600)
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw NSError(domain: "ksift.tests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Video write failed: \(String(describing: writer.error))"])
        }
    }
}
