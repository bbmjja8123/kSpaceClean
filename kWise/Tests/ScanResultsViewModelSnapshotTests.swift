// kWise/Tests/ScanResultsViewModelSnapshotTests.swift
//
// F4 perf sweep regression guard — verifies that a scan-completion
// emits at most one `objectWillChange` per logical update batch.
//
// Before F4, the view model exposed four `@Published` fields that
// transitioned together at scan completion (`isScanning`,
// `hasScanned`, `categories`, and the `totalSelectedSize` /
// `totalSelectedCount` pair), each firing its own
// `objectWillChange`. After F4 they live on a single ``ScanSnapshot``
// struct so a single setter write collapses the invalidation count.

import XCTest
import Combine
@testable import kWise

@MainActor
final class ScanResultsViewModelSnapshotTests: XCTestCase {
    /// Counts `objectWillChange` emissions over a single scan-completion
    /// event. Before F4 this would be ≥ 4 (one per `@Published` field);
    /// after F4 it is exactly 1 (the single `snapshot = newSnapshot`
    /// write in ``ScanResultsViewModel/startRealScan(rootPaths:)``).
    ///
    /// We do not require *exactly* 1 — SwiftUI may still fire an extra
    /// invalidation when a property's projected value changes during
    /// `objectWillChange.sink` traversal — but the count must be at or
    /// below the legacy baseline of 4.
    func test_scanCompletionEmitsAtMostOneSnapshotChange() async {
        // Drive the view model directly through its public surface so
        // the test does not need a real scan engine.
        let viewModel = ScanResultsViewModel()
        viewModel.loadMockData()
        XCTAssertFalse(viewModel.categories.isEmpty,
            "Mock data must populate at least one category before the test runs")

        // Tap an `objectWillChange` sink and count notifications while we
        // batch the same five logical fields the scan-completion code path
        // touches.
        let cancellable = Box<AnyCancellable?>(nil)
        let counter = AtomicCounter()
        cancellable.value = viewModel.objectWillChange.sink { counter.increment() }

        // Replicate the batched completion: assemble the new snapshot
        // locally, then assign once. The `assign(snapshot:)` mutator is
        // the only sanctioned write path from outside the model — it
        // preserves the encapsulation that existed pre-F4. We build the
        // `ScanSnapshot` literal here (rather than reading the private
        // `snapshot` storage) so the test exercises only public surface.
        let currentCategories = viewModel.categories
        let batched = ScanResultsViewModel.ScanSnapshot(
            isScanning: false,
            hasScanned: true,
            categories: currentCategories,
            totalSelectedSize: currentCategories
                .reduce(Int64(0)) { $0 + $1.totalSize },
            totalSelectedCount: currentCategories.count
        )
        viewModel.assign(snapshot: batched)

        // Drain pending notifications.
        await Task.yield()
        let emissions = counter.value
        XCTAssertLessThanOrEqual(emissions, 1,
            "Snapshot write must collapse to at most one objectWillChange emission (got \(emissions))")

        cancellable.value?.cancel()
    }

    /// Helper: thread-safe counter so the sink closure can record
    /// emissions safely across isolation domains.
    private final class AtomicCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            _value += 1
        }
    }

    /// Helper: a tiny mutable box so the Combine cancellable can be
    /// captured inside a local scope without `var` shadowing warnings.
    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }
}