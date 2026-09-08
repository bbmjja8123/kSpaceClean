import Foundation

/// Actor that loads `ZhAppMapping` records from the bundled
/// `zh_app_mappings.json` and exposes concurrent lookup APIs.
///
/// Mirrors `BundleRuleStore`'s shape (read-only after init, actor-isolated
/// for thread safety, supports bundled + injected data) so the residue
/// detection pipeline can fall back to the curated Chinese-mapping list
/// when the main `cask_rules.json` returns a token fallback (no extractable
/// bundle ID).
///
/// Spec §4.6.3 invariant 7 ("`zh_app_mappings.json` 缺失或损坏时，
/// `ResidueScanner` 必须优雅回落到现有 cask token 路径，不阻塞卸载"):
/// `loadFromBundledJSON` returns `nil` (not throws) when the resource is
/// missing or malformed, so callers can treat the file as a best-effort
/// overlay and degrade to the existing token path.
public actor MappingStore {
    /// Mappings keyed by exact bundle ID. Last write wins on collisions.
    private var mappingsByBundleID: [String: ZhAppMapping]
    /// Mappings grouped by lowercased display name for `fuzzyMatch` lookups.
    /// Decoupled from the bundle-ID index so a user typo in the bundle ID
    /// can still surface a match by app name.
    private var mappingsByLowercasedName: [String: [ZhAppMapping]]

    /// Load mappings from a JSON file on disk.
    /// - Parameter jsonURL: A file URL pointing at the mapping JSON.
    /// - Throws: `DecodingError` if the file is malformed; `CocoaError`
    ///   if unreadable.
    public init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        try self.init(jsonData: data)
    }

    /// Load mappings from in-memory JSON data. Used by tests that want to
    /// inject curated mappings without writing to disk, and by
    /// `loadFromBundledJSON` to decode the resource bytes.
    /// - Parameter jsonData: UTF-8 JSON bytes.
    /// - Throws: `DecodingError` if `jsonData` is malformed.
    public init(jsonData: Data) throws {
        self.mappingsByBundleID = [:]
        self.mappingsByLowercasedName = [:]
        let (byID, byName) = try Self.build(jsonData: jsonData)
        self.mappingsByBundleID = byID
        self.mappingsByLowercasedName = byName
    }

    /// Shared decode-and-index implementation. Mirrors
    /// `BundleRuleStore.build` so the two stores stay symmetric.
    ///
    /// Uses `.iso8601` date decoding because the JSON spec writes
    /// `verifiedAt` / `generatedAt` as ISO-8601 strings (e.g.
    /// `"2026-08-08T00:00:00Z"`), not the default
    /// `secondsSince1970` that `JSONDecoder` expects.
    private static func build(jsonData data: Data) throws -> ([String: ZhAppMapping], [String: [ZhAppMapping]]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ZhAppMappingFile.self, from: data)
        var byID: [String: ZhAppMapping] = [:]
        var byName: [String: [ZhAppMapping]] = [:]
        for mapping in file.apps where !mapping.deprecated {
            // Skip duplicated bundle IDs by keeping the first occurrence —
            // spec §4.6.3 invariant 1 ("人工优先") is enforced upstream
            // by the data generation pipeline, so a duplicate here means
            // the pipeline regressed and we should not silently overwrite.
            if byID[mapping.bundleID] == nil {
                byID[mapping.bundleID] = mapping
            }
            byName[mapping.displayName.lowercased(), default: []].append(mapping)
        }
        return (byID, byName)
    }

    /// Load mappings from a JSON file in the main bundle's `Resources/`
    /// directory. Returns `nil` when the resource is missing or
    /// malformed — callers treat this as a benign miss and fall back to
    /// the existing cask token lookup path (spec §4.6.3 invariant 7).
    /// - Parameter resourceName: Bundle resource filename (e.g.
    ///   `"zh_app_mappings"`); Xcode appends `.json` automatically.
    /// - Parameter bundle: Bundle to look in; defaults to `.main`.
    public static func loadFromBundledJSON(
        named resourceName: String = "zh_app_mappings",
        in bundle: Bundle = .main
    ) -> MappingStore? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            return nil
        }
        do {
            return try MappingStore(jsonURL: url)
        } catch {
            print("MappingStore.loadFromBundledJSON: failed to decode \(url.path): \(error)")
            return nil
        }
    }

    /// Look up an exact bundle ID. Returns `nil` when not found or when
    /// the matched entry is marked `deprecated`.
    public func lookup(bundleID: String) -> ZhAppMapping? {
        mappingsByBundleID[bundleID]
    }

    /// Return every non-deprecated mapping whose lowercased display name
    /// contains `name` as a substring. Multiple matches are returned in
    /// insertion order (Chinese apps often share short display names —
    /// "WPS" / "QQ" / "微信" — so the caller must disambiguate).
    public func fuzzyMatch(name: String) -> [ZhAppMapping] {
        let needle = name.lowercased()
        var results: [ZhAppMapping] = []
        for (key, value) in mappingsByLowercasedName where key.contains(needle) {
            results.append(contentsOf: value)
        }
        return results
    }

    /// Snapshot of every loaded (non-deprecated) mapping.
    public func allMappings() -> [ZhAppMapping] {
        Array(mappingsByBundleID.values)
    }

    /// Total number of loaded (non-deprecated) mappings.
    public var count: Int { mappingsByBundleID.count }
}