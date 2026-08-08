import XCTest
@testable import kWise
import FileScanner

final class ScanSpeedTests: XCTestCase {
    // MARK: - Default

    func test_defaultSpeed_isMedium() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.scanSpeed, .medium)
    }

    // MARK: - All Cases

    func test_allCases_containsFourLevels() {
        XCTAssertEqual(ScanSpeed.allCases.count, 4)
        XCTAssertTrue(ScanSpeed.allCases.contains(.turbo))
        XCTAssertTrue(ScanSpeed.allCases.contains(.fast))
        XCTAssertTrue(ScanSpeed.allCases.contains(.medium))
        XCTAssertTrue(ScanSpeed.allCases.contains(.gentle))
    }

    // MARK: - Batch Size

    func test_turbo_batchSizeZero() {
        XCTAssertEqual(ScanSpeed.turbo.batchSize, 0)
    }

    func test_fast_batchSize() {
        XCTAssertGreaterThan(ScanSpeed.fast.batchSize, 0)
    }

    func test_medium_batchSize() {
        XCTAssertGreaterThan(ScanSpeed.medium.batchSize, 0)
    }

    func test_gentle_batchSize_smallerThanMedium() {
        XCTAssertLessThan(ScanSpeed.gentle.batchSize, ScanSpeed.medium.batchSize)
    }

    // MARK: - Sleep Duration

    func test_turbo_noSleep() {
        XCTAssertEqual(ScanSpeed.turbo.sleepNanoseconds, 0)
    }

    func test_fast_noSleep() {
        XCTAssertEqual(ScanSpeed.fast.sleepNanoseconds, 0)
    }

    func test_medium_hasSleep() {
        XCTAssertGreaterThan(ScanSpeed.medium.sleepNanoseconds, 0)
    }

    func test_gentle_longerSleepThanMedium() {
        XCTAssertGreaterThan(ScanSpeed.gentle.sleepNanoseconds, ScanSpeed.medium.sleepNanoseconds)
    }

    // MARK: - Throttle Config

    func test_throttle_matchesBatchSizeAndSleep() {
        for speed in ScanSpeed.allCases {
            let throttle = speed.throttle
            XCTAssertEqual(throttle.batchSize, speed.batchSize)
            XCTAssertEqual(throttle.sleepNanoseconds, speed.sleepNanoseconds)
        }
    }

    // MARK: - Display Name

    func test_displayName_notEmpty() {
        for speed in ScanSpeed.allCases {
            XCTAssertFalse(speed.displayName.isEmpty)
        }
    }

    func test_description_notEmpty() {
        for speed in ScanSpeed.allCases {
            XCTAssertFalse(speed.description.isEmpty)
        }
    }

    // MARK: - Raw Values

    func test_rawValues_areLowercase() {
        for speed in ScanSpeed.allCases {
            XCTAssertEqual(speed.rawValue, speed.rawValue.lowercased())
        }
    }

    // MARK: - Codable

    func test_codable_roundTrip() throws {
        for speed in ScanSpeed.allCases {
            let data = try JSONEncoder().encode(speed)
            let decoded = try JSONDecoder().decode(ScanSpeed.self, from: data)
            XCTAssertEqual(decoded, speed)
        }
    }

    // MARK: - Sendable

    func test_speed_isSendable() {
        // Compile-time check: ScanSpeed conforms to Sendable
        let speed: Sendable = ScanSpeed.medium
        _ = speed
    }

    func test_throttleConfig_isSendable() {
        // Compile-time check: ThrottleConfig conforms to Sendable
        let config: Sendable = ThrottleConfig(batchSize: 100, sleepNanoseconds: 1_000_000)
        _ = config
    }

    // MARK: - ThrottleConfig

    func test_throttleConfig_defaultNoThrottle() {
        let config = ThrottleConfig(batchSize: 0, sleepNanoseconds: 0)
        XCTAssertEqual(config.batchSize, 0)
        XCTAssertEqual(config.sleepNanoseconds, 0)
    }
}
