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
    /// Semantic metadata for one cleanable unit of an app. Each action
    /// carries a bilingual title plus the concrete paths to delete.
    public struct ResolvedAction: Sendable, Equatable {
        public let name: String
        public let nameCN: String
        public let paths: [String]

        public init(name: String, nameCN: String, paths: [String]) {
            self.name = name
            self.nameCN = nameCN
            self.paths = paths
        }
    }

    public let bundleID: String
    public let name: String
    public let nameCN: String
    public let vendor: String
    public let type: String
    public let riskLevel: String
    public let cleanPaths: [String]
    public let confidence: String
    /// Per-action clean paths (v2 schema). For v1-style rows this holds a
    /// single synthetic action whose title mirrors the app name.
    public let actions: [ResolvedAction]

    public init(
        bundleID: String,
        name: String,
        nameCN: String,
        vendor: String,
        type: String,
        riskLevel: String,
        cleanPaths: [String],
        confidence: String,
        actions: [ResolvedAction]
    ) {
        self.bundleID = bundleID
        self.name = name
        self.nameCN = nameCN
        self.vendor = vendor
        self.type = type
        self.riskLevel = riskLevel
        self.cleanPaths = cleanPaths
        self.confidence = confidence
        self.actions = actions
    }
}

/// Thread-safe lookup table for `Bundle ID → ResolvedApp`.
///
/// The default initializer is **lazy**: nothing is read from disk until the
/// first call to ``load(from:)``. Once loaded, subsequent calls become no-ops
/// and the in-memory table is reused.
public actor BundleIDResolver {
    /// Indexed by bundle ID for the direct-lookup path. Each value carries a
    /// pre-expanded copy of every action's clean paths (v1-first ordering:
    /// the synthetic fallback action, then v2 actions in JSON order) so we do
    /// not retilde on every ``resolve(path:)`` call.
    private struct Entry {
        let app: ResolvedApp
        let expandedActionPaths: [String]
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
                // Strip trailing slashes so L1's prefix match can re-apply a
                // path-boundary check (`prefix + "/"`) instead of relying on
                // the JSON spelling. Without the strip, a trailing-slash
                // prefix would double the separator (`prefix + "/"` becomes
                // `...//`) and never match a real child path.
                let expanded = app.actions.flatMap(\.paths).map { path in
                    let e = Self.expand(path)
                    return e.count > 1 && e.hasSuffix("/") ? String(e.dropLast()) : e
                }
                mapping[bundleID] = Entry(app: app, expandedActionPaths: expanded)
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
        // Prefixes are the pre-expanded paths of every action (v1 fallback
        // action first, then v2 actions in JSON order).
        for entry in mapping.values {
            for prefix in entry.expandedActionPaths {
                // Path-boundary check: the prefix must match a whole path
                // component, not merely a string prefix. Without this,
                // `com.anthropic.claude` (prefix `.../com.anthropic.claude`)
                // would swallow files owned by `com.anthropic.claudefordesktop`
                // (prefix `.../com.anthropic.claudefordesktop`) whenever the
                // dictionary iterates the shorter bundle ID first — a
                // non-deterministic misattribution. Prefixes are pre-stripped
                // of trailing slashes at load time, so the separator can be
                // re-applied here safely.
                if normalized == prefix || normalized.hasPrefix(prefix + "/") {
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

    /// Number of apps in the loaded map (alias of ``count``). Convenience for
    /// callers/tests that read the map as a dictionary.
    public var appCount: Int { mapping.count }

    /// Direct lookup by bundle ID. Returns ``nil`` when the map is unloaded
    /// or the ID is unknown.
    public func app(forBundleID id: String) -> ResolvedApp? {
        mapping[id]?.app
    }

    // MARK: - Public testable helpers

    /// Expand a tilde-prefixed path against the **real** $HOME (passwd-based),
    /// NOT the sandbox container home. `expandingTildeInPath` resolves `~` to
    /// the container home inside a sandboxed app, which never matches the
    /// orchestrator's enumerator output (also passwd-based via
    /// `UserPathResolver.expandTilde`). This silent mismatch was the root cause
    /// of the 2026-08-01 "应用缓存 → 应用缓存" duplication bug.
    ///
    /// Exposed as `public` (rather than `private`) so the regression test in
    /// `BundleIDResolverTests` can assert the implementation uses the real
    /// `$HOME` rather than the sandbox container, independent of whether the
    /// test runner itself is sandboxed.
    public static func expand(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.path
        return home + String(path.dropFirst(1))
    }

    /// Build a ``ResolvedApp`` from a single record in the JSON ``apps`` map.
    /// Returns ``nil`` for malformed entries so a corrupt row can never crash
    /// the resolver — we just drop it and move on.
    ///
    /// Accepts both schema generations:
    /// - **v2** — ``actions`` is an array of `{name, nameCN, type, paths}`;
    ///   `nameCN` falls back to `name` per action.
    /// - **v1** — flat ``cleanPaths``; it becomes a single synthetic action
    ///   whose `name` and `nameCN` mirror the app's `nameCN`.
    ///
    /// A row with neither key is malformed and dropped.
    private static func makeApp(bundleID: String, dict: [String: Any]) -> ResolvedApp? {
        let name = (dict["name"] as? String) ?? ""
        let nameCN = (dict["nameCN"] as? String) ?? name
        let vendor = (dict["vendor"] as? String) ?? ""
        let type = (dict["type"] as? String) ?? "other"
        let risk = (dict["riskLevel"] as? String) ?? "recommended"
        let confidence = (dict["confidence"] as? String) ?? "medium"

        var actions: [ResolvedApp.ResolvedAction] = []
        var legacyCleanPaths: [String] = []

        if let v2 = dict["actions"] as? [[String: Any]] {
            // v2 schema. A v2 action without `paths` is malformed and is
            // skipped; actions without `name` degrade to an empty title.
            actions = v2.compactMap { a in
                guard let paths = a["paths"] as? [String] else { return nil }
                let aName = (a["name"] as? String) ?? ""
                let aNameCN = (a["nameCN"] as? String) ?? aName
                return ResolvedApp.ResolvedAction(name: aName, nameCN: aNameCN, paths: paths)
            }
        } else if let cleanPaths = dict["cleanPaths"] as? [String] {
            // v1 legacy fallback: one synthetic action titled after the app.
            legacyCleanPaths = cleanPaths
            actions = [ResolvedApp.ResolvedAction(name: nameCN, nameCN: nameCN, paths: cleanPaths)]
        } else {
            return nil
        }

        return ResolvedApp(
            bundleID: bundleID,
            name: name,
            nameCN: nameCN,
            vendor: vendor,
            type: type,
            riskLevel: risk,
            cleanPaths: legacyCleanPaths,
            confidence: confidence,
            actions: actions
        )
    }
}
