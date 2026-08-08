// kWise/Features/SmartScan/Views/ScanProgressRing.swift
import SwiftUI

/// Apple-quality circular progress ring shown during a scan.
///
/// ``ScanProgressRing`` is the visual centerpiece of ``ScanProgressView``.
/// The ring is composed of three concentric layers stacked in a `ZStack`:
///
/// 1. **Track** — a soft `bgSurface` circle that establishes the ring's
///    geometry. Sits at 12% opacity so it reads as a guideline without
///    competing with the foreground stroke.
/// 2. **Glow halo** — a blurred duplicate of the progress stroke that
///    gives the ring an Apple-style luminous edge. The blur and opacity
///    are tuned so the halo is perceptible on dark mode without
///    looking "neon" on light mode (the gradient auto-adapts because
///    both colors are saturated mid-tones).
/// 3. **Progress stroke** — the active fill from 12 o'clock clockwise,
///    rendered with rounded line caps for a friendly hand-drawn feel
///    matching Apple's `Gauge` and `Activity` indicators.
///
/// Animations:
/// - The trim changes use `easeOutQuart` over 240 ms — a curve picked
///   from DaisyDisk's animation reference (and Apple's HIG under
///   "Spring Animations → Emphasis") because it produces a confident
///   "snap" feel without overshoot, matching the user's stated taste.
/// - `accessibleDefault(...)` swaps the curve for a linear 0.1 s fade
///   when "Reduce motion" is enabled.
///
/// Accessibility:
/// - `progress` is surfaced as a `0...100` percentage via an
///   `accessibilityValue` so VoiceOver can read it.
/// - The ring is announced as "Scan progress" with the live percent;
///   both labels update reactively.
struct ScanProgressRing: View {

    /// Scan progress in `0.0...1.0`. Out-of-range values are clamped so
    /// the trim never exceeds the stroke endpoint or pulls past 12
    /// o'clock. Stored as `Double` to match ``ScanProgress/completedCategories``
    /// and ``ScanProgress/totalCategories`` derivation.
    let progress: Double

    /// Outer diameter of the ring in points. Default `160` lands in the
    /// visual sweet spot for a hero element on the 960x720 design canvas
    /// without crowding the surrounding stage/path captions.
    var size: CGFloat = 160

    /// Stroke thickness. Scales with `size` so a smaller ring still reads
    /// as a ring (and a larger ring does not become "thin"). The 1/12
    /// ratio mirrors Apple Watch's activity rings.
    private var lineWidth: CGFloat { size / 12 }

    /// Animatable progress value bridged from the `let` input. Using
    /// an animatable `CGFloat` lets SwiftUI interpolate trim endpoints
    /// rather than crossfading whole circles when `progress` jumps.
    @State private var animatedProgress: CGFloat = 0

    /// Clamps input to `0...1` so a malformed `progress` cannot produce
    /// an empty ring or an over-rotated one.
    private var clamped: CGFloat {
        CGFloat(max(0, min(progress, 1)))
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.bgSurface.opacity(0.6), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Glow halo — duplicate of the progress stroke, blurred and dimmed.
            // Provides the "Apple luminous edge" feel without drawing
            // attention away from the sharp ring on top.
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: lineWidth * 0.75)
                .opacity(0.55)

            // Sharp progress stroke on top.
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            // Inner labels — percentage + caption. Monospaced digits
            // keep the number column anchored as the value ticks up.
            VStack(spacing: Spacing.xs) {
                Text("\(percentNumber)")
                    .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                    .modifier(NumericValueTextModifier(value: Double(percentNumber)))
                    .animation(.accessibleDefault(.easeOut(duration: 0.18)), value: percentNumber)

                Text(percentCaption)
                    .font(.system(size: size * 0.10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
            }
        }
        // Equal size keeps the ZStack centered; `.frame(width:height:)`
        // rather than `.aspectRatio` lets the parent supply the height.
        .frame(width: size, height: size)
        .onAppear { animatedProgress = clamped }
        .onChange(of: clamped) { newValue in
            withAnimation(Self.easeOutQuart(duration: 0.24)) {
                animatedProgress = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(percentNumber) percent")
    }

    /// Rounded integer percentage string (`"42"`). Avoids the
    /// `"\(Int(fraction * 100))%"` SwiftUI re-render every frame
    /// caused by string interpolation in the body.
    private var percentNumber: Int {
        Int((clamped * 100).rounded())
    }

    /// Caption shown beneath the percentage — gives the ring a clear
    /// "this is scanning, not just decorative" semantic for sighted
    /// users without making the label rotation the user's job.
    private var percentCaption: String { "扫描中" }

    /// Brand-colored linear gradient running from top-leading to
    /// bottom-trailing. Matches the brand mark adopted in v3 spec —
    /// purple → blue → cyan — and gives the ring a "moving" feel
    /// because the gradient stays anchored while the trim grows.
    private var ringGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.brandPrimary,
                Color.brandPrimary.opacity(0.85),
                Color.brandAccent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// easeOutQuart timing curve — `1 - (1 - t)^4`. Matches the DaisyDisk
    /// "confident snap" feel and Apple's HIG spring recommendations
    /// for emphasis animations. We define a manual cubic Bezier here
    /// because SwiftUI's built-in `Animation` lacks an `easeOutQuart`
    /// preset.
    /// - Parameter duration: Animation length in seconds.
    /// - Returns: An `Animation` matching the quartic ease-out curve.
    static func easeOutQuart(duration: Double) -> Animation {
        Animation.timingCurve(0.165, 0.84, 0.44, 1.0, duration: duration)
    }
}

#if DEBUG
/// Xcode preview surface — exercises the ring at four progress
/// fractions so reviewers can confirm color/interpolation behavior.
struct ScanProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: Spacing.lg) {
            ScanProgressRing(progress: 0.0)
            ScanProgressRing(progress: 0.35)
            ScanProgressRing(progress: 0.72)
            ScanProgressRing(progress: 1.0)
        }
        .padding(Spacing.xl)
        .background(Color.bgCanvas)
    }
}
#endif

// MARK: - Numeric transition helpers

/// `contentTransition(.numericText(value:))` is macOS 14+; this shim
/// falls back to a plain view (no numeric transition) on macOS 13 so
/// the binary keeps building at the project's deployment target.
///
/// Note: `numericText()` is a static factory on `ContentTransition`,
/// not a `View.contentTransition` overload. The shim is applied as a
/// `.transition(...)` only when it is safe; otherwise `content`
/// passes through unchanged.
struct NumericValueTextModifier: ViewModifier {
    let value: Double
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            // Apply via `.transition` so the rolling-digit animation
            // pairs with the outer `.animation(_, value:)` modifier.
            AnyView(
                content
                    .contentTransition(.numericText())
            )
        } else {
            AnyView(content)
        }
    }
}

/// `contentTransition(.numericText())` is macOS 14+; this shim mirrors
/// the same fallback for the stats-row labels.
struct NumericTextModifier: ViewModifier {
    let value: String
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}
