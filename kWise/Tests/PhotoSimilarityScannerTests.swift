// kWise/Tests/PhotoSimilarityScannerTests.swift
//
// v2.3 Phase 3 — 相似照片引擎：scope-honest 候选目录、取消、preset 映射、
// 组映射。纯逻辑测试（不依赖真实照片库）。
import XCTest
import DetectionCore
import PowerScope
@testable import kWise

final class PhotoSimilarityScannerTests: XCTestCase {

    /// containerOnly scope: candidate directories must NOT include home
    /// subdirectories (honest degradation — the UI shows a grant CTA).
    func testContainerOnlyCandidatesAreEmpty() {
        let capability = ScopeCapability(
            level: .containerOnly, grantedRoot: nil, readablePublicDirs: []
        )
        XCTAssertTrue(PhotoSimilarityScanner.candidateDirectories(capability: capability).isEmpty)
    }

    /// homeGranted scope: the four picture directories are candidates.
    func testHomeGrantedCandidatesIncludePictureDirs() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let capability = ScopeCapability(
            level: .homeGranted, grantedRoot: home, readablePublicDirs: []
        )
        let dirs = PhotoSimilarityScanner.candidateDirectories(capability: capability)
        XCTAssertTrue(dirs.contains { $0.path.hasSuffix("Screenshots") })
        XCTAssertTrue(dirs.contains { $0.path.hasSuffix("Downloads") })
    }

    func testCancelYieldsEmptyResult() async {
        let scanner = PhotoSimilarityScanner()
        let controller = DetectionCore.ScanController()
        controller.cancel()

        let config = PhotoSimilarityConfig(
            directories: [FileManager.default.temporaryDirectory],
            preset: .normal
        )
        let groups = await scanner.scan(config: config, controller: controller) { _, _ in }
        XCTAssertTrue(groups.isEmpty, "A cancelled scan must not fabricate groups")
    }

    func testEmptyDirectoriesYieldNothing() async {
        let scanner = PhotoSimilarityScanner()
        let controller = DetectionCore.ScanController()
        let groups = await scanner.scan(
            config: PhotoSimilarityConfig(directories: [], preset: .normal),
            controller: controller
        ) { _, _ in }
        XCTAssertTrue(groups.isEmpty)
    }

    /// Duplicate identical images in a temp dir → grouped by the perceptual
    /// pipeline (end-to-end smoke on real files).
    func testIdenticalImagesGroupTogether() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photosim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 3 visually identical PNGs (solid color).
        //
        // The fixture must opt out of `minFileSize` (default 128 KB — see
        // `PhotoSimilarityConfig`): a solid 64×64 PNG is a few hundred bytes
        // and would be filtered out during enumeration, so the scan saw zero
        // candidates and returned no groups. Padding the images with noise to
        // clear the threshold would change their perceptual hashes, so the
        // threshold is lowered here instead — this test exercises grouping,
        // not the size cutoff.
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("fixture image encoding failed")
        }
        for i in 0..<3 {
            try png.write(to: dir.appendingPathComponent("shot-\(i).png"))
        }

        let scanner = PhotoSimilarityScanner()
        let controller = DetectionCore.ScanController()
        var config = PhotoSimilarityConfig(directories: [dir], preset: .strict)
        config.minFileSize = 1
        let groups = await scanner.scan(config: config, controller: controller) { _, _ in }

        XCTAssertEqual(groups.count, 1, "3 identical images must form one group")
        XCTAssertEqual(groups.first?.files.count, 3)
        let mapped = groups.first.map { ToolboxGroup.map($0, strategy: .keepNewest, scanRoots: [dir]) }
        XCTAssertTrue(mapped?.evidenceSummary.contains("视觉相似") == true)
    }
}

import AppKit
