import SwiftUI
import DesignSystem

struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false

    @State private var icon: NSImage?

    /// True when the file no longer exists on disk (trashed, moved, or
    /// unmounted between scan and view). Used to surface a warning badge
    /// so the user doesn't double-select a path that can no longer be cleaned.
    private var isMissing: Bool {
        !FileManager.default.fileExists(atPath: file.url.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Type-aware placeholder first so the row is never blank while
            // NSWorkspace loads the real icon. Falls back to the generic
            // doc symbol when UTType is unknown.
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else if let typeIcon = FileIconCache.shared.icon(for: file.fileType) {
                    Image(nsImage: typeIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "doc")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
            }
            .opacity(isMissing ? 0.4 : 1.0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(file.url.lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                    if isMissing {
                        // Inline warning label so the user knows the path is
                        // gone (trashed, unmounted, renamed) before they try
                        // to select/clean it.
                        Label(
                            NSLocalizedString("Missing", comment: "File-row warning when path no longer exists"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: file.url) {
            // Cache-hit short-circuit keeps re-renders cheap; first render
            // does the one-time NSWorkspace lookup on a background queue.
            if let cached = FileIconCache.shared.cachedIcon(for: file.url.path) {
                icon = cached
                return
            }
            FileIconCache.shared.loadIcon(for: file.url) { image in
                icon = image
            }
        }
    }
}
