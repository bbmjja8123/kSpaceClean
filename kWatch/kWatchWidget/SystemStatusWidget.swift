//
//  SystemStatusWidget.swift
//  kWatchWidget
//
//  The System Status widget declaration. Hands off to `SystemStatusWidgetView`
//  for rendering. Uses `StaticConfiguration` so the widget is available on
//  macOS 13; interactive `Button(intent:)` controls inside the view are
//  guarded with `#available(macOS 14.0, *)`.
//

import SwiftUI
import WidgetKit

/// The kWatch System Status widget.
///
/// Renders aggregate CPU / memory / disk / network metrics in small, medium,
/// and large families. The widget reads only `SharedSnapshot` — never Core
/// Data, never private APIs — so it remains safe to run when the main app
/// is not running.
///
/// On macOS 14, the view adds a deep-link `Button(intent:)` that surfaces
/// `OpenDashboardIntent`. The intent itself is a stub; the main app's
/// intents module (Task 21) will flesh it out.
public struct SystemStatusWidget: Widget {
    public let kind: String = "kWatchSystemStatus"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            SystemStatusWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "System Status"))
        .description(String(localized: "Live CPU, memory, disk, and network at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}