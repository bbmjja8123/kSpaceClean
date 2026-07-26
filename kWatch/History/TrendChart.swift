import SwiftUI

/// A pure-SwiftUI line chart that renders the supplied `ChartPoint` series.
///
/// This view has **no repository access, no formatting logic, and no side
/// effects**. It auto-scales to the min/max of the data and spaces points
/// evenly along the x-axis.
///
/// Uses `Canvas` (available since macOS 12) to avoid a dependency on
/// Swift Charts, keeping the deployment target at macOS 13.
public struct TrendChart: View {
    public let points: [ChartPoint]
    public let lineColor: Color
    public let fillColor: Color?

    public init(
        points: [ChartPoint],
        lineColor: Color = .accentColor,
        fillColor: Color? = nil
    ) {
        self.points = points
        self.lineColor = lineColor
        self.fillColor = fillColor
    }

    public var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            let values = points.map(\.value)
            let maxValue = values.max() ?? 1
            let minValue = values.min() ?? 0
            let range = max(maxValue - minValue, 0.0001)

            // Build the line path.
            var linePath = Path()
            for (index, point) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let y = size.height * (1 - CGFloat((point.value - minValue) / range))
                let pt = CGPoint(x: x, y: y)
                if index == 0 {
                    linePath.move(to: pt)
                } else {
                    linePath.addLine(to: pt)
                }
            }

            // Optional fill beneath the line.
            if let fillColor {
                var fillPath = linePath
                if let last = points.last {
                    let lastX = size.width
                    let lastY = size.height * (1 - CGFloat((last.value - minValue) / range))
                    fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
                    fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                    fillPath.closeSubpath()
                }
                context.fill(fillPath, with: .color(fillColor))
            }

            context.stroke(linePath, with: .color(lineColor), lineWidth: 1.5)
        }
    }
}

// MARK: - Preview

#Preview("TrendChart with data") {
    let points = (0..<50).map { i in
        ChartPoint(
            date: Date(timeIntervalSinceNow: Double(-i * 60)),
            value: Double.random(in: 20...90)
        )
    }
    TrendChart(
        points: points,
        lineColor: .blue,
        fillColor: .blue.opacity(0.1)
    )
    .frame(height: 200)
    .padding()
}

#Preview("TrendChart empty") {
    TrendChart(points: [])
        .frame(height: 200)
        .padding()
}
