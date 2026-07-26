//
//  WidgetSnapshotProviderTests.swift
//  kWatchWidgetTests
//
//  Tests for `WidgetSnapshotProvider`. All tests drive the provider through
//  its `SnapshotReading` boundary with `StubSnapshotReader`, so no App
//  Group provisioning is required.
//

import Foundation
import WidgetKit
import XCTest
@testable import kWatchWidget

final class WidgetSnapshotProviderTests: XCTestCase {
    // MARK: - Helpers

    /// A `SharedSnapshot` produced at a fixed instant. Used by "fresh" and
    /// "stale" tests.
    private func makeSnapshot(at timestamp: Date) -> SharedSnapshot {
        SharedSnapshot(
            timestamp: timestamp,
            cpuPercent: 42,
            memoryPercent: 55,
            diskPercent: 67,
            networkBytesPerSecond: 1_024,
            temperatureCelsius: 51,
            fanRPM: 1_800,
            batteryPercent: 80,
            cpuAvailable: true,
            memoryAvailable: true,
            diskAvailable: true,
            networkAvailable: true,
            temperatureAvailable: true,
            fanAvailable: true,
            batteryAvailable: true,
            isPro: false,
            menuBarModeRaw: "compact"
        )
    }

    /// Wait for a callback-based call to finish. WidgetKit's API uses
    /// `@escaping` completion handlers; this helper drains a single
    /// continuation deterministically.
    private func waitForEntry(
        from provider: WidgetSnapshotProvider,
        in context: TimelineProviderContext,
        file: StaticString = #file,
        line: UInt = #line
    ) -> SystemStatusEntry {
        let expectation = expectation(description: "timeline entry")
        var received: SystemStatusEntry?
        provider.getTimeline(in: context) { timeline in
            received = timeline.entries.first
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        guard let entry = received else {
            XCTFail("Provider never produced an entry", file: file, line: line)
            // Return a placeholder so the compiler is happy; the XCTFail
            // above has already recorded the failure.
            return SystemStatusEntry(date: Date(), snapshot: nil, state: .placeholder)
        }
        return entry
    }

    // MARK: - Tests

    /// The placeholder entry must always be `.placeholder` so the view layer
    /// can branch on state without touching the snapshot.
    func testPlaceholderReturnsPlaceholderEntry() {
        let provider = WidgetSnapshotProvider(reader: StubSnapshotReader(snapshot: nil))
        let entry = provider.placeholder(in: TimelineProviderContext())
        XCTAssertEqual(entry.state, .placeholder)
        XCTAssertNil(entry.snapshot)
    }

    /// When the reader returns a snapshot whose age is below the freshness
    /// threshold (30s), the timeline entry must be `.live` and carry the
    /// snapshot through.
    func testGetTimelineBuildsLiveEntryWhenSnapshotIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshotTimestamp = now.addingTimeInterval(-10) // 10s old
        let reader = StubSnapshotReader(snapshot: makeSnapshot(at: snapshotTimestamp))
        let provider = WidgetSnapshotProvider(reader: reader, now: { now })

        let entry = waitForEntry(from: provider, in: TimelineProviderContext())
        XCTAssertEqual(entry.state, .live)
        XCTAssertEqual(entry.snapshot?.cpuPercent, 42)
        XCTAssertEqual(entry.date, now)
    }

    /// When the snapshot is older than the freshness threshold (30s), the
    /// entry must be `.stale` so views can show the stale badge.
    func testGetTimelineBuildsStaleEntryWhenSnapshotIsOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshotTimestamp = now.addingTimeInterval(-120) // 2 minutes old
        let reader = StubSnapshotReader(snapshot: makeSnapshot(at: snapshotTimestamp))
        let provider = WidgetSnapshotProvider(reader: reader, now: { now })

        let entry = waitForEntry(from: provider, in: TimelineProviderContext())
        XCTAssertEqual(entry.state, .stale)
        XCTAssertEqual(entry.snapshot?.cpuPercent, 42)
    }

    /// When the reader returns `nil` (fresh install or unprovisioned App
    /// Group), the entry must be `.placeholder` and have no snapshot.
    func testGetTimelineReturnsPlaceholderWhenReaderReturnsNil() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = WidgetSnapshotProvider(
            reader: StubSnapshotReader(snapshot: nil),
            now: { now }
        )

        let entry = waitForEntry(from: provider, in: TimelineProviderContext())
        XCTAssertEqual(entry.state, .placeholder)
        XCTAssertNil(entry.snapshot)
        XCTAssertEqual(entry.date, now)
    }

    /// Reader errors must downgrade to `.placeholder`. The provider must
    /// never throw — a thrown error would crash the widget extension.
    func testGetTimelineHandlesReaderErrorsByReturningPlaceholder() {
        struct ReaderFailure: Error {}
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = WidgetSnapshotProvider(
            reader: StubSnapshotReader(snapshot: nil, error: ReaderFailure()),
            now: { now }
        )

        let entry = waitForEntry(from: provider, in: TimelineProviderContext())
        XCTAssertEqual(entry.state, .placeholder)
        XCTAssertNil(entry.snapshot)
    }
}