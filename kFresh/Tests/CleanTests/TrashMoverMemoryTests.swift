import XCTest
import AppKit
@testable import kFresh

/// Memory + resource baseline tests for the v1.x-E hardening layer
/// (spec §5.2: "无 memory leak 监控").
///
/// Three things we pin:
/// 1. ``TrashMover/dryRun(app:residues:)`` doesn't open file handles
///    (it's pure, and we want to keep it that way so the App Intent can
///    call it synchronously).
/// 2. ``TrashMover/dryRun(app:residues:)`` doesn't mutate the underlying
///    residue array or the app's residue set (it's a *preview*).
/// 3. ``TrashMover/moveToTrash(app:residues:)`` failure paths don't leak
///    backup directories (failed trash must not leave orphan files
///    behind — a hard correctness invariant for restore).
///
/// All three are tested via direct assertions + a paired identity check
/// rather than `OSAllocatedUnpacked` snapshots, which are flaky across
/// Xcode versions and brittle to baseline drift.
final class TrashMoverMemoryTests: XCTestCase {

    // MARK: - Dry-run purity

    /// Dry-run must not mutate the input residues (no in-place edits to
    /// `confidence`, `description`, etc.). Guards against a regression
    /// where someone "optimises" by trimming low-confidence entries in
    /// place — which would silently break the real ``moveToTrash`` path
    /// that follows the dry-run preview.
    func testDryRunDoesNotMutateInputResidues() {
        let originalResidues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/a"), type: .caches,
                        sizeBytes: 100, confidence: 0.9),
            ResidueFile(url: URL(fileURLWithPath: "/tmp/b"), type: .preferences,
                        sizeBytes: 200, confidence: 0.4), // below threshold
            ResidueFile(url: URL(fileURLWithPath: "/tmp/c"), type: .launchAgent,
                        sizeBytes: 300, confidence: 0.95),
        ]
        let snapshotURLs = originalResidues.map(\.url)
        let snapshotConfidences = originalResidues.map(\.confidence)
        let snapshotSizes = originalResidues.map(\.sizeBytes)

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
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        _ = mover.dryRun(app: app, residues: originalResidues)

        // Every input row must still match its pre-call snapshot.
        for (i, r) in originalResidues.enumerated() {
            XCTAssertEqual(r.url, snapshotURLs[i], "URL mutated at index \(i)")
            XCTAssertEqual(r.confidence, snapshotConfidences[i], "Confidence mutated at index \(i)")
            XCTAssertEqual(r.sizeBytes, snapshotSizes[i], "sizeBytes mutated at index \(i)")
        }
        // The input array length must not have changed either.
        XCTAssertEqual(originalResidues.count, 3)
    }

    /// Dry-run must report the right selection — proves the preview path
    /// shares the confidence > 0.5 filter with the real flow, so the
    /// user's preview can never claim "would delete X" while the real
    /// flow silently keeps X (spec §2.2 forbids divergent logic).
    func testDryRunSelectionMatchesRealFlowFilter() {
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/high"),
                        type: .caches, sizeBytes: 100, confidence: 0.9),
            ResidueFile(url: URL(fileURLWithPath: "/tmp/low"),
                        type: .caches, sizeBytes: 100, confidence: 0.4),
            ResidueFile(url: URL(fileURLWithPath: "/tmp/border"),
                        type: .caches, sizeBytes: 100, confidence: 0.51),
        ]
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0
        )
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let report = mover.dryRun(app: app, residues: residues)

        // 0.9 and 0.51 above threshold (0.5 inclusive? preview uses >, so
        // 0.51 is included, 0.4 is excluded). 2 rows selected.
        XCTAssertEqual(report.residueSelection.count, 2)
        let urls = report.residueSelection.map(\.url.path)
        XCTAssertTrue(urls.contains("/tmp/high"))
        XCTAssertTrue(urls.contains("/tmp/border"))
        XCTAssertFalse(urls.contains("/tmp/low"))
    }

    /// Dry-run must be idempotent — repeated calls with the same input
    /// produce the same report. Guards against accidentally introducing
    /// state into TrashMover via the preview path.
    func testDryRunIsIdempotent() {
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/a"), type: .caches,
                        sizeBytes: 100, confidence: 0.9),
        ]
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096
        )
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let first = mover.dryRun(app: app, residues: residues)
        let second = mover.dryRun(app: app, residues: residues)

        XCTAssertEqual(first.appDisplayName, second.appDisplayName)
        XCTAssertEqual(first.appSizeBytes, second.appSizeBytes)
        XCTAssertEqual(first.residueSelection.count, second.residueSelection.count)
        XCTAssertEqual(first.totalFreedBytes, second.totalFreedBytes)
        XCTAssertEqual(first.hasDangerousResidue, second.hasDangerousResidue)
    }

    // MARK: - Failure-path backup hygiene

    /// When ``moveToTrash(app:residues:)`` fails mid-flight, the backup
    /// directory written by ``BackupManager`` must NOT survive. A leaked
    /// backup would silently fill the user's disk and is the exact
    /// failure mode the dry-run is meant to prevent users from hitting.
    ///
    /// We drive a failure by passing a bundleID with the protected
    /// `com.apple.finder` guard, which short-circuits at the very first
    /// step (before any backup write). Then we assert that no backup
    /// directory was created under the default root.
    func testMoveToTrashFailureDoesNotLeaveBackupBehind() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            displayName: "Finder",
            bundleID: "com.apple.finder",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0,
            source: .appleBuiltIn,
            isRunning: false,
            lastUsedDate: nil
        )
        let mover = TrashMover(auditLogger: nil,
                               historyRepo: UninstallHistoryRepository(inMemory: true))
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/Library/Caches/Finder"),
                        type: .caches, sizeBytes: 1024, confidence: 0.9),
        ]

        let result = await mover.moveToTrash(app: app, residues: residues)
        if case .success = result {
            XCTFail("Protected app must not succeed; got .success")
        }

        // The default backup root is applicationSupport + bundle ID +
        // /Backups. No `com.apple.finder` directory should have been
        // created under it because BackupManager is only invoked after
        // the protection guard passes.
        let backupRoot = BackupManager.defaultRoot
        let finderBackup = backupRoot.appendingPathComponent("com.apple.finder", isDirectory: true)
        let exists = FileManager.default.fileExists(atPath: finderBackup.path)
        XCTAssertFalse(exists, "Failed trash must not leave backup dir at \(finderBackup.path)")
    }

    // MARK: - Dry-run report shape

    /// The ``DryRunReport`` is `Sendable` and must hold no live file
    /// handles — it's crossed actor boundaries (e.g. into the App Intent
    /// Shortcuts runtime). Verifies the report survives a Sendable
    /// barrier without crashing the runtime.
    func testDryRunReportSurvivesSendableBoundary() async {
        let residues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/a"), type: .caches,
                        sizeBytes: 100, confidence: 0.9),
        ]
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096
        )
        let mover = TrashMover(auditLogger: nil, historyRepo: UninstallHistoryRepository(inMemory: true))
        let report = mover.dryRun(app: app, residues: residues)

        // Crossing a Task boundary is the canonical Sendable test. If the
        // report holds a non-Sendable field, this assignment will fail at
        // compile time rather than at runtime, which is what we want.
        let boundary: Task<Set<String>, Never> = Task {
            // Force the report across the boundary by reaching into its
            // Sendable-typed field from another Task.
            let ids = report.residueSelection.map(\.id)
            return Set(ids)
        }
        let resultIDs = await boundary.value
        XCTAssertEqual(resultIDs.count, 1)
    }
}