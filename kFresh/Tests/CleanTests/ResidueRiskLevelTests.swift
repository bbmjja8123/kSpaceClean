import XCTest
import AppKit
@testable import kFresh

/// Unit tests for the v1.x-B I-4 pieces:
/// - ``ResidueRiskLevel.classify(type:isSystemLevel:)`` mapping
/// - ``TrashMover/dryRun(app:residues:)`` producing a well-formed
///   ``DryRunReport``
/// - Shared preview path between dry-run and the real ``moveToTrash``
///   flow (the spec §2.2 "no divergent logic" invariant)
@MainActor
final class ResidueRiskLevelTests: XCTestCase {
    // MARK: - Classifier mapping

    func testCacheLikeResidueTypesClassifyAsRecommended() {
        for type in [ResidueType.caches, .httpStorage, .webKit, .log] {
            XCTAssertEqual(
                ResidueRiskLevel.classify(type: type, isSystemLevel: false),
                .recommended,
                "\(type) should be recommended (cache-like)"
            )
        }
    }

    func testLaunchOnBootResidueTypesClassifyAsDangerous() {
        for type in [ResidueType.launchAgent, .launchDaemon, .startupItem] {
            XCTAssertEqual(
                ResidueRiskLevel.classify(type: type, isSystemLevel: false),
                .dangerous,
                "\(type) should be dangerous (auto-runs on next login/boot)"
            )
        }
    }

    func testPreferencesAndCookiesClassifyAsCaution() {
        for type in [ResidueType.preferences, .cookie] {
            XCTAssertEqual(
                ResidueRiskLevel.classify(type: type, isSystemLevel: false),
                .caution,
                "\(type) should be caution"
            )
        }
    }

    func testAppDataClassifiesAsOptional() {
        for type in [ResidueType.appSupport, .container, .savedState,
                     .groupContainer, .plugin, .prefPane, .appleScript, .other] {
            XCTAssertEqual(
                ResidueRiskLevel.classify(type: type, isSystemLevel: false),
                .optional,
                "\(type) should be optional"
            )
        }
    }

    /// Spec §2.1: only 🟢 Recommended defaults to ON.
    func testDefaultSelectionMatchesSpec() {
        XCTAssertTrue(ResidueRiskLevel.recommended.defaultSelected)
        XCTAssertFalse(ResidueRiskLevel.optional.defaultSelected)
        XCTAssertFalse(ResidueRiskLevel.caution.defaultSelected)
        XCTAssertFalse(ResidueRiskLevel.dangerous.defaultSelected)
    }

    // MARK: - ResidueFile init derives riskLevel from type

    func testResidueFileInitDerivesRiskLevelWhenOmitted() {
        let residue = ResidueFile(
            url: URL(fileURLWithPath: "/tmp/cache"),
            type: .caches,
            sizeBytes: 100,
            confidence: 0.9
        )
        XCTAssertEqual(residue.riskLevel, .recommended)
    }

    func testResidueFileInitHonoursExplicitRiskLevel() {
        let residue = ResidueFile(
            url: URL(fileURLWithPath: "/tmp/cache"),
            type: .caches,
            sizeBytes: 100,
            confidence: 0.9,
            riskLevel: .dangerous
        )
        XCTAssertEqual(residue.riskLevel, .dangerous)
    }

    // MARK: - TrashMover.dryRun

    func testDryRunReturnsReportWithoutTouchingFileSystem() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil
        )
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/Library/Caches/com.example.sample"),
                        type: .caches, sizeBytes: 2048, confidence: 0.9),
            ResidueFile(url: URL(fileURLWithPath: "/Library/LaunchAgents/com.example.sample.plist"),
                        type: .launchAgent, sizeBytes: 512, confidence: 0.95),
        ]
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let report = mover.dryRun(app: app, residues: residues)

        XCTAssertEqual(report.appDisplayName, "Sample")
        XCTAssertEqual(report.appBundleID, "com.example.sample")
        XCTAssertEqual(report.appSizeBytes, 4096)
        // The shared preview helper filters by confidence > 0.5 — both
        // residues above the threshold, so both appear in the report.
        XCTAssertEqual(report.residueSelection.count, 2)
        XCTAssertEqual(report.totalFreedBytes, 4096 + 2048 + 512)
        XCTAssertTrue(report.hasDangerousResidue)
    }

    func testDryRunRespectsConfidenceFilter() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0
        )
        // Below the 0.5 confidence threshold: the shared preview helper
        // drops it, so the dry-run report does NOT promise to delete it.
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/Library/Stuff"),
                        type: .caches, sizeBytes: 9999, confidence: 0.4),
        ]
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let report = mover.dryRun(app: app, residues: residues)

        XCTAssertTrue(report.residueSelection.isEmpty,
                      "Residues below the confidence threshold must not appear in dry-run")
        XCTAssertFalse(report.hasDangerousResidue)
    }

    func testDryRunGroupsByRiskInSpecOrder() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0
        )
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/Library/LaunchAgents/x.plist"),
                        type: .launchAgent, sizeBytes: 100, confidence: 0.95),
            ResidueFile(url: URL(fileURLWithPath: "/Library/Caches/x"),
                        type: .caches, sizeBytes: 200, confidence: 0.95),
            ResidueFile(url: URL(fileURLWithPath: "/Library/Preferences/x.plist"),
                        type: .preferences, sizeBytes: 300, confidence: 0.95),
            ResidueFile(url: URL(fileURLWithPath: "/Library/Application Support/x"),
                        type: .appSupport, sizeBytes: 400, confidence: 0.95),
        ]
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let report = mover.dryRun(app: app, residues: residues)

        let levels = report.residuesByRisk.map(\.level)
        XCTAssertEqual(levels, [.recommended, .optional, .caution, .dangerous])
        let dangerousItems = report.residuesByRisk.first { $0.level == .dangerous }?.items
        XCTAssertEqual(dangerousItems?.count, 1)
        XCTAssertEqual(dangerousItems?.first?.type, .launchAgent)
    }
}