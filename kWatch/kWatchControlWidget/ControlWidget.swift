//
//  ControlWidget.swift
//  kWatchControlWidget
//
//  The kWatch Control Widget declaration. Uses `StaticConfiguration` with
//  `.systemSmall` only -- no Control Center APIs (absent in macOS 13.3 SDK).
//  The widget renders a compact dual-gauge view of CPU and Memory.
//

import SwiftUI
import WidgetKit

/// The kWatch Control Widget.
///
/// A compact gauge-style widget showing CPU and Memory utilization in a
/// `.systemSmall` family. Uses `StaticConfiguration` so the widget is
/// available on macOS 13+; no Control Center APIs are referenced because
/// they do not exist in the macOS 13.3 SDK.
public struct ControlWidget: Widget {
    /// Stable kind identifier for this widget.
    public let kind: String = "kWatchControlWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ControlWidgetProvider()) { entry in
            ControlWidgetView(entry: entry)
        }
        .configurationDisplayName("CPU & Memory")
        .description("Compact CPU and memory gauges at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
