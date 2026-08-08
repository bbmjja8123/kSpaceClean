// kWise/Features/SmartScan/Models/ScanThreshold.swift
import Foundation

/// Path-based risk classifier that maps a file path to one of the four
/// `RiskLevel` tiers defined by the v3 UX spec (§1.2 / CLAUDE.md §8.5).
///
/// The threshold table is derived from two sources:
///
/// 1. **Lemon `garbage1.xml`** — Tencent's decade-old macOS cleaner keeps a
///    per-app `recommend` flag on every garbage entry. We project that
///    boolean onto the four-tier scale (recommended → recommended, everything
///    else → optional unless explicitly dangerous).
/// 2. **CleanMyMac X 5-level downscale** — CleanMyMac uses five tiers
///    (Safe / Useful / Cautious / Sensitive / Critical). We collapse that
///    onto four tiers by merging "Critical" and "Sensitive" into
///    `.dangerous` so the cascade-checkbox algorithm can drive a binary
///    default-selection policy.
///
/// The classifier is intentionally **conservative on Dangerous** — every
/// Dangerous rule corresponds to a path component that, if deleted, would
/// break macOS, an app, or the user's data (Keychain, Time Machine backup,
/// sandbox Container, LaunchAgent, system plist, Photos Library). When in
/// doubt, the classifier returns `.optional` rather than guessing, because
/// `.recommended` over-selects and `.caution`/`.dangerous` would block
/// legitimate cleanup.
///
/// `RiskClassifier` is a stateless value type; it is `Sendable` so it can be
/// safely shared across actor boundaries (the scan engine runs on a
/// background actor and the UI reads results on `@MainActor`).
public struct RiskClassifier: Sendable {
    /// Initialize a classifier.
    ///
    /// The type has no stored state today; the initializer exists so future
    /// versions can accept a custom rule table (e.g. user-defined Dangerous
    /// paths) without breaking the public API.
    public init() {}

    /// Classify a file path into one of the four `RiskLevel` tiers.
    ///
    /// - Parameter path: Absolute filesystem path. Tilde-prefixed paths
    ///   (`~/Library/...`) are expanded before matching so users can hand
    ///   the classifier either form.
    /// - Returns: The matched `RiskLevel`. Order of evaluation is
    ///   Dangerous → Caution → Optional → Recommended, so the most
    ///   protective rule wins on ambiguous paths (a Cookies file under
    ///   `/Library/Caches` would still be classified as `.caution`).
    ///
    /// The classifier matches on **substring containment** rather than
    /// `URL` components because cleanup targets come from many sources
    /// (`String` from the FileWalker, `URL` from `FileManager.enumerator`,
    /// and Apple Event file paths from Finder Sync) and we want a single
    /// uniform rule set.
    public func classify(path: String) -> RiskLevel {
        let normalized = (path as NSString).expandingTildeInPath

        // MARK: - Dangerous (highest priority)
        // Deleting any of these paths would break macOS, an app, or the
        // user's data. The double-confirm + DELETE-typed dialog guards
        // the actual cleanup action; this classifier is the first gate.
        if normalized.contains("/Keychains/") { return .dangerous }
        if normalized.contains("/Backups.backupdb/") { return .dangerous }
        if normalized.contains("/MobileBackups/") { return .dangerous }
        if normalized.contains("/Containers/") { return .dangerous }
        if normalized.contains("/Saved Application State/") { return .dangerous }
        if normalized.contains("/LaunchAgents/") || normalized.contains("/LaunchDaemons/") { return .dangerous }
        if normalized.hasPrefix("/Library/Preferences/") { return .dangerous }
        if normalized.contains("/Pictures/Photos Library") { return .dangerous }

        // MARK: - Caution
        // Deleting causes minor recovery cost (re-login, rebuild cache,
        // re-fetch messages). Off by default per §8.6 of CLAUDE.md.
        if normalized.contains("/Cookies/") { return .caution }
        if normalized.contains("/Application Support/") && normalized.hasSuffix(".sqlite") { return .caution }
        if normalized.contains("/Preferences/") { return .caution }
        if normalized.contains("/Mail/") && normalized.contains("Attachments") { return .caution }
        if normalized.contains("/Mail/V") { return .caution }  // Mail envelope index database

        // MARK: - Optional
        // Useful history the user may want to keep. Off by default.
        if normalized.contains("/Safari/History.db") { return .optional }
        if normalized.contains("/Chrome/History") { return .optional }
        if normalized.contains("/Firefox/places.sqlite") { return .optional }
        if normalized.hasSuffix(".log.gz") || normalized.hasSuffix(".crash") || normalized.hasSuffix(".ips") { return .optional }
        if normalized.contains("/DiagnosticReports/") { return .optional }

        // MARK: - Recommended (default-clean, regenerated automatically)
        if normalized.contains("/Caches/") { return .recommended }
        if normalized.contains("/Logs/") { return .recommended }
        if normalized.hasPrefix("/tmp/") || normalized.hasPrefix("/private/tmp/") { return .recommended }
        if normalized.contains("/Quick Look/") { return .recommended }
        if normalized.hasSuffix(".tmp") { return .recommended }

        // Unknown path → conservative Optional (off by default). This is
        // safer than falling through to `.recommended`, which would
        // auto-check files the user has never seen.
        return .optional
    }
}