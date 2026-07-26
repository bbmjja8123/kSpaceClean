import SwiftUI

/// A minimal line chart that draws only the supplied data points.
///
/// Pure presentation: it holds no monitoring state and produces no side
/// effects. The caller supplies a fixed-size window of values (e.g. the
/// most recent CPU samples) and the chart auto-scales to their range.
public struct MiniTrendChart: View {
    public let values: [Double]
    public let color: Color

    public init(values: [Double], color: Color = .accentColor) {
        self.values = values
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maxValue = values.max() ?? 1
            let minValue = values.min() ?? 0
            let range = max(maxValue - minValue, 0.0001)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((value - minValue) / range))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}
