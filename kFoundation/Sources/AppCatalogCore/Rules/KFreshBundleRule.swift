import Foundation

/// A heuristic rule that describes how to clean up a known application's residue.
///
/// Rules are produced from three sources (priority order, high to low):
/// 1. `ManualOverrides.json` (maintained for 2000+ Chinese App bundle IDs; v1.1+)
/// 2. `user_contributed_rules.json` (App Group, accumulated from real scans; v1.0+)
/// 3. Homebrew Cask `zap` stanzas (committed `cask_rules.json`; v1.0 Wave 0)
///
/// Consumed by `ResidueDetector` (Task 3) and the future `AppCatalogService` enrichment.
public struct KFreshBundleRule: Codable, Sendable, Hashable {
    /// Reverse-DNS bundle identifier (e.g. `com.microsoft.VSCode`).
    public let bundleID: String

    /// Human-readable application name (e.g. `Visual Studio Code`).
    public let appName: String

    /// User-level residue paths under `~/Library/...`.
    /// Tildes are preserved so callers can expand them at lookup time.
    public let residuePaths: [String]

    /// System-level paths under `/Library/...` or `/private/var/...`.
    public let systemLevelPaths: [String]

    /// Raw Homebrew Cask `zap` stanzas for transparency and future re-derivation.
    public let zapStanzas: [String]

    /// Confidence score in the range `0.0...1.0`.
    public let confidence: Double

    /// Provenance tag — `"homebrew-cask"`, `"user-contributed"`, or `"manual"`.
    public let source: String

    /// Default initializer.
    /// - Parameters:
    ///   - bundleID: Reverse-DNS bundle identifier.
    ///   - appName: Human-readable application name.
    ///   - residuePaths: User-level residue paths (`~/Library/...`); tildes preserved.
    ///   - systemLevelPaths: System-level paths (`/Library/...`, `/private/var/...`).
    ///   - zapStanzas: Raw Homebrew Cask `zap` stanzas for auditing.
    ///   - confidence: Confidence in `0.0...1.0`; defaults to `0.85` for Homebrew Cask.
    ///   - source: Provenance tag; defaults to `"homebrew-cask"`.
    public init(
        bundleID: String,
        appName: String,
        residuePaths: [String] = [],
        systemLevelPaths: [String] = [],
        zapStanzas: [String] = [],
        confidence: Double = 0.85,
        source: String = "homebrew-cask"
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.residuePaths = residuePaths
        self.systemLevelPaths = systemLevelPaths
        self.zapStanzas = zapStanzas
        self.confidence = confidence
        self.source = source
    }
}