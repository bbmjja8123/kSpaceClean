import SwiftUI

/// Single-row rendering of a ``SystemCleanItem`` inside the
/// ``SystemCleanGroupView`` list. Displays the item's display name, full
/// path, on-disk size, a protected (Apple-owned) indicator, and a
/// selection checkbox bound through `onToggle`.
///
/// Protected items render with the checkbox disabled — they can never be
/// selected, mirroring the engine's refusal to delete them.
struct SystemCleanRowView: View {
    /// The item this row renders.
    let item: SystemCleanItem
    /// Whether the item is currently in the selection set.
    let isSelected: Bool
    /// Called when the user taps the selection checkbox.
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(item.displayName)
                        .font(AppFont.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isProtected {
                        Label("受保护", systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.warning)
                    }
                }

                Text(item.url.path)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: AppSpacing.sm) {
                    Text(item.sizeBytes.deepCleanSizeFormatted)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                    if let bundleID = item.associatedBundleID {
                        Text(bundleID)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { isSelected },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
            .disabled(item.isProtected)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

/// File-size formatting used by the deep-clean rows and the bottom bar.
///
/// Named uniquely (not `kbFormatted`) because several other views already
/// declare file-private `Int64.kbFormatted` extensions; a module-internal
/// member of that name would be an invalid redeclaration inside those files.
internal extension Int64 {
    /// Formats the byte count using the system file-size formatter (e.g.
    /// "4.2 KB", "1.3 MB"). Wraps `ByteCountFormatter` so the view never
    /// hand-rolls units.
    var deepCleanSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
