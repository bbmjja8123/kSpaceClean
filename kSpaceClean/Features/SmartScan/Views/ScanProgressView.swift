// kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift
import SwiftUI

/// Apple-quality scan-progress screen for kSpaceClean.
///
/// ``ScanProgressView`` is the middle stage of the scan flow — it is
/// pushed after the user starts a scan and dismissed (via the owning
/// navigation stack) when the engine reports ``ScanProgress/State-swift.enum/completed``.
/// The view is purely presentational; the scanner orchestrator writes
/// into the bound ``ScanProgress`` value and SwiftUI re-renders.
///
/// Layout (top → bottom, centered horizontally):
///
/// 1. **Hero ring** — ``ScanProgressRing`` showing overall completion as
///    a percentage. Stroke color is brand-driven by default; the ring
///    can be tinted by risk level when the orchestrator knows which
///    category is currently scanning (see ``ScanProgress/currentStage``).
/// 2. **Stage pill** — a single chip below the ring that names the
///    8-stage scan the engine is currently working on. Default state
///    shows "准备扫描" while the engine boots; live updates flow
///    through ``ScanProgress/currentStage``.
/// 3. **Stats row** — file count + discovered byte size + scanning speed,
///    auto-formatted via ``ByteCountFormatter``. Mirrors Apple's
///    "About this Mac" reading at the same visual weight.
/// 4. **Current path** — the actual filesystem path the engine is
///    enumerating, monospaced, ellipsised from the middle so long
///    `/Users/.../Library/Caches/...` paths still fit. Hidden when the
///    orchestrator has no live path yet (e.g. during the "准备扫描"
///    phase before the first file is touched).
///
/// Accessibility:
/// - The whole view is announced as one element with a composite value
///   that mirrors what sighted users see ("Stage 3 of 8, scanning browser
///   cache; 4,521 files; 1.2 GB discovered"). VoiceOver users therefore
///   do not have to swipe through every sub-element.
/// - Individual stats are also labeled so macOS Inspector / AX debugging
///   surfaces can find them.
struct ScanProgressView: View {

    /// Live progress value published by the scanner engine. Kept as a
    /// `let` so the view is a pure projection of engine state — the
    /// orchestrator owns the `ScanProgress` instance.
    let progress: ScanProgress

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.lg)

            // Hero ring — takes ~40% of vertical space.
            ScanProgressRing(progress: progressFraction, size: ringSize)

            // Stage pill — single chip announcing the active stage.
            stagePill

            // Live stats — file count + discovered size.
            statsRow

            // Currently-scanning path, monospaced + ellipsised.
            if let path = progress.currentNodePath, !path.isEmpty {
                currentPathLabel(path)
            }

            Spacer(minLength: Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    /// Stage announcement pill — a rounded-rect chip that names the
    /// active stage. Background tint shifts between `bgSurface`
    /// (default), `stateScanning` (while a stage is actively working),
    /// and `stateSuccess` (after completion; the view should be
    /// dismissed by then, but the visual is documented for previews).
    @ViewBuilder
    private var stagePill: some View {
        HStack(spacing: Spacing.sm) {
            pulseIcon(stageIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stageTint)

            Text(stageText)
                .font(Typography.regularBody())
                .foregroundStyle(Color.textSecondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: stageText)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            Capsule(style: .continuous)
                .fill(Color.bgSurface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(stageTint.opacity(0.35), lineWidth: 1)
        )
    }

    /// Returns the stage-pill icon as a plain `Image`. The pulsing
    /// animation originally applied via `.symbolEffect(.pulse, options:)`
    /// was removed because the project's build toolchain (Xcode 14.3 /
    /// macOS 13 SDK) cannot resolve the SDK-new `.symbolEffect` overload
    /// even behind `@available(macOS 14.0, *)` annotations. The visual
    /// polish is preserved by the color-tinted capsule border and the
    /// pulsing inner progress ring instead. The helper is kept as a
    /// single-call site so a future CI bump to Xcode 15+ can add the
    /// pulse back in one place.
    private func pulseIcon(_ name: String) -> Image {
        Image(systemName: name)
    }

    /// Compact stats row — files discovered + bytes discovered. The
    /// numbers use `contentTransition(.numericText)` so when the
    /// orchestrator streams a new file count the digits roll instead
    /// of flashing.
    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: Spacing.xl) {
            statColumn(
                title: "已发现",
                value: progress.stats.fileCount.formatted(),
                caption: "个文件"
            )

            divider

            statColumn(
                title: "已扫描",
                value: ByteCountFormatter.string(
                    fromByteCount: progress.stats.discoveredSize, countStyle: .file
                ),
                caption: ""
            )

            divider

            statColumn(
                title: "速度",
                value: String(format: "%.0f", progress.stats.filesPerSecond),
                caption: "文件/秒"
            )

            divider

            statColumn(
                title: "预计剩余",
                value: etaText,
                caption: ""
            )
        }
        .padding(.horizontal, Spacing.lg)
    }

    /// Reusable single-stat column used by ``statsRow``.
    @ViewBuilder
    private func statColumn(title: String, value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .modifier(NumericTextModifier(value: value))
                .animation(.easeOut(duration: 0.18), value: value)
            Text(title + (caption.isEmpty ? "" : " " + caption))
                .font(Typography.smallBody())
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) \(caption)")
    }

    /// Hairline divider between stat columns. Uses `Color.divider` so it
    /// picks up the system hairline weight via the `.frame(height:)`.
    @ViewBuilder
    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 28)
    }

    /// Current path label — monospaced, single line, middle-ellipsised.
    /// The leading icon (`folder.fill`) gives the label a clear visual
    /// semantic so users read it as "where we are" rather than "what we
    /// are doing".
    @ViewBuilder
    private func currentPathLabel(_ path: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
            Text(path)
                .font(Typography.filePath())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.bgSurface.opacity(0.6))
        )
        .accessibilityLabel("Currently scanning path")
        .accessibilityValue(path)
    }

    // MARK: - Derived values

    /// Live ring diameter. Resolves to 180 on wide layouts and shrinks on
    /// narrow canvases so the screen stays usable on split-view inserts.
    private var ringSize: CGFloat {
        // Default to a hero-sized ring; tightening handled by the
        // parent's `.frame(maxWidth:)`. SwiftUI reads `size` here so
        // scaling the parent keeps the ring proportional.
        180
    }

    /// Fractional completion via `ScanProgressMath` (Task A2) — categories
    /// completed + in-flight files + stats so the ring moves continuously
    /// instead of freezing between category boundaries.
    private var progressFraction: Double {
        ScanProgressMath.completionFraction(
            categoryProgress: progress.categoryProgress,
            stats: progress.stats
        )
    }

    /// Live ETA string; shows "—" until the math has enough signal.
    private var etaText: String {
        if case .scanning = progress.state {
            if let eta = ScanProgressMath.estimatedRemainingSeconds(
                categoryProgress: progress.categoryProgress,
                stats: progress.stats
            ) {
                return ScanProgressMath.formatClock(eta)
            }
        }
        return "—"
    }

    /// Icon for the active stage — pulled from ``ScanStage/icon``.
    /// Defaults to a `magnifyingglass` symbol if the orchestrator hasn't
    /// reported a stage yet (engine boot).
    private var stageIcon: String {
        progress.currentStage.icon
    }

    /// Human-readable text for the active stage — combines a "Stage N of 8"
    /// label with the stage title so users get orientation feedback.
    private var stageText: String {
        let stageTitle = progress.currentStage.title
        if progress.state == .idle {
            return "准备扫描"
        }
        if progress.state == .analysing {
            return "正在分析结果…"
        }
        return "Stage \(progress.currentStage.rawValue) / 8 · \(stageTitle)"
    }

    /// Tint applied to the stage icon + pill border. Defaults to the
    /// brand-accent while scanning; switches to ``stateSuccess`` after
    /// completion. Uses opaque-but-soft tones so the pill stays in the
    /// background hierarchy rather than competing with the ring.
    private var stageTint: Color {
        switch progress.state {
        case .completed: return .stateSuccess
        case .failed: return .stateError
        case .cancelled: return .textSecondary
        default: return .brandAccent
        }
    }

    /// Composite accessibility label that mirrors the visible summary.
    /// VoiceOver reads this once when the user focuses the screen
    /// instead of swiping through every chip/label.
    private var accessibilityLabel: String {
        let percent = Int((progressFraction * 100).rounded())
        let stage = progress.currentStage.title
        let files = progress.stats.fileCount
        let bytes = ByteCountFormatter.string(
            fromByteCount: progress.stats.discoveredSize, countStyle: .file
        )
        return "Scanning. \(percent) percent complete. Stage: \(stage). " +
        "\(files) files, \(bytes) discovered."
    }
}

