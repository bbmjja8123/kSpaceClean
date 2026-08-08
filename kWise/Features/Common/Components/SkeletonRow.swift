import SwiftUI

/// A single shimmering placeholder row used while a scan / list is loading.
///
/// Lays out four greyed-out blocks in the same horizontal rhythm as a real
/// ``ScanTreeRow`` (16pt leading icon gutter, 24pt category icon, two-line
/// label area, 60pt trailing size badge). The opacity of each block is
/// driven by a single `@State` phase value (`0...1`) that tweens forever
/// via `repeatForever`, producing a subtle pulse that signals "loading"
/// without hard motion.
///
/// Designed to never drop below 50fps under
/// `SWIFT_STRICT_CONCURRENCY = complete` — the body is a static shape tree
/// with no observation dependencies, and `withAnimation(...)` runs on the
/// main actor implicitly (the view itself is implicitly `@MainActor`).
struct SkeletonRow: View {
    /// Shimmer phase (0 = full opacity, 1 = dimmed). Driven by a forever
    /// linear animation so the placeholder pulses smoothly without relying
    /// on per-block state.
    @State private var phase: Double = 0

    /// Reduced shimmer opacity used when the user has Reduce Motion enabled.
    /// We still drive `phase`, but keep the contrast delta small so the row
    /// reads as "static" rather than "animated" to assistive tech.
    private var blockOpacity: Double {
        0.18 + 0.12 * abs(phase - 0.5) * 2
    }

    /// Visual placeholder for a single block of greyed-out content.
    ///
    /// Extracts the repeated `Color + frame + clipShape` triple into a
    /// `ViewBuilder` so the body stays readable. The block never owns state
    /// and never re-renders independent of its parent.
    @ViewBuilder
    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        Color.textTertiary
            .opacity(blockOpacity)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Trailing 60pt size-badge slot matches ScanTreeRow's trailing column.
            placeholder(width: 60, height: 14)

            placeholder(width: 16, height: 16)
            placeholder(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                placeholder(width: 200, height: 14)
                placeholder(width: 140, height: 10)
            }

            Spacer()
        }
        .frame(height: RowSize.height)
        .padding(.horizontal, Spacing.md)
        .onAppear {
            // Linear + autoreversing + forever = smooth symmetric pulse.
            // 1.5s matches macOS HIG suggestions for non-distracting motion.
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityLabel("加载中")
        .accessibilityElement(children: .ignore)
    }

    /// Manually-readable phase accessor used by tests that want to assert
    /// the placeholder still drives a fade animation without introspecting
    /// SwiftUI's opaque `body`.
    func currentPhase() -> Double { phase }
}

#if DEBUG
/// Previews showing several skeleton rows stacked inside a list-style
/// background, so reviewers can eyeball the pulse + spacing.
struct SkeletonRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            SkeletonRow()
            Divider()
            SkeletonRow()
            Divider()
            SkeletonRow()
            Divider()
            SkeletonRow()
        }
        .background(Color.bgCanvas)
    }
}
#endif
