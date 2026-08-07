//
//  ControlWidgetEntry.swift
//  kWatchControlWidget
//
//  Timeline entry for the Control Widget. Defines `ControlWidgetState`
//  locally so the target is self-contained (no dependency on kWatchWidget).
//

import Foundation
import WidgetKit

/// State the widget renders. Distinguishes the three meaningful conditions
/// a widget timeline can be in.
///
/// Mirrors the `WidgetState` enum from the System Status widget for
/// consistency, but is defined locally so the Control Widget target has
/// no compile-time dependency on `kWatchWidget/WidgetEntry.swift`.
public enum ControlWidgetState: String, Codable, Sendable, Equatable {
    case placeholder
    case live
    case stale
}

/// A single timeline entry produced by ``ControlWidgetProvider``.
///
/// `snapshot` is optional because the widget can be asked for a placeholder
/// before any data has been written to the App Group. `state` is the
/// authoritative hint for view rendering.
public struct ControlWidgetEntry: TimelineEntry, Sendable, Equatable {
    public let date: Date
    public let snapshot: SharedSnapshot?
    public let state: ControlWidgetState

    public init(date: Date, snapshot: SharedSnapshot?, state: ControlWidgetState) {
        self.date = date
        self.snapshot = snapshot
        self.state = state
    }
}
