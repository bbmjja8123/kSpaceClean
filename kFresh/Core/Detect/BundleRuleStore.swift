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
        let rules = try JSONDecoder().decode([KFreshBundleRule].self, from: data)
        var byID: [String: KFreshBundleRule] = [:]
        var byName: [String: [KFreshBundleRule]] = [:]
        for rule in rules {
            byID[rule.bundleID] = rule
            byName[rule.appName.lowercased(), default: []].append(rule)
        }
        self.rulesByBundleID = byID
        self.rulesByLowercasedName = byName
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