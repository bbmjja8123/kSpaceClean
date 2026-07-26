import XCTest
import MetricsKit
@testable import kWatch

@MainActor
final class MetricCardViewModelTests: XCTestCase {
    // MARK: - Free metrics (always accessible)

    func testFreeCardShowsFormattedValue() {
        let vm = MetricCardViewModel(
            kind: .cpu,
            value: .percentage(67),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "67%")
        XCTAssertEqual(vm.subtitle, "System CPU")
        XCTAssertEqual(vm.icon, "cpu")
        XCTAssertEqual(vm.cardColor, .blue)
        XCTAssertFalse(vm.isLocked)
        XCTAssertFalse(vm.isUnavailable)
        XCTAssertTrue(vm.unavailableDescription.isEmpty)
    }

    func testMemoryCardFormatsBytes() {
        let vm = MetricCardViewModel(
            kind: .memory,
            value: .bytes(8_589_934_592),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "8 GB")
        XCTAssertEqual(vm.subtitle, "Memory Pressure")
        XCTAssertEqual(vm.cardColor, .green)
    }

    func testDiskCardFormatsPercentage() {
        let vm = MetricCardViewModel(
            kind: .disk,
            value: .percentage(44),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "44%")
        XCTAssertEqual(vm.subtitle, "Disk Usage")
    }

    func testNetworkCardFormatsBytesPerSecond() {
        let vm = MetricCardViewModel(
            kind: .network,
            value: .bytesPerSecond(1_048_576),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "1 MB/s")
        XCTAssertEqual(vm.subtitle, "Network Traffic")
    }

    // MARK: - Pro-gated metrics

    func testTemperatureIsLockedForFreeUser() {
        let vm = MetricCardViewModel(
            kind: .temperature,
            value: .degreesCelsius(72),
            availability: .available,
            isPro: false
        )
        XCTAssertTrue(vm.isLocked)
        XCTAssertFalse(vm.isUnavailable)
        XCTAssertEqual(vm.subtitle, "Pro Feature")
        XCTAssertEqual(vm.icon, "lock.fill")
        XCTAssertEqual(vm.cardColor, .gray)
        XCTAssertEqual(vm.lockDescription, "Upgrade to Pro to monitor temperature.")
    }

    func testTemperatureIsUnlockedForProUser() {
        let vm = MetricCardViewModel(
            kind: .temperature,
            value: .degreesCelsius(72),
            availability: .available,
            isPro: true
        )
        XCTAssertFalse(vm.isLocked)
        XCTAssertFalse(vm.isUnavailable)
        XCTAssertEqual(vm.displayValue, "72°C")
        XCTAssertEqual(vm.subtitle, "System Temperature")
        XCTAssertEqual(vm.icon, "thermometer")
        XCTAssertEqual(vm.cardColor, .red)
    }

    func testFanIsLockedForFreeUser() {
        let vm = MetricCardViewModel(
            kind: .fan,
            value: .revolutionsPerMinute(2200),
            availability: .available,
            isPro: false
        )
        XCTAssertTrue(vm.isLocked)
        XCTAssertEqual(vm.subtitle, "Pro Feature")
    }

    func testBatteryIsLockedForFreeUser() {
        let vm = MetricCardViewModel(
            kind: .battery,
            value: .percentage(91),
            availability: .available,
            isPro: false
        )
        XCTAssertTrue(vm.isLocked)
        XCTAssertEqual(vm.subtitle, "Pro Feature")
    }

    // MARK: - Unavailable hardware

    func testUnavailableFanShowsReason() {
        let vm = MetricCardViewModel(
            kind: .fan,
            value: .unavailable(.unsupported("SMC not found")),
            availability: .unsupported(reason: "SMC not found"),
            isPro: true
        )
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertFalse(vm.isLocked) // Unavailable trumps lock
        XCTAssertEqual(vm.subtitle, "SMC not found")
        XCTAssertEqual(vm.icon, "questionmark.circle")
        XCTAssertEqual(vm.cardColor, .gray)
    }

    func testUnavailableFreeCardIsNotLocked() {
        let vm = MetricCardViewModel(
            kind: .cpu,
            value: .unavailable(.systemCall("host_statistics", -1)),
            availability: .unavailable(reason: "Not supported on this Mac"),
            isPro: false
        )
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertFalse(vm.isLocked) // Unavailable, not lockable
        XCTAssertEqual(vm.subtitle, "Not supported on this Mac")
    }

    func testUnavailableProCardIsNotLocked() {
        // Even for a free user, unavailable Pro hardware should never show
        // as locked — the user cannot purchase their way to a working sensor.
        let vm = MetricCardViewModel(
            kind: .temperature,
            value: .unavailable(.unsupported("No thermal sensor")),
            availability: .unsupported(reason: "No thermal sensor"),
            isPro: false
        )
        XCTAssertTrue(vm.isUnavailable)
        XCTAssertFalse(vm.isLocked)
        XCTAssertEqual(vm.subtitle, "No thermal sensor")
    }

    // MARK: - Formatting edge cases

    func testFormatVolts() {
        let vm = MetricCardViewModel(
            kind: .battery,
            value: .volts(12.345),
            availability: .available,
            isPro: true
        )
        XCTAssertEqual(vm.displayValue, "12.35 V")
    }

    func testFormatText() {
        let vm = MetricCardViewModel(
            kind: .battery,
            value: .text("Charging"),
            availability: .available,
            isPro: true
        )
        XCTAssertEqual(vm.displayValue, "Charging")
    }

    func testFormatUnavailable() {
        let vm = MetricCardViewModel(
            kind: .cpu,
            value: .unavailable(.unsupported("No data")),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "N/A")
    }

    func testFormatSmallBytes() {
        let vm = MetricCardViewModel(
            kind: .memory,
            value: .bytes(512),
            availability: .available,
            isPro: false
        )
        XCTAssertEqual(vm.displayValue, "512 B")
    }

    // MARK: - Equatable

    func testViewModelEquatable() {
        let a = MetricCardViewModel(kind: .cpu, value: .percentage(50), availability: .available, isPro: false)
        let b = MetricCardViewModel(kind: .cpu, value: .percentage(50), availability: .available, isPro: false)
        XCTAssertEqual(a, b)

        let c = MetricCardViewModel(kind: .cpu, value: .percentage(75), availability: .available, isPro: false)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - CardColor

    func testCardColorResolvesToColor() {
        // Smoke test: all colors should resolve without crash.
        let colors: [CardColor] = [.blue, .green, .orange, .purple, .red, .yellow, .gray]
        for cardColor in colors {
            _ = cardColor.color
        }
    }
}
