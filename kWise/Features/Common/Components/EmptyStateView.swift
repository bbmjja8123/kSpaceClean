import SwiftUI

/// Empty / error state scenarios rendered by ``EmptyStateView``.
///
/// Eight scenarios cover the empty-state surfaces used across
/// `ScanResultsView`, history view, onboarding, and disk-full guards.
/// The first six are "happy-path" empties (first launch, no results,
/// cleanup complete, no history, no FDA, scan failed); the last three are
/// guarded error states (cleanup failed, disk full) plus the FDA permission
/// gate that doubles as an error surface.
///
/// Each scenario binds an SF Symbol icon, a title, a longer help message,
/// and a tint colour drawn from the design-system token palette
/// (see `kWise/Features/Common/DesignSystem/Colors.swift`).
enum EmptyStateScenario {
    /// First-launch welcome — seen only on a brand-new install before any scan.
    case firstLaunch
    /// Scan returned zero cleanable items — the user's Mac is already tidy.
    case noResults
    /// Cleanup action completed successfully — celebratory empty.
    case cleanupComplete
    /// History tab has no entries yet (first 30 days post-install).
    case noHistory
    /// Full Disk Access has not been granted — required for any scan.
    case noFDA
    /// Scan aborted mid-way (file-system error, permission revoked, etc.).
    case scanFailed
    /// One or more files could not be moved to Trash because they were in use.
    case cleanupFailed
    /// Free disk space is below the 1 GB minimum required to perform cleanup.
    case diskFull

    /// SF Symbol rendered for the scenario's centered hero icon.
    var iconName: String {
        switch self {
        case .firstLaunch: return "sparkles"
        case .noResults: return "checkmark.seal.fill"
        case .cleanupComplete: return "checkmark.circle.fill"
        case .noHistory: return "clock.arrow.circlepath"
        case .noFDA: return "lock.shield.fill"
        case .scanFailed: return "exclamationmark.triangle.fill"
        case .cleanupFailed: return "xmark.octagon.fill"
        case .diskFull: return "internaldrive.fill"
        }
    }

    /// Localized title displayed under the icon (large-title typography).
    var title: String {
        switch self {
        case .firstLaunch: return "Mac 存储清理，从这里开始"
        case .noResults: return "Mac 已经干干净净"
        case .cleanupComplete: return "清理完成"
        case .noHistory: return "还没有清理记录"
        case .noFDA: return "需要 Full Disk Access 权限"
        case .scanFailed: return "扫描未完成"
        case .cleanupFailed: return "清理未完成"
        case .diskFull: return "无法清理 · 磁盘空间不足"
        }
    }

    /// Localized helper body text displayed below the title (regular body).
    var message: String {
        switch self {
        case .firstLaunch: return "kWise 会扫描你 Mac 上可以安全清理的文件，给你一个详细列表。"
        case .noResults: return "没有发现可以安全清理的文件。下次扫描建议在 7 天后。"
        case .cleanupComplete: return "你的 Mac 已经被清理干净了。"
        case .noHistory: return "你的第一次清理完成后，30 天内的清理记录会在这里显示。"
        case .noFDA: return "kWise 需要 Full Disk Access 才能扫描你 Mac 上的所有可清理文件。"
        case .scanFailed: return "扫描过程中遇到错误，部分文件未扫描。"
        case .cleanupFailed: return "部分文件清理失败（文件被其他应用占用）。"
        case .diskFull: return "需要至少 1 GB 可用空间执行清理。"
        }
    }

    /// Tint applied to the icon and primary action button. Drawn from
    /// design-system tokens so every surface stays consistent with the rest
    /// of the app's semantic colour language.
    var iconColor: Color {
        switch self {
        case .firstLaunch, .cleanupComplete, .noResults: return .brandPrimary
        case .noHistory: return .textSecondary
        case .noFDA, .scanFailed: return .stateWarning
        case .cleanupFailed, .diskFull: return .stateError
        }
    }
}

/// Centered empty / error placeholder view used by every list screen and
/// root navigator surface in kWise v1.0.
///
/// Renders an SF Symbol hero icon, a title, a multi-line body message, and
/// up to two call-to-action buttons (primary + secondary). The view fills
/// its parent container and lays out vertically with the design-system
/// `Spacing.md` rhythm, so it can be dropped into any full-bleed container
/// (sheet, navigation destination, list background) without further
/// configuration.
///
/// **Naming note:** the type is called `EmptyStateScreen` (not
/// `EmptyStateView`) because the shared `kFoundation.DesignSystem` package
/// already exports its own `EmptyStateView` (lighter-weight; takes raw
/// icon/title/subtitle strings). Our local version is scenario-driven and
/// drives icon / copy / tint from a single ``EmptyStateScenario`` enum, so
/// it lives under a distinct name to avoid module-resolution ambiguity.
///
/// The view exposes a single memberwise init that accepts optional
/// `(title: String, action: () -> Void)` tuples for both buttons; pass `nil`
/// to omit either or both call-to-actions.
///
/// ## Usage
///
/// ```swift
/// EmptyStateScreen(
///     scenario: .noResults,
///     primaryAction: ("重新扫描", { viewModel.startScan() }),
///     secondaryAction: ("了解规则", { showRulesSheet() })
/// )
/// ```
///
/// Actions are optional. When both are `nil` the view renders as a pure
/// informational surface (e.g. `.cleanupComplete`).
struct EmptyStateScreen: View {
    /// Which scenario to render. Drives icon, copy, and tint.
    let scenario: EmptyStateScenario
    /// Optional primary call-to-action rendered as a `.borderedProminent` button.
    var primaryAction: (title: String, action: () -> Void)?
    /// Optional secondary call-to-action rendered as a `.bordered` button.
    var secondaryAction: (title: String, action: () -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: scenario.iconName)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(scenario.iconColor)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text(scenario.title)
                .font(Typography.largeTitle())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
                .accessibilityAddTraits(.isHeader)

            Text(scenario.message)
                .font(Typography.regularBody())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.horizontal, Spacing.md)

            if let primary = primaryAction {
                Button(primary.title, action: primary.action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, Spacing.md)
                    .accessibilityLabel(primary.title)
            }

            if let secondary = secondaryAction {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel(secondary.title)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
/// SwiftUI previews for every `EmptyStateScenario`. Lets reviewers eyeball
/// all eight heroes side-by-side in Xcode's canvas.
struct EmptyStateScreen_Previews: PreviewProvider {
    static var previews: some View {
        let scenarios: [EmptyStateScenario] = [
            .firstLaunch, .noResults, .cleanupComplete, .noHistory,
            .noFDA, .scanFailed, .cleanupFailed, .diskFull
        ]
        return VStack(spacing: 0) {
            ForEach(0..<scenarios.count, id: \.self) { idx in
                EmptyStateScreen(
                    scenario: scenarios[idx],
                    primaryAction: ("主操作", {}),
                    secondaryAction: ("次操作", {})
                )
                .frame(height: 160)
                .background(Color.bgCanvas)
            }
        }
    }
}
#endif
