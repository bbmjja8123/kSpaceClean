//
//  WidgetEntry.swift
//  kWatchWidget
//
//  The single timeline entry type the widget renders. Snapshots are passed
//  through opaquely so that views never touch Core Data or any other
//  process-local state.
//

import Foundation
import WidgetKit

/// State the widget renders. Distinguishes the three meaningful conditions
/// a widget timeline can be in:
///
/// - `placeholder`: no snapshot has ever been written (or the App Group is
///   unprovisioned). Views show a prompt to open kWatch.
/// - `live`: a snapshot was read successfully and is fresh (≤ 30 seconds old).
/// - `stale`: a snapshot exists but is older than the freshness threshold. The
///   data is shown with a "Stale" badge so users know it is no longer current.
public enum WidgetState: String, Codable, Sendable, Equatable {
    case placeholder
    case live
    case stale
}

/// A single timeline entry produced by ``WidgetSnapshotProvider``.
///
/// `snapshot` is optional because the widget can be asked for a placeholder
/// before any data has been written to the App Group. `state` is the
/// authoritative hint for view rendering — callers should branch on `state`
/// rather than recomputing freshness from `snapshot.timestamp`.
public struct SystemStatusEntry: TimelineEntry, Sendable, Equatable {
    public let date: Date
    public let snapshot: SharedSnapshot?
    public let state: WidgetState

    public init(date: Date, snapshot: SharedSnapshot?, state: WidgetState) {
        self.date = date
        self.snapshot = snapshot
        self.state = state
    }
}