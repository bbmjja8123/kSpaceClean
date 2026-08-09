import SwiftUI
import DesignSystem

struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false

    @State private var icon: NSImage?
    @State private var isMissing = false

    /// True when the file no longer exists on disk (trashed, moved, or
    /// unmounted between scan and view). Used to surface a warning badge
    /// so the user doesn't double-select a path that can no longer be cleaned.
    ///
    /// Populated asynchronously via `.task(id: file.url)` so the stat(2)
    /// syscall runs off the main thread. While the task is in flight the
    /// row renders with `isMissing = false` — a brief window where a
    /// just-deleted file may still look "present" until the next body pass.
    /// The trade-off is intentional: a 10 000-row list with sync stat per
    /// row was blocking the main thread for hundreds of ms per scroll.

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
            // stat(2) off the main thread. The view briefly renders
            // isMissing=false until the next body pass after the await.
            let missing = await Task.detached(priority: .utility) {
                !FileManager.default.fileExists(atPath: file.url.path)
            }.value
            isMissing = missing
        }
    }
}
