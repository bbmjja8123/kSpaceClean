import Foundation

/// Decides which residues should default to **ON** in
/// ``UninstallConfirmSheet`` when the sheet first opens.
///
/// Implements the Nektony-style "smart selector" called out in spec
/// §5.1 ("Apple top-tier gap closure — v1.x 可选"): an auto-recommendation
/// that flips the ⚪ Optional bucket to ON when the app hasn't been used
/// in a long time, because a clearly-abandoned app's Application Support
/// data is almost certainly junk to the user.
///
/// The rules are deliberately narrow:
///
/// | Risk | Default policy |
/// |---|---|
/// | 🟢 Recommended | always ON — cache-like files are safe to delete |
/// | ⚪ Optional | ON if `app.lastUsedDate` is older than ``staleThresholdDays`` **or** `nil` (never used); OFF otherwise |
/// | 🟠 Caution | always OFF — preferences / cookies are user intent |
/// | 🔴 Dangerous | always OFF — launch agents / keychain are policy boundaries |
///
/// The user can still toggle any row in the sheet — this function only
/// governs the initial selection. The Defaultable defaults from
/// ``ResidueRiskLevel/defaultSelected`` are preserved for callers that
/// don't want the staleness heuristic (e.g. tests, share / extension
/// surfaces that don't have an app context).
///
/// Internal (not public) because ``InstalledApp`` is internal — exposing
/// the selector would force the model to go public too.
enum ResidueSmartSelector {

    /// An optional residue is flipped to ON when the app has not been
    /// used in this many days (or has never been used — `nil`).
    /// 180 days ≈ 6 months, matching Nektony's "stale" cutoff.
    static let staleThresholdDays: Int = 180

    /// Returns the default selection state for `residue` in the context of
    /// `app`. Pure function — no I/O, no actor state.
    static func defaultSelection(
        residue: ResidueFile,
        app: InstalledApp
    ) -> Bool {
        switch residue.riskLevel {
        case .recommended:
            return true
        case .dangerous:
            return false
        case .caution:
            return false
        case .optional:
            return isOptionalStale(app: app)
        }
    }

    /// Convenience overload that operates on a homogeneous bucket — used
    /// by ``UninstallConfirmSheet`` to seed the selection set in one pass.
    static func defaultSelection(
        residues: [ResidueFile],
        app: InstalledApp
    ) -> Set<String> {
        Set(
            residues
                .filter { defaultSelection(residue: $0, app: app) }
                .map(\.id)
        )
    }

    /// True when the app has not been used in ``staleThresholdDays`` or
    /// has no `lastUsedDate` recorded (never launched since install).
    private static func isOptionalStale(app: InstalledApp) -> Bool {
        guard let lastUsed = app.lastUsedDate else {
            return true
        }
        let cutoff = Date().addingTimeInterval(-Double(staleThresholdDays) * 86_400)
        return lastUsed < cutoff
    }
}