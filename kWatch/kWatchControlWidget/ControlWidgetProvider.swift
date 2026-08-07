//
//  ControlWidgetProvider.swift
//  kWatchControlWidget
//
//  `TimelineProvider` for the compact Control Widget gauge. Reads the same
//  `SharedSnapshot` JSON from the App Group as the full System Status widget.
//
//  This file defines its own `SnapshotReading` boundary and reader types so
//  the target has no compile-time dependency on `kWatchWidget/WidgetSnapshotProvider.swift`.
//

import Foundation
import WidgetKit

// MARK: - Reader boundary

/// Boundary protocol for reading a `SharedSnapshot` from the App Group.
///
/// Mirrors the protocol from the System Status widget. Tests inject
/// ``ControlStubSnapshotReader`` so the provider can be exercised deterministically.
public protocol ControlSnapshotReading: Sendable {
    /// Returns the most recent snapshot, or `nil` if none has been written.
    func read() throws -> SharedSnapshot?
}

/// Reads the live snapshot from the App Group container.
public struct ControlLiveSnapshotReader: ControlSnapshotReading {
    public init() {}

    public func read() throws -> SharedSnapshot? {
        guard let directory = AppGroupConfiguration.snapshotDirectory() else {
            return nil
        }
        return try SnapshotWriter(directory: directory).read()
    }
}

/// Test double. `snapshot == nil` simulates a fresh install with no data.
public final class ControlStubSnapshotReader: ControlSnapshotReading, @unchecked Sendable {
    private let snapshot: SharedSnapshot?
    private let error: Error?

    public init(snapshot: SharedSnapshot? = nil, error: Error? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    public func read() throws -> SharedSnapshot? {
        if let error { throw error }
        return snapshot
    }
}

// MARK: - Provider

/// Provides a single 60-second timeline for the Control Widget.
///
/// The provider distinguishes three states:
///
/// - `.placeholder` -- the App Group has no snapshot yet, the reader threw, or
///   the App Group is unprovisioned.
/// - `.live` -- a snapshot exists and is fresh (within the staleness threshold).
/// - `.stale` -- a snapshot exists but is older than the freshness threshold.
///   Views overlay a "Stale" badge so users know the data may be outdated.
public struct ControlWidgetProvider: TimelineProvider, Sendable {
    /// Reader boundary. Injected so tests can swap in `ControlStubSnapshotReader`.
    public let reader: any ControlSnapshotReading

    /// Clock seam so tests can produce deterministic freshness comparisons.
    /// Production uses `Date()`; tests pass a closure that returns a fixed date.
    public let now: @Sendable () -> Date

    public init(
        reader: any ControlSnapshotReading = ControlLiveSnapshotReader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.now = now
    }

    /// Placeholder shown while the system is preparing the widget.
    public func placeholder(in context: TimelineProviderContext) -> ControlWidgetEntry {
        ControlWidgetEntry(date: now(), snapshot: nil, state: .placeholder)
    }

    /// Snapshot for the widget gallery and quick-look. Returns a placeholder
    /// to avoid reading the App Group during configuration.
    public func getSnapshot(in context: TimelineProviderContext, completion: @escaping (ControlWidgetEntry) -> Void) {
        completion(buildEntry(snapshot: nil))
    }

    /// The real timeline. Reads the App Group, classifies freshness, and
    /// requests a refresh every 60 seconds.
    public func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<ControlWidgetEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Date(timeIntervalSinceNow: 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: - Helpers

    /// Reads the snapshot via the reader and classifies it. Never throws --
    /// any reader error downgrades the entry to `.placeholder`.
    private func readEntry() -> ControlWidgetEntry {
        do {
            guard let snapshot = try reader.read() else {
                return buildEntry(snapshot: nil)
            }
            return buildEntry(snapshot: snapshot)
        } catch {
            return buildEntry(snapshot: nil)
        }
    }

    /// Classifies the snapshot against the staleness threshold and returns
    /// the appropriate entry.
    private func buildEntry(snapshot: SharedSnapshot?) -> ControlWidgetEntry {
        let currentDate = now()
        guard let snapshot else {
            return ControlWidgetEntry(date: currentDate, snapshot: nil, state: .placeholder)
        }
        let age = currentDate.timeIntervalSince(snapshot.timestamp)
        let state: ControlWidgetState = age > SharedSnapshot.stalenessThreshold ? .stale : .live
        return ControlWidgetEntry(date: currentDate, snapshot: snapshot, state: state)
    }
}
