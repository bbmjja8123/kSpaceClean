import SwiftUI
import DesignSystem
import CommonUtils

/// Privacy Overview — the M3 surface that replaced the TCC.db reader.
///
/// Lists what kWise can act on (cleanable surfaces) and what needs a
/// System Settings visit (guidance rows with deep links). Scope coverage
/// is shown honestly via ``ScopeCoverageBadge``.
struct PrivacyOverviewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                header
                ForEach(PrivacySurface.catalog) { surface in
                    PrivacySurfaceRow(surface: surface)
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(Color.bgCanvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("隐私概览")
                .font(AppFont.title2)
                .foregroundStyle(Color.textPrimary)
            Text("kWise 只列出它能实际处理的项目；其余项会直接带你去系统设置。")
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// One row of the overview: cleanable surfaces show a chevron into the
/// scanner; guidance rows deep-link to System Settings.
struct PrivacySurfaceRow: View {
    let surface: PrivacySurface

    var body: some View {
        Group {
            if surface.kind == .guidance, let path = surface.settingsPath {
                Button {
                    if let url = URL(string: path) {
                        NSWorkspace.shared.open(url)
                    }
                } label: { rowContent }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rowContent: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: surface.iconSystemName)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: String.LocalizationValue(surface.titleKey)))
                    .font(AppFont.body)
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: String.LocalizationValue(surface.detailKey)))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Image(systemName: surface.kind == .guidance ? "arrow.up.forward" : "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var accessibilityLabel: String {
        String(localized: String.LocalizationValue(surface.titleKey))
    }
}

#Preview("Overview") {
    PrivacyOverviewView()
        .frame(width: 640, height: 520)
        .preferredColorScheme(.dark)
}
