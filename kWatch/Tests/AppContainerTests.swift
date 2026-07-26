import XCTest
import MetricsKit
@testable import kWatch

final class AppContainerTests: XCTestCase {
    @MainActor
    func testTestAppContainerPublishesConfiguredStubs() async {
        let container = TestAppContainer(cpu: .percentage(37), memory: .percentage(64))
        XCTAssertFalse(container.purchaseState.isPro)
        XCTAssertEqual(container.appState.latestSnapshot, nil)
        await container.aggregator.start()
        let stream = await container.aggregator.stream()
        var iterator = stream.makeAsyncIterator()
        let snapshot = await iterator.next()
        XCTAssertNotNil(snapshot?.values[.cpu])
        await container.aggregator.stop()
    }

    func testLiveAppContainerConformsToProtocol() {
        let container: any AppContainerProtocol = LiveAppContainer()
        XCTAssertNotNil(container.aggregator)
        XCTAssertNotNil(container.appState)
        XCTAssertNotNil(container.purchaseState)
    }
}