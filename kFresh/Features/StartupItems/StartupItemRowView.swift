import SwiftUI

/// Single-row rendering of a ``StartupItem`` inside the
/// `StartupItemsView` list. Displays the item's label, full path,
/// protected indicator, and a toggle / remove control pair.
///
/// Both controls observe `item.isProtected` and disable themselves
/// when true — system-level items are read-only and cannot be modified
/// in v1.
struct StartupItemRowView: View {
    let item: StartupItem
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(item.name)
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

                if let appURL = item.appURL {
                    Text(appURL.path)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { item.enabled },
                    set: { _ in onToggle() }
                )
            )
            .labelsHidden()
            .disabled(item.isProtected)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(item.isProtected ? Color.textSecondary.opacity(0.4) : Color.danger)
            }
            .buttonStyle(.borderless)
            .disabled(item.isProtected)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
