import XCTest
import AppIntents
@testable import kWatch

@MainActor
final class IntentParameterTests: XCTestCase {

    func testShowTopProcessesHasDefaultLimit() {
        let intent = ShowTopProcessesIntent()
        XCTAssertEqual(intent.limit, 10)
    }

    func testShowTopProcessesAcceptsCustomLimit() {
        let intent = ShowTopProcessesIntent()
        intent.limit = 25
        XCTAssertEqual(intent.limit, 25)
    }

    func testShowDiskUsageDefaultsToSystemVolume() {
        let intent = ShowDiskUsageIntent()
        XCTAssertEqual(intent.volume, .system)
    }

    func testShowNetworkRateDefaultsToCombined() {
        let intent = ShowNetworkRateIntent()
        XCTAssertEqual(intent.direction, .combined)
    }

    func testNetworkDirectionEnumRoundTrips() {
        for value in [NetworkDirectionParameter.combined, .download, .upload] {
            XCTAssertEqual(NetworkDirectionParameter(rawValue: value.rawValue), value)
        }
    }

    func testDiskVolumeEnumRoundTrips() {
        for value in [DiskVolumeParameter.system, .data, .external] {
            XCTAssertEqual(DiskVolumeParameter(rawValue: value.rawValue), value)
        }
    }
}
