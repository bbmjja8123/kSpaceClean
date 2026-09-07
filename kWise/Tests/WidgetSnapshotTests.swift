// kWise/Tests/WidgetSnapshotTests.swift
//
// v2.0 Phase 6 — App Group snapshot feed round-trip, schema guard, atomic
// merge, and the sink that feeds it from cleanup events.
import XCTest
@testable import kWise

final class WidgetSnapshotTests: XCTestCase {

    private var storeURL: URL!
    private var store: WidgetSnapshotStore!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snap-\(UUID().uuidString).json")
        store = WidgetSnapshotStore(fileURL: storeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    func testRoundTripCodable() {
        let snapshot = WidgetSnapshot(
            disk: .init(usedBytes: 300, totalBytes: 500),
            lastCleanup: .init(freedBytes: 1_000, date: Date(timeIntervalSince1970: 100)),
            streak: .init(currentStreak: 2, longestStreak: 5),
            topCategory: .init(title: "系统缓存", size: 900),
            forecast: .init(daysToFull: 42, isReliable: true)
        )
        store.write(snapshot)
        let read = store.read()
        XCTAssertEqual(read, snapshot)
    }

    func testMissingFileReadsNil() {
        XCTAssertNil(store.read())
    }

    func testUnknownSchemaVersionRejected() {
        var snapshot = WidgetSnapshot()
        snapshot.schemaVersion = 99
        store.write(snapshot)
        XCTAssertNil(store.read(), "Unknown schema versions must read as no-data")
    }

    func testUpdateMergesFields() {
        store.update { $0.disk = .init(usedBytes: 1, totalBytes: 2) }
        store.update { $0.lastCleanup = .init(freedBytes: 42, date: Date()) }

        let read = store.read()
        XCTAssertEqual(read?.disk?.totalBytes, 2, "Second update must preserve the disk field")
        XCTAssertEqual(read?.lastCleanup?.freedBytes, 42)
    }

    func testNoAppGroupDegradesGracefully() {
        let noGroup = WidgetSnapshotStore(fileURL: nil)
        noGroup.write(WidgetSnapshot())     // Must not crash
        XCTAssertNil(noGroup.read())
    }
}

final class WidgetSnapshotSinkTests: XCTestCase {

    private var storeURL: URL!
    private var store: WidgetSnapshotStore!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-sink-\(UUID().uuidString).json")
        store = WidgetSnapshotStore(fileURL: storeURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    func testSinkWritesLastCleanup() async {
        let sink = WidgetSnapshotSink(store: store)
        await sink.cleanupDidFinish(
            CleanupEvent(freedBytes: 5_000, measuredBytes: nil, itemCount: 3)
        )
        let read = store.read()
        XCTAssertEqual(read?.lastCleanup?.freedBytes, 5_000)
    }

    func testSinkIgnoresZeroByteCleanup() async {
        let sink = WidgetSnapshotSink(store: store)
        await sink.cleanupDidFinish(CleanupEvent(freedBytes: 0, measuredBytes: nil, itemCount: 0))
        XCTAssertNil(store.read()?.lastCleanup,
                     "Zero-byte events must never touch the feed")
    }
}
