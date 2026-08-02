import SwiftUI
import Charts
import DesignSystem

/// A Swift Charts trend view that renders the supplied `ChartPoint` series
/// as a line with a gradient area fill and time/numeric axes.
///
/// This view has **no repository access, no formatting logic, and no side
/// effects**. It auto-scales to the min/max of the data and spaces points
/// evenly along the x-axis.
///
/// Uses Swift Charts, which ships with the macOS 13 SDK — no deployment
/// target change is required.
public struct TrendChart: View {
    public let points: [ChartPoint]
    public let lineColor: Color

    public init(points: [ChartPoint], lineColor: Color = .brandPrimary) {
        self.points = points
        self.lineColor = lineColor
    }

    public var body: some View {
        Chart(points) { point in
            // The area must be declared before the line so the line draws
            // on top of the fill instead of being washed out.
            AreaMark(
                x: .value("Time", point.date),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [lineColor.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.date),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(lineColor)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.separatorColor)
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.separatorColor)
                AxisValueLabel()
            }
        }
    }
}

// MARK: - Preview

struct TrendChart_Data_Previews: PreviewProvider {
    static var previews: some View {
        let now = Date()
        let points = (0..<50).map { i in
            ChartPoint(
                date: now.addingTimeInterval(Double(i - 49) * 60),
                value: Double.random(in: 20...90)
            )
        }
        TrendChart(
            points: points,
            lineColor: .blue
        )
        .frame(height: 200)
        .padding()
    }
}

struct TrendChart_Empty_Previews: PreviewProvider {
    static var previews: some View {
        TrendChart(points: [])
            .frame(height: 200)
            .padding()
    }
}
