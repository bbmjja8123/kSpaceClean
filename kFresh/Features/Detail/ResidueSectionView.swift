import SwiftUI

/// Residue section of the app-detail pane: a header with scan progress and
/// one row per detected residue file.
struct ResidueSectionView: View {
    let residues: [ResidueFile]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("残留文件")
                    .font(AppFont.title3)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text("\(residues.count) 项")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if residues.isEmpty && !isLoading {
                Text("未发现残留")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, AppSpacing.md)
            } else {
                ForEach(residues, id: \.url) { residue in
                    ResidueRow(residue: residue)
                }
            }
        }
    }
}

private struct ResidueRow: View {
    let residue: ResidueFile

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: residue.type.systemImage)
                .foregroundStyle(Color.brandSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(residue.url.lastPathComponent)
                    .font(AppFont.body)
                Text(residue.url.deletingLastPathComponent().path)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(residue.sizeFormatted)
                    .font(AppFont.caption.monospacedDigit())
                Text("置信度 \(Int(residue.confidence * 100))%")
                    .font(AppFont.caption)
                    .foregroundStyle(confidenceColor)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var confidenceColor: Color {
        if residue.confidence > 0.8 { return Color.success }
        if residue.confidence > 0.5 { return Color.warning }
        return Color.danger
    }
}

extension ResidueType {
    /// SF Symbol name for each residue category, used for the row icon.
    var systemImage: String {
        switch self {
        case .preferences: return "gearshape"
        case .caches: return "internaldrive"
        case .appSupport: return "folder"
        case .container: return "shippingbox"
        case .savedState: return "internaldrive"
        case .webKit: return "safari"
        case .httpStorage: return "externaldrive"
        case .groupContainer: return "shippingbox.and.arrow.backward"
        case .launchAgent, .launchDaemon: return "play.circle"
        case .prefPane: return "slider.horizontal.3"
        case .plugin: return "puzzlepiece"
        case .startupItem: return "arrow.up.forward.app"
        case .log: return "doc.text"
        case .cookie: return "circle.grid.cross"
        case .appleScript: return "applescript"
        case .other: return "questionmark.folder"
        }
    }
}
