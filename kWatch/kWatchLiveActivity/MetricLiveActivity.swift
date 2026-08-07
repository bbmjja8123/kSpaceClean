//
//  MetricLiveActivity.swift
//  kWatchLiveActivity
//
//  --- Xcode integration (developer must perform manually) -----------------
//  1. Add a Widget/Activity Extension target with bundle ID
//     `app.kraftly.kwatch.activity`, deployment target macOS 14.0, and
//     `NSSupportsLiveActivities = YES` in the main app's Info.plist.
//  2. Add SharedSnapshot.swift (and any other shared files) to this target's
//     Compile Sources phase. If this activity is co-hosted in the widget
//     extension, move this activity view into that widget bundle instead.
//  3. Wire Activity<MetricActivityAttributes>.request(attributes:contentState:pushType:)
//     from AppCoordinator or a dedicated LiveActivityCoordinator only on
//     macOS 14+ and only after the user opts in through Preferences.
//  -------------------------------------------------------------------------

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

#if os(macOS)
/// The kWatch Live Activity widget configuration.
public struct MetricLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        if #available(macOS 14.0, *) {
            return ActivityConfiguration(for: MetricActivityAttributes.self) { context in
                MetricLiveActivityView(context: context)
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.center) {
                        MetricLiveActivityView(context: context)
                    }
                } compactLeading: {
                    Text(context.attributes.kindRaw.capitalized.prefix(1))
                } compactTrailing: {
                    MetricValueText(state: context.state)
                } minimal: {
                    MetricValueText(state: context.state)
                }
            }
        }

        return StaticConfiguration(
            kind: "app.kraftly.kwatch.activity.placeholder",
            provider: PlaceholderProvider()
        ) { _ in
            Text(String(localized: "Live Activity requires macOS 14"))
                .font(.caption)
        }
    }
}

@available(macOS 14.0, *)
private struct MetricLiveActivityView: View {
    let context: ActivityViewContext<MetricActivityAttributes>

    var body: some View {
        HStack(spacing: 8) {
            Text(context.attributes.kindRaw.capitalized)
                .font(.headline)
            Spacer(minLength: 4)
            Text(trendArrow(for: context.state.trend))
                .accessibilityLabel(trendLabel(for: context.state.trend))
            MetricValueText(state: context.state)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func trendArrow(for trend: MetricActivityAttributes.ContentState.Trend) -> String {
        switch trend {
        case .up: return "↑"
        case .down: return "↓"
        case .flat: return "→"
        }
    }

    private func trendLabel(for trend: MetricActivityAttributes.ContentState.Trend) -> String {
        switch trend {
        case .up: return String(localized: "Trending up")
        case .down: return String(localized: "Trending down")
        case .flat: return String(localized: "Stable")
        }
    }
}

private struct MetricValueText: View {
    let state: MetricActivityAttributes.ContentState

    var body: some View {
        if state.isAvailable {
            Text(verbatim: String(format: "%.1f\(state.displayUnit)", state.value))
                .monospacedDigit()
        } else {
            Text(String(localized: "Unavailable"))
        }
    }
}

private struct PlaceholderProvider: TimelineProvider {
    typealias Entry = PlaceholderEntry

    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}
#endif // os(macOS)
#endif // canImport(ActivityKit)
