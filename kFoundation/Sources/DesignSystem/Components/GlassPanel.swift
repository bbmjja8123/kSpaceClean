import SwiftUI

public struct GlassPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
