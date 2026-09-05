import XCTest
@testable import kSift

final class ProfileConfigStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "test.profile.config.store"

    override func setUp() {
        super.setUp()
        // Use a private suite so tests don't pollute the host's UserDefaults
        // and can't see each other's state.
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadOnEmptyDefaultsReturnsDeveloperProfile() {
        let loaded = ProfileConfigStore.load(defaults: defaults)
        // The store persists only CUSTOM exclusion patterns; the profile's
        // built-in exclusions are merged at scan time
        // (`ProfileType.additionalExclusions`), so an empty store yields
        // empty custom exclusions rather than `.default`'s seeded list.
        XCTAssertEqual(loaded.type, .developer)
        XCTAssertEqual(loaded.customDirectories, [])
        XCTAssertEqual(loaded.exclusions, [])
        XCTAssertEqual(loaded.minFileSize, 1024)
        XCTAssertTrue(loaded.enablePerceptualScan)
        XCTAssertTrue(loaded.enableBuildArtifacts)
        XCTAssertEqual(loaded.selectionStrategy, .keepNewest)
        XCTAssertEqual(loaded.similarityPreset, .normal)
        XCTAssertEqual(loaded.largeFileSizeThreshold, 100 * 1024 * 1024)
    }

    func testRoundTripPreservesEveryField() {
        var config = ProfileConfig(
            type: .photographer,
            customDirectories: ["~/Pictures/2024", "~/Pictures/Raw"],
            exclusions: ["**/.thumbnails/**", "**/*.tmp"],
            minFileSize: 4096,
            enablePerceptualScan: false,
            enableBuildArtifacts: true,
            selectionStrategy: .keepShortestPath
        )
        config.similarityPreset = .strict
        config.largeFileSizeThreshold = 50 * 1024 * 1024

        ProfileConfigStore.save(config, defaults: defaults)
        let loaded = ProfileConfigStore.load(defaults: defaults)

        XCTAssertEqual(loaded, config)
    }

    func testPersistsAcrossLoadCalls() {
        let config = ProfileConfig(
            type: .designer,
            customDirectories: ["~/Desktop"],
            exclusions: ["**/node_modules/**"],
            minFileSize: 8192,
            enablePerceptualScan: true,
            enableBuildArtifacts: false
        )
        ProfileConfigStore.save(config, defaults: defaults)

        // Two successive loads must return the same value (no in-memory
        // caching effect to flake on).
        XCTAssertEqual(ProfileConfigStore.load(defaults: defaults), config)
        XCTAssertEqual(ProfileConfigStore.load(defaults: defaults), config)
    }

    func testLegacyKeysDefaultSensibly() {
        // Simulate an older payload missing the newer toggle keys by
        // writing only the profile type.
        defaults.set(ProfileType.photographer.rawValue, forKey: "ksift.profile.type")

        let loaded = ProfileConfigStore.load(defaults: defaults)
        XCTAssertEqual(loaded.type, .photographer)
        XCTAssertEqual(loaded.customDirectories, [])
        XCTAssertEqual(loaded.exclusions, [])
        XCTAssertEqual(loaded.minFileSize, 1024)
        // Missing toggles fall back to true per ProfileConfig.default.
        XCTAssertTrue(loaded.enablePerceptualScan)
        XCTAssertTrue(loaded.enableBuildArtifacts)
    }

    func testUnknownProfileTypeFallsBackToDeveloper() {
        // Forward-compat: if a future build renames a case, older payloads
        // decoding it shouldn't crash — should degrade to developer.
        defaults.set("nonexistent-profile", forKey: "ksift.profile.type")
        XCTAssertEqual(ProfileConfigStore.load(defaults: defaults).type, .developer)
    }

    func testSaveDoesNotTouchOtherDefaults() {
        // ProfileConfigStore must only touch the 6 ksift.profile.* keys —
        // no wildcards, no removeObject on unrelated keys.
        defaults.set("untouched", forKey: "ksift.unrelated.key")

        ProfileConfigStore.save(.default, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "ksift.unrelated.key"), "untouched")
    }
}