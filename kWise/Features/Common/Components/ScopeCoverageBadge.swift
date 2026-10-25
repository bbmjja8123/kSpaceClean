import SwiftUI
import DesignSystem
import CommonUtils

/// Small pill surfacing scope coverage: "已扫描 3 个区域 · 未授权：主目录".
///
/// Green when the scan covered everything the scope allows; amber with a
/// "授权" CTA when regions were skipped.
struct ScopeCoverageBadge: View {
    let coverage: ScopeCoverage
    var onGrant: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: coverage.isCompleteForScope ? "checkmark.shield" : "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(coverage.isCompleteForScope ? Color.stateSuccess : Color.stateWarning)
                .accessibilityHidden(true)

            Text(headline)
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)

            if !coverage.isCompleteForScope, let onGrant {
                Button(String(localized: String.LocalizationValue("scope.coverage.grantButton")), action: onGrant)
                    .buttonStyle(.link)
                    .font(AppFont.caption)
                    .accessibilityLabel(String(localized: String.LocalizationValue("scope.coverage.grant.a11y")))
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.bgElevated, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var headline: String {
        if coverage.isCompleteForScope {
            return String(localized: String.LocalizationValue("scope.coverage.complete"))
        }
        let names = coverage.skippedRegions.map(\.displayName).joined(separator: "、")
        return String(format: String(localized: String.LocalizationValue("scope.coverage.incomplete.headline")), names)
    }

    private var accessibilitySummary: String {
        if coverage.isCompleteForScope {
            return String(localized: String.LocalizationValue("scope.coverage.complete.a11y"))
        }
        let names = coverage.skippedRegions.map(\.displayName).joined(separator: "、")
        return String(format: String(localized: String.LocalizationValue("scope.coverage.incomplete.a11y")), names)
    }
}

#Preview("Complete") {
    ScopeCoverageBadge(coverage: ScopeCoverage(scannedBytes: 12_000_000_000, scannedFiles: 42_000))
        .padding()
}

#Preview("Restricted") {
    ScopeCoverageBadge(
        coverage: ScopeCoverage(
            scannedBytes: 3_000_000_000,
            scannedFiles: 11_000,
            skippedRegions: [.init(id: "home", displayName: "主目录", estimatedBytes: 40_000_000_000)]
        ),
        onGrant: {}
    )
    .padding()
}
