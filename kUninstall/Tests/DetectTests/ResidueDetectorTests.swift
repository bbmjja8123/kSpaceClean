import XCTest
@testable import kUninstall

final class ResidueDetectorTests: XCTestCase {
    func testAllPathTemplatesGenerated() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(
            bundleID: "com.example.Test",
            appName: "TestApp"
        )
        XCTAssertFalse(residues.isEmpty, "Should generate paths from templates")
    }

    func testConfidenceHighForPreferences() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "com.example.Test", appName: "Test")
        let prefs = residues.filter { $0.type == .preferences }
        XCTAssertFalse(prefs.isEmpty)
        XCTAssertEqual(prefs.first?.confidence, 0.99)
    }

    func testConfidenceLowForPlugins() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "com.example.Test", appName: "Test")
        let plugins = residues.filter { $0.type == .plugin }
        if let plugin = plugins.first {
            XCTAssertEqual(plugin.confidence, 0.80)
        }
    }

    func testNoResiduesForUnknownBundle() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "", appName: "")
        XCTAssertTrue(residues.isEmpty)
    }
}
