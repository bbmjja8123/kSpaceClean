import XCTest
import DetectionCore
@testable import kSift

final class SimilarityPresetTests: XCTestCase {
    func testPresetThresholdsMatchEngineContract() {
        // These values are the product contract: "Normal" must equal the
        // historical hardcoded engine defaults so an existing install's
        // behavior doesn't change after upgrading.
        XCTAssertEqual(SimilarityPreset.normal.maximumHammingDistance, 10)
        XCTAssertEqual(SimilarityPreset.normal.visionDistanceThreshold, 0.6, accuracy: 0.0001)
        XCTAssertLessThan(SimilarityPreset.strict.maximumHammingDistance, SimilarityPreset.normal.maximumHammingDistance)
        XCTAssertLessThan(SimilarityPreset.normal.maximumHammingDistance, SimilarityPreset.loose.maximumHammingDistance)
        XCTAssertLessThan(SimilarityPreset.strict.visionDistanceThreshold, SimilarityPreset.loose.visionDistanceThreshold)
    }

    func testCodableRoundTrip() throws {
        for preset in SimilarityPreset.allCases {
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(SimilarityPreset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }
    }

    func testLegacyRawValueDecodesToNormal() {
        XCTAssertEqual(SimilarityPreset(rawValue: "normal"), .normal)
        XCTAssertNil(SimilarityPreset(rawValue: "bogus"), "Unknown raw values must not fabricate a case")
    }

    func testLargeFileSizeThresholdRoundTrip() throws {
        var config = ProfileConfig.default
        config.largeFileSizeThreshold = 512 * 1024 * 1024
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProfileConfig.self, from: data)
        XCTAssertEqual(decoded.largeFileSizeThreshold, 512 * 1024 * 1024)
        XCTAssertEqual(decoded.similarityPreset, config.similarityPreset)
    }

    func testLegacyConfigJSONDecodesWithDefaults() throws {
        // A v1.2-era payload without the new keys must decode to the
        // historical defaults: keep-newest / normal similarity / 100 MB.
        let legacy = """
        {"type":"developer","customDirectories":[],"exclusions":[],"minFileSize":1024,"enablePerceptualScan":true,"enableBuildArtifacts":true}
        """
        let config = try JSONDecoder().decode(ProfileConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(config.selectionStrategy, .keepNewest)
        XCTAssertEqual(config.similarityPreset, .normal)
        XCTAssertEqual(config.largeFileSizeThreshold, 100 * 1024 * 1024)
    }
}
