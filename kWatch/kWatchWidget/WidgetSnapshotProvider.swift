//
//  WidgetSnapshotProvider.swift
//  kWatchWidget
//
//  `TimelineProvider` implementation that reads the cross-process JSON
//  snapshot written by the main app into the shared App Group container.
//
//  The provider depends on a `SnapshotReading` boundary so that tests can
//  inject canned data without touching the App Group or the file system.
//

import Foundation
import WidgetKit

// MARK: - Reader boundary

/// Boundary protocol for reading a `SharedSnapshot` from the App Group.
///
/// The widget never reads Core Data or private APIs; it only reads the JSON
/// snapshot that the main app wrote atomically. Tests inject
/// ``StubSnapshotReader`` so the provider can be exercised deterministically.
public protocol SnapshotReading: Sendable {
    /// Returns the most recent snapshot, or `nil` if none has been written.
    /// Errors must be surfaced so the provider can downgrade to a placeholder
    /// entry instead of crashing the extension.
    func read() throws -> SharedSnapshot?
}

/// Reads the live snapshot from the App Group container.
///
/// Falls back to returning `nil` (which the provider treats as `.placeholder`)
/// when the App Group has not been provisioned (e.g. unsigned dev builds).
public struct LiveSnapshotReader: SnapshotReading {
    public init() {}

    public func read() throws -> SharedSnapshot? {
        // Resolve the directory lazily; the App Group container may not exist
        // until the system has registered the entitlement.
        guard let directory = AppGroupConfiguration.snapshotDirectory() else {
            return nil
        }
        // Errors propagate to the provider, which downgrades them to a
        // placeholder entry. We never throw out of the extension on purpose.
        return try SnapshotWriter(directory: directory).read()
    }
}

/// Test double. `snapshot == nil` simulates a fresh install with no data.
public final class StubSnapshotReader: SnapshotReading, @unchecked Sendable {
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

/// Provides a single 60-second timeline for the System Status widget.
///
/// The provider distinguishes three states:
///
/// - `.placeholder` — the App Group has no snapshot yet, the reader threw, or
///   the App Group is unprovisioned.
/// - `.live` — the snapshot exists and is at most
///   `SharedSnapshot.stalenessThreshold` seconds old.
/// - `.stale` — the snapshot exists but is older than the freshness threshold.
///   Views overlay a "Stale" badge so users know to open kWatch for fresh
///   numbers.
public struct WidgetSnapshotProvider: TimelineProvider, Sendable {
    /// Reader boundary. Injected so tests can swap in `StubSnapshotReader`.
    public let reader: any SnapshotReading

    /// Clock seam so tests can produce deterministic freshness comparisons.
    /// Production uses `Date()`; tests pass a closure that returns a fixed
    /// `Date`.
    public let now: @Sendable () -> Date

    public init(
        reader: any SnapshotReading = LiveSnapshotReader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.now = now
    }

    /// Placeholder shown while the system is preparing the widget (e.g.
    /// during configuration, or when no snapshot exists yet).
    public func placeholder(in context: TimelineProviderContext) -> SystemStatusEntry {
        SystemStatusEntry(date: now(), snapshot: nil, state: .placeholder)
    }

    /// Snapshot for the widget gallery and quick-look. We always return a
    /// `.placeholder` entry here — we never read the App Group for the
    /// gallery because the snapshot may be from a different user account.
    public func getSnapshot(in context: TimelineProviderContext, completion: @escaping (SystemStatusEntry) -> Void) {
        completion(buildEntry(snapshot: nil))
    }

    /// The real timeline. Reads the App Group, classifies freshness, and asks
    /// the system to refresh every 60 seconds. The system may coalesce or
    /// delay the refresh; 60s is the upper bound on data staleness.
    public func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<SystemStatusEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Date(timeIntervalSinceNow: 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: - Helpers

    /// Reads the snapshot via the reader and classifies it. Never throws —
    /// any reader error downgrades the entry to `.placeholder` so the
    /// widget can never crash the extension.
    private func readEntry() -> SystemStatusEntry {
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
    private func buildEntry(snapshot: SharedSnapshot?) -> SystemStatusEntry {
        let currentDate = now()
        guard let snapshot else {
            return SystemStatusEntry(date: currentDate, snapshot: nil, state: .placeholder)
        }
        let age = currentDate.timeIntervalSince(snapshot.timestamp)
        let state: WidgetState = age > SharedSnapshot.stalenessThreshold ? .stale : .live
        return SystemStatusEntry(date: currentDate, snapshot: snapshot, state: state)
    }
}