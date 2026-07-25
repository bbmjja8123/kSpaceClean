import SwiftUI

public enum AppShadow {
    public static let sm = Shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    public static let md = Shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    public static let lg = Shadow(color: .black.opacity(0.5), radius: 24, y: 8)

    public struct Shadow {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat

        public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}

public extension View {
    func appShadow(_ shadow: AppShadow.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
