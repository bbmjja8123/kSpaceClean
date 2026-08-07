import SwiftUI

/// One row of the app list: icon, name, source badge, size, and a running
/// indicator. Layout uses the shared DesignSystem spacing / font tokens.
///
/// The `sizeBytes` parameter comes from the parent's resolved-size lookup so
/// the view renders the most recently measured value without owning the
/// `sizeMap` itself.
struct AppRowView: View {
    let app: InstalledApp
    let sizeBytes: Int64

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(AppFont.body.weight(.medium))
                    .foregroundStyle(app.isProtected ? Color.textSecondary : Color.textPrimary)
                HStack(spacing: AppSpacing.sm) {
                    Text(app.source.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(app.source.tint)
                    Text("·")
                        .foregroundStyle(Color.textSecondary.opacity(0.6))
                    Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            if app.isRunning {
                Image(systemName: "circle.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.success)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

extension AppSource {
    /// User-facing label for the app's origin.
    var displayName: String {
        switch self {
        case .system: return "系统"
        case .appleBuiltIn: return "Apple"
        case .mas: return "App Store"
        case .userInstalled: return "用户"
        case .homebrew: return "Homebrew"
        case .setapp: return "Setapp"
        case .unknown: return "未知"
        }
    }

    /// Accent color used to tint the source badge in list rows.
    var tint: Color {
        switch self {
        case .system, .appleBuiltIn: return Color.textSecondary
        case .mas: return Color.brandPrimary
        case .userInstalled: return Color.brandSecondary
        case .homebrew: return Color.warning
        case .setapp: return Color.success
        case .unknown: return Color.textSecondary.opacity(0.6)
        }
    }
}
