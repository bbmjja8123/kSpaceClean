import SwiftUI

// MARK: - Card Style

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Color.bgSecondary)
            .cornerRadius(12)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 4)
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }
}

// MARK: - Brand Gradient Background

struct BrandGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.bgPrimary,
                        Color.bgSecondary
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

extension View {
    func brandBackground() -> some View {
        modifier(BrandGradientBackground())
    }
}

// MARK: - Blur Card (for Pro locking, etc.)

struct BlurCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
    }
}

extension View {
    func blurCardStyle() -> some View {
        modifier(BlurCardStyle())
    }
}
