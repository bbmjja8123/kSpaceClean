import Foundation

/// Actor that loads `KFreshBundleRule` records from a JSON file on disk and
/// exposes concurrent lookup APIs.
///
/// Thread-safety is guaranteed by the actor model: all public methods may be
/// awaited from any task. The store is read-only after `init`; mutation is
/// expected to go through user-contributed rules in a future task.
public actor BundleRuleStore {
    /// Rules keyed by exact bundle ID. Last write wins on collisions.
    private var rulesByBundleID: [String: KFreshBundleRule]
    /// Rules grouped by lowercased app name for `fuzzyMatch` lookups.
    private var rulesByLowercasedName: [String: [KFreshBundleRule]]

    /// Load rules from a JSON file containing an array of `KFreshBundleRule`.
    /// - Parameter jsonURL: A file URL pointing at the rules JSON.
    /// - Throws: `DecodingError` if the file is malformed; `CocoaError` if unreadable.
    public init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        try self.init(jsonData: data)
    }

    /// Load rules from in-memory JSON data containing an array of
    /// `KFreshBundleRule`. Used by tests that want to inject curated
    /// rules without writing to disk, and by `loadFromBundledJSON` to
    /// decode the resource bytes.
    /// - Parameter jsonData: UTF-8 JSON bytes.
    /// - Throws: `DecodingError` if `jsonData` is malformed.
    public init(jsonData: Data) throws {
        // Initialize storage first so the actor's stored properties are
        // initialized before `Self.build` assigns into them. Actor
        // initializers in Swift cannot delegate to other initializers on
        // `self`, so we use a `static` builder rather than delegating.
        self.rulesByBundleID = [:]
        self.rulesByLowercasedName = [:]
        let (byID, byName) = try Self.build(jsonData: jsonData)
        self.rulesByBundleID = byID
        self.rulesByLowercasedName = byName
    }

    /// Shared decode-and-index implementation. Returns two dictionaries
    /// that the caller (the actor's designated initializer) assigns into
    /// its isolated storage. Actor initializers in Swift cannot delegate
    /// to other initializers on `self`, and a `static` function cannot
    /// mutate the actor's isolated properties directly, so the shared
    /// logic lives in a pure builder that returns the built dicts.
    /// - Parameter data: UTF-8 JSON bytes.
    /// - Returns: Tuple of `(rulesByBundleID, rulesByLowercasedName)`.
    private static func build(jsonData data: Data) throws -> ([String: KFreshBundleRule], [String: [KFreshBundleRule]]) {
        let rules = try JSONDecoder().decode([KFreshBundleRule].self, from: data)
        var byID: [String: KFreshBundleRule] = [:]
        var byName: [String: [KFreshBundleRule]] = [:]
        for rule in rules {
            byID[rule.bundleID] = rule
            byName[rule.appName.lowercased(), default: []].append(rule)
        }
        return (byID, byName)
    }

    /// Load rules from a JSON file in the main bundle's `Resources/`
    /// directory. Used by `ResidueScanner` (C-2 fix) so the production
    /// scan path picks up the curated `cask_rules.json` without an
    /// explicit init argument.
    /// - Parameter resourceName: Bundle resource filename (e.g.
    ///   `"cask_rules"`); Xcode appends `.json` automatically.
    /// - Parameter bundle: Bundle to look in; defaults to `.main`.
    /// - Returns: A `BundleRuleStore` loaded with the bundled rules, or
    ///   `nil` if the resource is missing or malformed. Returning `nil`
    ///   (rather than throwing) lets callers fall back to the
    ///   template-only branch when the bundled resource is unavailable
    ///   — important during first launch before the bundle is set up.
    public static func loadFromBundledJSON(
        named resourceName: String = "cask_rules",
        in bundle: Bundle = .main
    ) -> BundleRuleStore? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            return nil
        }
        do {
            return try BundleRuleStore(jsonURL: url)
        } catch {
            print("BundleRuleStore.loadFromBundledJSON: failed to decode \(url.path): \(error)")
            return nil
        }
    }

    /// Look up an exact bundle ID.
    public func lookup(bundleID: String) -> KFreshBundleRule? {
        rulesByBundleID[bundleID]
    }

    /// Return every rule whose lowercased app name contains `name` as a substring.
    public func fuzzyMatch(name: String) -> [KFreshBundleRule] {
        let needle = name.lowercased()
        var results: [KFreshBundleRule] = []
        for (key, value) in rulesByLowercasedName where key.contains(needle) {
            results.append(contentsOf: value)
        }
        return results
    }

    /// Snapshot of every loaded rule.
    public func allRules() -> [KFreshBundleRule] {
        Array(rulesByBundleID.values)
    }

    /// Total number of loaded rules.
    public var count: Int { rulesByBundleID.count }
}