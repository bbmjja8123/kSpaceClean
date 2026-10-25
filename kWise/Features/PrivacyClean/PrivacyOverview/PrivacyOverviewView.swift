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
                PrivacySurfaceCatalog()
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

/// The channel-filtered catalog as a plain row stack — safe to embed inside
/// a Form `Section` (no nested ScrollView).
struct PrivacySurfaceCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(PrivacySurface.catalogForCurrentChannel) { surface in
                PrivacySurfaceRow(surface: surface)
            }
        }
    }
}

/// One row of the overview: guidance rows deep-link to System Settings;
/// cleanable rows are inert labels — the actual cleaning actions live in
/// the privacy scanner section below (no dead chevron affordance).
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
            if surface.kind == .guidance {
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
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
