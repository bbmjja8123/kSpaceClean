import XCTest
import AppKit
@testable import kFresh

/// Unit tests for the v1.x-D Nektony-style smart selector.
///
/// Covers the 4 risk levels × 3 app-usage scenarios (active / stale /
/// never-used) matrix per the spec §5.1 rules table.
final class ResidueSmartSelectorTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `ResidueFile` with the given risk level. Selector is
    /// irrelevant to the rules — the detector's confidence value flows
    /// through unchanged. Each call gets a unique URL because
    /// ``ResidueFile/id`` is `url.path` and a `Set<String>` would dedupe
    /// identical paths.
    private func residue(_ type: ResidueType, risk: ResidueRiskLevel, suffix: Int = 0) -> ResidueFile {
        let suffixPart = suffix == 0 ? "" : "-\(suffix)"
        return ResidueFile(
            url: URL(fileURLWithPath: "/tmp/\(type.rawValue)\(suffixPart).bin"),
            type: type,
            sizeBytes: 1024,
            confidence: 0.9,
            riskLevel: risk
        )
    }

    /// Build an `InstalledApp` with the given `lastUsedDate`. Use `nil` to
    /// represent "never used" (the key trigger for the smart selector's
    /// stale rule).
    private func app(lastUsedDate: Date?) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            displayName: "Sample",
            bundleID: "com.example.sample",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 4096,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: lastUsedDate
        )
    }

    /// Compute "X days ago" timestamps deterministically.
    private func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(-Double(days) * 86_400)
    }

    // MARK: - Per-risk defaults

    /// 🟢 Recommended: always ON, regardless of app usage.
    func testRecommendedIsAlwaysOn() {
        for date in [nil, daysAgo(1), daysAgo(365), daysAgo(10_000)] as [Date?] {
            let r = residue(.caches, risk: .recommended)
            let a = app(lastUsedDate: date)
            XCTAssertTrue(
                ResidueSmartSelector.defaultSelection(residue: r, app: a),
                "Recommended must be ON for lastUsedDate=\(String(describing: date))"
            )
        }
    }

    /// 🟠 Caution: always OFF, regardless of app usage.
    func testCautionIsAlwaysOff() {
        for date in [nil, daysAgo(1), daysAgo(365), daysAgo(10_000)] as [Date?] {
            let r = residue(.preferences, risk: .caution)
            let a = app(lastUsedDate: date)
            XCTAssertFalse(
                ResidueSmartSelector.defaultSelection(residue: r, app: a),
                "Caution must be OFF for lastUsedDate=\(String(describing: date))"
            )
        }
    }

    /// 🔴 Dangerous: always OFF, regardless of app usage.
    func testDangerousIsAlwaysOff() {
        for date in [nil, daysAgo(1), daysAgo(365), daysAgo(10_000)] as [Date?] {
            let r = residue(.launchAgent, risk: .dangerous)
            let a = app(lastUsedDate: date)
            XCTAssertFalse(
                ResidueSmartSelector.defaultSelection(residue: r, app: a),
                "Dangerous must be OFF for lastUsedDate=\(String(describing: date))"
            )
        }
    }

    // MARK: - Optional bucket — the new Nektony rule

    /// ⚪ Optional, active app (lastUsedDate recent): OFF.
    /// The user is actively using the app — preserving app data is the
    /// safe default.
    func testOptionalIsOffForActiveApp() {
        let r = residue(.appSupport, risk: .optional)
        let a = app(lastUsedDate: daysAgo(1))
        XCTAssertFalse(ResidueSmartSelector.defaultSelection(residue: r, app: a))
    }

    /// ⚪ Optional, app just below the stale threshold (179 days):
    /// still OFF (boundary is inclusive of values strictly less than
    /// the cutoff).
    func testOptionalIsOffJustBelowStaleThreshold() {
        let r = residue(.appSupport, risk: .optional)
        let a = app(lastUsedDate: daysAgo(179))
        XCTAssertFalse(ResidueSmartSelector.defaultSelection(residue: r, app: a))
    }

    /// ⚪ Optional, app at the stale threshold: ON.
    /// The threshold is `lastUsedDate < cutoff`; cutoff = `now - 180d`.
    /// 181 days ago < 180 days ago, so this row is stale.
    func testOptionalIsOnAtStaleThreshold() {
        let r = residue(.appSupport, risk: .optional)
        let a = app(lastUsedDate: daysAgo(181))
        XCTAssertTrue(ResidueSmartSelector.defaultSelection(residue: r, app: a))
    }

    /// ⚪ Optional, app never used (lastUsedDate nil): ON.
    /// Matches Nektony's "clearly abandoned" heuristic.
    func testOptionalIsOnForNeverUsedApp() {
        let r = residue(.appSupport, risk: .optional)
        let a = app(lastUsedDate: nil)
        XCTAssertTrue(ResidueSmartSelector.defaultSelection(residue: r, app: a))
    }

    /// ⚪ Optional, app ancient (1000 days): ON.
    func testOptionalIsOnForAncientApp() {
        let r = residue(.appSupport, risk: .optional)
        let a = app(lastUsedDate: daysAgo(1_000))
        XCTAssertTrue(ResidueSmartSelector.defaultSelection(residue: r, app: a))
    }

    // MARK: - Bulk API

    /// The bulk overload must return a Set<String> of residue IDs that
    /// honours the same per-residue rules — verifying the convenience
    /// overload doesn't drift from the per-residue source of truth.
    func testBulkSelectionMatchesPerResidueRules() {
        let residues = [
            residue(.caches, risk: .recommended),
            residue(.preferences, risk: .caution),
            residue(.appSupport, risk: .optional, suffix: 1),
            residue(.launchAgent, risk: .dangerous),
            residue(.httpStorage, risk: .recommended),
            residue(.appSupport, risk: .optional, suffix: 2),
        ]
        let a = app(lastUsedDate: daysAgo(365)) // stale
        let ids = ResidueSmartSelector.defaultSelection(residues: residues, app: a)

        // Recommended × 2 + Optional × 2 (stale) → 4 selected.
        XCTAssertEqual(ids.count, 4)
        for r in residues where r.riskLevel == .recommended || r.riskLevel == .optional {
            XCTAssertTrue(ids.contains(r.id), "missing \(r.id)")
        }
        for r in residues where r.riskLevel == .caution || r.riskLevel == .dangerous {
            XCTAssertFalse(ids.contains(r.id), "should not include \(r.id)")
        }
    }

    func testBulkSelectionForActiveAppIsRecommendedOnly() {
        let residues = [
            residue(.caches, risk: .recommended),
            residue(.appSupport, risk: .optional, suffix: 1),
            residue(.appSupport, risk: .optional, suffix: 2),
        ]
        let a = app(lastUsedDate: daysAgo(1)) // active
        let ids = ResidueSmartSelector.defaultSelection(residues: residues, app: a)
        XCTAssertEqual(ids.count, 1, "Active app: only Recommended selected")
    }

    // MARK: - Threshold constant

    /// The 180-day threshold is part of the public-spec contract — pin it
    /// so a future "let's bump it to 90 days" change is a deliberate
    /// decision, not a silent regression.
    func testStaleThresholdMatchesSpec() {
        XCTAssertEqual(ResidueSmartSelector.staleThresholdDays, 180)
    }
}