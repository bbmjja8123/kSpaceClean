// kFoundation/Sources/FileScanner/BundleIDResolver.swift
//
// Resolves a filesystem path to the macOS app that owns it.
//
// This resolver loads a static JSON map (built from Lemon's cleaning-rule data
// via ``scripts/lemon_xml_to_json.py``) and looks up a ``ResolvedApp`` in three
// cascading ways, from cheapest to most expensive:
//
// 1. **L1 — clean-path prefix match**: the path begins with one of the
//    app's registered clean directories (``~/Library/Caches/<bundleID>`` etc.).
// 2. **L2 — reverse-DNS token match**: a `com.vendor.app` token appears
//    somewhere in the path (e.g. ``/Containers/com.tencent.xinWeChat/...``).
// 3. **No match → ``nil``**: the path belongs to a generic system location.
//
// The resolver is an ``actor`` so the file is loaded at most once per process
// even under concurrent access, and the lookup is O(matches). The data file
// is shipped inside the host app's bundle, not vendored here — callers
// inject the URL via ``load(from:)`` because kFoundation is a generic package
// with no opinion about host app layout.

import Foundation

/// Public metadata about a single macOS app, hydrated from the JSON map.
public struct ResolvedApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public let nameCN: String
    public let vendor: String
    public let type: String
    public let riskLevel: String
    public let cleanPaths: [String]
    public let confidence: String

    public init(
        bundleID: String,
        name: String,
        nameCN: String,
        vendor: String,
        type: String,
        riskLevel: String,
        cleanPaths: [String],
        confidence: String
    ) {
        self.bundleID = bundleID
        self.name = name
        self.nameCN = nameCN
        self.vendor = vendor
        self.type = type
        self.riskLevel = riskLevel
        self.cleanPaths = cleanPaths
        self.confidence = confidence
    }
}

/// Thread-safe lookup table for `Bundle ID → ResolvedApp`.
///
/// The default initializer is **lazy**: nothing is read from disk until the
/// first call to ``load(from:)``. Once loaded, subsequent calls become no-ops
/// and the in-memory table is reused.
public actor BundleIDResolver {
    /// Indexed by bundle ID for the direct-lookup path. Each value carries a
    /// pre-expanded copy of its clean paths so we do not retilde on every
    /// ``resolve(path:)`` call.
    private struct Entry {
        let app: ResolvedApp
        let expandedCleanPaths: [String]
    }

    private var mapping: [String: Entry] = [:]
    private var loaded = false
    private var loadError: String?

    public init() {}

    /// Load the JSON map from ``url`` exactly once. Subsequent calls are
    /// no-ops. Failures are recorded into ``loadError`` rather than thrown
    /// so the resolver can degrade to "always returns ``nil``" without
    /// crashing the scan pipeline.
    public func load(from url: URL) async {
        guard !loaded else { return }
        loaded = true  // mark even on failure so we do not retry forever
        do {
            let data = try Data(contentsOf: url)
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                loadError = "Top-level JSON is not an object"
                return
            }
            guard let apps = raw["apps"] as? [String: [String: Any]] else {
                loadError = "Missing 'apps' key or wrong shape"
                return
            }
            for (bundleID, dict) in apps {
                guard let app = Self.makeApp(bundleID: bundleID, dict: dict) else { continue }
                let expanded = app.cleanPaths.map(Self.expand)
                mapping[bundleID] = Entry(app: app, expandedCleanPaths: expanded)
            }
        } catch {
            loadError = "Failed to load BundleID mapping: \(error)"
        }
    }

    /// True if ``load(from:)`` has been called and did not fail catastrophically.
    public var isLoaded: Bool {
        loaded && loadError == nil
    }

    /// The most recent load error message, or ``nil`` if everything is fine.
    public var lastLoadError: String? { loadError }

    /// Look up which app, if any, owns ``path``. ``path`` may use ``~`` for
    /// the home directory; the resolver normalises both sides before comparing.
    public func resolve(path: String) -> ResolvedApp? {
        let normalized = Self.expand(path)

        // L1 — path-prefix match. O(n*m) over the table, but the table is
        // bounded to a few dozen apps in v1, and we exit on the first hit.
        for entry in mapping.values {
            for prefix in entry.expandedCleanPaths {
                if normalized.hasPrefix(prefix) {
                    return entry.app
                }
            }
        }

        // L2 — reverse-DNS token. We use a literal substring search rather
        // than a regex for speed; the only false positives are paths that
        // incidentally contain a dotted word like ``com.apple.something``,
        // and those will normally be matched by L1 first.
        for entry in mapping.values {
            if normalized.contains(entry.app.bundleID) {
                return entry.app
            }
        }

        return nil
    }

    /// Number of apps in the loaded map. Useful for assertions in tests.
    public var count: Int { mapping.count }

    // MARK: - Private helpers

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Build a ``ResolvedApp`` from a single record in the JSON ``apps`` map.
    /// Returns ``nil`` for malformed entries so a corrupt row can never crash
    /// the resolver — we just drop it and move on.
    private static func makeApp(bundleID: String, dict: [String: Any]) -> ResolvedApp? {
        let name = (dict["name"] as? String) ?? ""
        let nameCN = (dict["nameCN"] as? String) ?? name
        let vendor = (dict["vendor"] as? String) ?? ""
        let type = (dict["type"] as? String) ?? "other"
        let risk = (dict["riskLevel"] as? String) ?? "recommended"
        let cleanPaths = (dict["cleanPaths"] as? [String]) ?? []
        let confidence = (dict["confidence"] as? String) ?? "medium"
        return ResolvedApp(
            bundleID: bundleID,
            name: name,
            nameCN: nameCN,
            vendor: vendor,
            type: type,
            riskLevel: risk,
            cleanPaths: cleanPaths,
            confidence: confidence
        )
    }
}
