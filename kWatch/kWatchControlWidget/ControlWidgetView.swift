//
//  ControlWidgetView.swift
//  kWatchControlWidget
//
//  Compact gauge-style SwiftUI view for the `.systemSmall` Control Widget.
//  Renders two ring gauges -- CPU and Memory -- side by side in a minimal
//  layout that fits the 154x154pt small widget canvas on macOS.
//

import SwiftUI
import WidgetKit

// MARK: - Entry View

/// Top-level entry view that dispatches based on widget state.
public struct ControlWidgetView: View {
    public let entry: ControlWidgetEntry

    public init(entry: ControlWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        switch entry.state {
        case .placeholder:
            PlaceholderView()
        case .live, .stale:
            GaugeGridView(snapshot: entry.snapshot, stale: entry.state == .stale)
        }
    }
}

// MARK: - Gauge Grid (Live / Stale)

/// Two circular gauges side by side -- CPU on the left, Memory on the right.
struct GaugeGridView: View {
    let snapshot: SharedSnapshot?
    let stale: Bool

    var body: some View {
        HStack(spacing: 10) {
            GaugeRing(
                label: String(localized: "CPU"),
                percent: snapshot?.cpuPercent ?? 0,
                available: snapshot?.cpuAvailable ?? false,
                color: cpuColor
            )
            GaugeRing(
                label: String(localized: "MEM"),
                percent: snapshot?.memoryPercent ?? 0,
                available: snapshot?.memoryAvailable ?? false,
                color: memColor
            )
        }
        .padding(8)
        .overlay(alignment: .topTrailing) {
            if stale {
                Text(String(localized: "Stale"))
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
    }

    /// Adaptive color based on CPU utilization.
    private var cpuColor: Color {
        guard let percent = snapshot?.cpuPercent, snapshot?.cpuAvailable == true else {
            return .gray
        }
        if percent < 60 { return .green }
        if percent < 85 { return .orange }
        return .red
    }

    /// Adaptive color based on memory utilization.
    private var memColor: Color {
        guard let percent = snapshot?.memoryPercent, snapshot?.memoryAvailable == true else {
            return .gray
        }
        if percent < 70 { return .green }
        if percent < 85 { return .orange }
        return .red
    }
}

// MARK: - Single Gauge Ring

/// A circular gauge that fills an arc proportional to `percent`.
/// When the metric is unavailable the ring shows an "N/A" label instead.
struct GaugeRing: View {
    let label: String
    let percent: Double
    let available: Bool
    let color: Color

    /// Track (background) arc: nearly a full circle.
    private let trackFraction: Double = 0.75
    /// The arc starts at the bottom-left (225 degrees on the unit circle).
    private let startAngle: Angle = .degrees(135)

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background track
                Circle()
                    .trim(from: 0, to: trackFraction)
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(startAngle)

                // Filled arc
                Circle()
                    .trim(from: 0, to: available ? trackFraction * min(percent / 100.0, 1.0) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(startAngle)
                    .animation(.easeInOut(duration: 0.4), value: percent)

                // Center value
                if available {
                    Text(String(format: "%.0f", percent))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        + Text("%")
                            .font(.system(.caption2, design: .rounded))
                } else {
                    Text(String(localized: "N/A"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)

            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Placeholder

/// Shown when no snapshot data is available yet.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.medium")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("kWatch")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Open to start"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
