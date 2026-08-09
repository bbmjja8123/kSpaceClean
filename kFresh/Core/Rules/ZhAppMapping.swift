import Foundation

/// One entry in `zh_app_mappings.json` — the curated bundle ID mapping for
/// Mac apps widely installed in mainland China but absent from
/// `cask_rules.json` (which falls back to token-only entries when no
/// extractable signal exists).
///
/// The schema mirrors the v1.x-C spec §4.1 field-for-field so the JSON
/// round-trip is lossless. `sources` is an array (not a single string) so
/// future sources (`manual` / `cask-cn` / `as-cn-scrape`) can be added
/// without breaking decoders — see spec §4.6.3 invariant 6
/// ("schema 向后兼容：新增字段必须 optional").
public struct ZhAppMapping: Codable, Sendable, Hashable {
    /// User-facing display name (e.g. "QQ", "微信").
    public let displayName: String
    /// macOS bundle identifier (e.g. "com.tencent.qq").
    /// Verified by `defaults read <path>/Contents/Info.plist CFBundleIdentifier`
    /// per spec §1.3 quality gate.
    public let bundleID: String
    /// Optional English / canonical app name. Distinct from `displayName`
    /// because some apps have a Chinese display name and a different
    /// English name (e.g. displayName "钉钉" / appName "DingTalk").
    public let appName: String?
    /// When this mapping was last verified. ISO-8601 string in the JSON
    /// (`2026-08-08T00:00:00Z`); decoded to `Date` for ordering / staleness
    /// checks at the runtime layer.
    public let verifiedAt: Date
    /// Who verified this entry. One of `"manual"` / `"cask-cn"` /
    /// `"as-cn-scrape"`. Spec §4.6.3 invariant 1: `"manual"` entries must
    /// never be overwritten by automated sources.
    public let verifiedBy: String
    /// Every source that contributed to this entry. Decoded as `[String]`
    /// so the schema can absorb new sources without breaking change.
    /// Spec §1.3 quality gate: each entry must have ≥ 2 independent sources.
    public let sources: [String]
    /// Set to `true` to mark the entry as no longer trustworthy (app
    /// renamed, bundle ID changed, app discontinued). Runtime lookups
    /// skip deprecated entries.
    public let deprecated: Bool

    public init(displayName: String,
                bundleID: String,
                appName: String? = nil,
                verifiedAt: Date,
                verifiedBy: String,
                sources: [String],
                deprecated: Bool = false) {
        self.displayName = displayName
        self.bundleID = bundleID
        self.appName = appName
        self.verifiedAt = verifiedAt
        self.verifiedBy = verifiedBy
        self.sources = sources
        self.deprecated = deprecated
    }
}

/// Top-level shape of `zh_app_mappings.json`. Wraps the app array with
/// metadata fields (`version`, `generatedAt`, `source`) so the file is
/// self-describing and a CI freshness check can assert recency without
/// reading every entry.
public struct ZhAppMappingFile: Codable, Sendable {
    /// Schema version. Bump on any breaking field change; additive
    /// changes keep the same version. Spec §4.1.
    public let version: Int
    /// When this file was generated (ISO-8601 in JSON).
    public let generatedAt: Date
    /// Free-text origin label (e.g. `"manual + cask-cn + as-cn-scrape"`).
    /// Used by tooling, not by lookups.
    public let source: String
    /// The mapping entries. The `key` field is the bundle ID for fast
    /// lookup; the array order is not significant.
    public let apps: [ZhAppMapping]

    public init(version: Int,
                generatedAt: Date,
                source: String,
                apps: [ZhAppMapping]) {
        self.version = version
        self.generatedAt = generatedAt
        self.source = source
        self.apps = apps
    }
}