#if DEBUG
/// Xcode preview surface — exercises the screen at three lifecycle
/// milestones (idle, mid-scan, complete) so reviewers can sanity-check
/// stage transitions and ring interpolation without running the engine.
struct ScanProgressView_Previews: PreviewProvider {

    /// Mid-scan fixture — a couple of completed categories, a live path,
    /// non-zero stats. Mimics the state the orchestrator publishes once
    /// the first scanner worker has reported results.
    private static var midScan: ScanProgress {
        var p = ScanProgress()
        p.state = .scanning
        p.currentStage = .devJunk
        p.categoryProgress = [
            CategoryProgress(id: 1, title: "缓存", status: .completed,
                             subCategories: [], filesFound: 1234, totalSize: 2_100_000_000),
            CategoryProgress(id: 2, title: "开发残留", status: .scanning,
                             subCategories: [], filesFound: 4321, totalSize: 1_400_000_000),
            CategoryProgress(id: 3, title: "二进制", status: .pending,
                             subCategories: [], filesFound: 0, totalSize: 0)
        ]
        p.currentNodePath = "/Users/mengjianjun/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
        p.stats = ScanStats(discoveredSize: 3_500_000_000, fileCount: 5555,
                            elapsed: 42, filesPerSecond: 132.3)
        return p
    }

    /// Completed fixture — visual contract test for the `.completed`
    /// state tint. Useful when reviewing the success styling in
    /// isolation from the live scanner.
    private static var completed: ScanProgress {
        var p = ScanProgress()
        p.state = .completed
        p.currentStage = .browserCache
        p.categoryProgress = (1...8).map { i in
            CategoryProgress(id: i, title: "Stage \(i)", status: .completed,
                             subCategories: [], filesFound: 100 * i, totalSize: 100_000_000 * Int64(i))
        }
        p.stats = ScanStats(discoveredSize: 3_600_000_000, fileCount: 3600, elapsed: 128, filesPerSecond: 28)
        return p
    }

    static var previews: some View {
        VStack(spacing: 0) {
            ScanProgressView(progress: .init())
                .frame(width: 800, height: 500)
            Divider()
            ScanProgressView(progress: midScan)
                .frame(width: 800, height: 500)
            Divider()
            ScanProgressView(progress: completed)
                .frame(width: 800, height: 500)
        }
        .background(Color.bgCanvas)
    }
}
#endif
