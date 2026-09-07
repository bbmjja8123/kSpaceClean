import XCTest
@testable import kFresh

/// Unit tests for the v1.x-C `MappingStore` + `ZhAppMapping` schema.
///
/// Covers the four invariants the spec §4.6.3 calls out that this layer
/// can enforce without external systems:
/// 1. Schema decodes losslessly (no field drops).
/// 2. Deprecated entries are filtered out at build time.
/// 3. Duplicate bundle IDs are deduped (first wins — pipeline regression
///    signal).
/// 4. Missing / malformed JSON returns nil (graceful fallback to the
///    cask token path).
///
/// Not `@MainActor` because `MappingStore` is an actor and the tests
/// await each call from the default XCTest runner executor.
final class MappingStoreTests: XCTestCase {

    // MARK: - Schema round-trip

    func testSchemaDecodesFromMinimalValidJSON() async throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "QQ",
              "bundleID": "com.tencent.QQ",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual", "cask-cn"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let count = await store.count
        XCTAssertEqual(count, 1)
        let mapping = await store.lookup(bundleID: "com.tencent.QQ")
        XCTAssertEqual(mapping?.displayName, "QQ")
        XCTAssertEqual(mapping?.appName, nil,
                       "appName is optional in the schema — must stay nil when omitted")
        XCTAssertEqual(mapping?.verifiedBy, "manual")
        XCTAssertEqual(mapping?.sources, ["manual", "cask-cn"])
    }

    func testSchemaDecodesWithAllOptionalFields() async throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "微信",
              "bundleID": "com.tencent.xinWeChat",
              "appName": "WeChat",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let mapping = await store.lookup(bundleID: "com.tencent.xinWeChat")
        XCTAssertEqual(mapping?.appName, "WeChat")
    }

    func testSchemaRejectsMissingRequiredField() {
        // No 'verifiedAt' field — must throw.
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "QQ",
              "bundleID": "com.tencent.QQ",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try MappingStore(jsonData: json),
                             "verifiedAt is mandatory per spec §4.4 — a missing field must fail decoding")
    }

    // MARK: - Lookup

    func testLookupReturnsNilForUnknownBundleID() async throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "QQ",
              "bundleID": "com.tencent.QQ",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let mapping = await store.lookup(bundleID: "com.unknown.NotHere")
        XCTAssertNil(mapping)
    }

    func testFuzzyMatchIsCaseInsensitiveSubstring() async throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "QQ",
              "bundleID": "com.tencent.QQ",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            },
            {
              "displayName": "QQ 音乐",
              "bundleID": "com.tencent.QQMusic",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let lowerMatches = await store.fuzzyMatch(name: "qq")
        XCTAssertEqual(lowerMatches.count, 2, "Both 'QQ' and 'QQ 音乐' contain 'qq'")
        let upperMatches = await store.fuzzyMatch(name: "QQ")
        XCTAssertEqual(upperMatches.count, 2)
    }

    // MARK: - Deprecated filtering

    func testDeprecatedEntriesAreExcludedFromLookups() async throws {
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "OldApp",
              "bundleID": "com.legacy.OldApp",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": true
            },
            {
              "displayName": "NewApp",
              "bundleID": "com.fresh.NewApp",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let count = await store.count
        XCTAssertEqual(count, 1, "Deprecated entries must be filtered out at build time")
        let oldMapping = await store.lookup(bundleID: "com.legacy.OldApp")
        XCTAssertNil(oldMapping)
        let newMapping = await store.lookup(bundleID: "com.fresh.NewApp")
        XCTAssertNotNil(newMapping)
    }

    // MARK: - Duplicate bundle ID

    func testDuplicateBundleIDFirstWins() async throws {
        // Spec §4.6.3 invariant 1: manual entries must never be overwritten
        // by automated sources. If the pipeline regressed and stamped two
        // entries with the same bundleID, the first one wins (the upstream
        // generator should have rejected the second).
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-08-09T00:00:00Z",
          "source": "manual",
          "apps": [
            {
              "displayName": "First",
              "bundleID": "com.dupe.Both",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            },
            {
              "displayName": "Second",
              "bundleID": "com.dupe.Both",
              "verifiedAt": "2026-08-09T00:00:00Z",
              "verifiedBy": "manual",
              "sources": ["manual"],
              "deprecated": false
            }
          ]
        }
        """.data(using: .utf8)!
        let store = try MappingStore(jsonData: json)
        let count = await store.count
        XCTAssertEqual(count, 1)
        let mapping = await store.lookup(bundleID: "com.dupe.Both")
        XCTAssertEqual(mapping?.displayName, "First")
    }

    // MARK: - Graceful fallback

    func testLoadFromBundledJSONReturnsNilWhenResourceMissing() {
        // `loadFromBundledJSON` must return nil (not throw) when the
        // resource is absent — callers treat this as a benign miss and
        // fall back to the existing cask token look up path (spec
        // §4.6.3 invariant 7).
        let store = MappingStore.loadFromBundledJSON(
            named: "definitely_not_a_real_resource_\(UUID().uuidString)",
            in: .main
        )
        XCTAssertNil(store)
    }

    // MARK: - Bundled JSON

    /// Smoke test: the shipped `zh_app_mappings.json` (if present in the
    /// test bundle) decodes and exposes ≥ 1 entry. Skipped when the
    /// resource is not in the bundle (e.g. running unit tests before the
    /// resource is added to the app target).
    func testBundledJSONDecodesIfPresent() async throws {
        guard let store = MappingStore.loadFromBundledJSON() else {
            throw XCTSkip("zh_app_mappings.json not bundled in this test target")
        }
        let count = await store.count
        XCTAssertGreaterThan(count, 0)
        // The v1 baseline contains QQ; if the resource is bundled, this
        // is a stable anchor for a regression check.
        let mapping = await store.lookup(bundleID: "com.tencent.QQ")
        XCTAssertNotNil(mapping,
                        "Bundled JSON must contain the well-known anchor entry")
    }

    // MARK: - v1.1 coverage gate (spec §4.6.1)

    /// Spec §4.6.1 calls out "≥ 200 真 bundle ID 条目" as the v1.1
    /// coverage gate. We assert ≥ 200 here so a future regression that
    /// strips manual entries trips the gate before shipping.
    ///
    /// Skipped if the resource isn't bundled — same caveat as the
    /// smoke test above.
    func testBundledMappingCountMeetsV1Gate() async throws {
        guard let store = MappingStore.loadFromBundledJSON() else {
            throw XCTSkip("zh_app_mappings.json not bundled in this test target")
        }
        let count = await store.count
        XCTAssertGreaterThanOrEqual(count, 200,
            "v1.1 coverage gate: zh_app_mappings.json must have ≥ 200 entries (got \(count))")
    }

    /// Every bundled mapping must have a reverse-DNS-style bundle ID
    /// (≥ 2 dot-separated segments) — otherwise the residue scanner's
    /// lookup will silently skip it. Catches the easy mistake of
    /// pasting a non-conforming token into the JSON.
    func testBundledMappingsAllHaveReverseDNSBundleIDs() async throws {
        guard let store = MappingStore.loadFromBundledJSON() else {
            throw XCTSkip("zh_app_mappings.json not bundled in this test target")
        }
        let all = await store.allMappings()
        let nonConforming = all.filter { mapping in
            let segments = mapping.bundleID.split(separator: ".")
            return segments.count < 2 || mapping.bundleID.isEmpty
        }
        XCTAssertTrue(nonConforming.isEmpty,
                      "Every bundled mapping must be reverse-DNS; offenders: \(nonConforming.map(\.bundleID))")
    }

    /// The bundled JSON must not contain duplicate bundle IDs — the
    /// upstream generator deduplicates by bundle ID with "first wins",
    /// so a duplicate at this layer means a generation regression.
    func testBundledMappingsHaveUniqueBundleIDs() async throws {
        guard let store = MappingStore.loadFromBundledJSON() else {
            throw XCTSkip("zh_app_mappings.json not bundled in this test target")
        }
        let all = await store.allMappings()
        let grouped = Dictionary(grouping: all, by: \.bundleID)
        let dupes = grouped.filter { $0.value.count > 1 }
        XCTAssertTrue(dupes.isEmpty,
                      "Duplicate bundle IDs in shipped JSON: \(dupes.keys)")
    }
}