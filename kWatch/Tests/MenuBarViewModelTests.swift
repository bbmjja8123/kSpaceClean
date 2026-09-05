import XCTest
import MetricsKit
@testable import kWatch

@MainActor
final class MenuBarViewModelTests: XCTestCase {

    /// A pro user sees all 8 metrics flowing through the menu bar view
    /// model, including the Pro-only temperature / fan / battery / GPU values.
    func testMenuBarViewModelExposesAllEightMetrics() async {
        let container = TestAppContainer(
            cpu: .percentage(40),
            memory: .percentage(60),
            disk: .percentage(70),
            network: .bytesPerSecond(3000),
            temperature: .degreesCelsius(65),
            fan: .revolutionsPerMinute(2200),
            battery: .percentage(90),
            gpu: .percentage(58)
        )
        container.purchaseState.update(isPro: true)
        let vm = MenuBarViewModel(container: container)
        vm.start()

        await container.aggregator.start()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(vm.cpuPercent, 40, accuracy: 0.5)
        XCTAssertEqual(vm.memoryPercent, 60, accuracy: 0.5)
        XCTAssertEqual(vm.diskPercent, 70, accuracy: 0.5)
        // `MetricValue.bytesPerSecond` carries a single combined total.
        XCTAssertEqual(vm.networkBytesSent, 0)
        XCTAssertEqual(vm.networkBytesReceived, 3000)
        XCTAssertEqual(vm.networkBytesPerSecond, 3000)
        XCTAssertEqual(vm.temperatureCelsius ?? -1, 65, accuracy: 0.5)
        XCTAssertEqual(vm.fanRPM, 2200)
        XCTAssertEqual(vm.batteryPercent ?? -1, 90, accuracy: 0.5)
        XCTAssertEqual(vm.gpuUsagePercent ?? -1, 58, accuracy: 0.5)

        vm.stop()
        await container.aggregator.stop()
    }

    /// A free user still gets the free metrics, but the Pro-only
    /// temperature value stays nil (the UI renders the lock instead).
    func testFreeUserHidesProMetricValues() async {
        let container = TestAppContainer(cpu: .percentage(40), temperature: .degreesCelsius(65))
        container.purchaseState.update(isPro: false)
        let vm = MenuBarViewModel(container: container)
        vm.start()

        await container.aggregator.start()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(vm.cpuPercent, 40, accuracy: 0.5)
        XCTAssertNil(vm.temperatureCelsius, "Free users must not see temperature values")

        vm.stop()
        await container.aggregator.stop()
    }

    /// `GPUMonitor` emits `.percentage` (usage) on Apple Silicon, so the
    /// menu bar must consume it and format it as a percent unit — not the
    /// historical `.degreesCelsius` temperature.
    func testGPUPercentageIsConsumedForMenuBar() async {
        let container = TestAppContainer()
        container.purchaseState.update(isPro: true)
        let vm = MenuBarViewModel(container: container)
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .percentage(42.5)],
            availability: [.gpu: .available]
        )
        vm.consumeForTesting(snapshot)

        XCTAssertEqual(vm.gpuUsagePercent ?? -1, 42.5, accuracy: 0.01)
        let data = vm.displayData(for: .gpu)
        XCTAssertEqual(data.unit, "%")
    }

    /// Free users must not see the Pro-only GPU usage value (the UI
    /// renders the lock instead).
    func testGPUPercentageNilForFreeUsers() async {
        let container = TestAppContainer()
        container.purchaseState.update(isPro: false)
        let vm = MenuBarViewModel(container: container)
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.gpu: .percentage(42.5)],
            availability: [.gpu: .available]
        )
        vm.consumeForTesting(snapshot)

        XCTAssertNil(vm.gpuUsagePercent)
    }
}
