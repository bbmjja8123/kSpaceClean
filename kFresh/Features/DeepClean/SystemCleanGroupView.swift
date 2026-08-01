import SwiftUI

/// One section of the ``DeepCleanView`` list: a header showing the
/// ``SystemCleanCategory`` (icon + name + item count) followed by one
/// ``SystemCleanRowView`` per item.
///
/// The view is intentionally stateless — selection state lives in the
/// parent's ``DeepCleanViewModel`` and is passed down via `selectedIDs`
/// and `onToggle`, keeping this render-only.
struct SystemCleanGroupView: View {
    /// The category this section renders.
    let category: SystemCleanCategory
    /// The items belonging to `category`.
    let items: [SystemCleanItem]
    /// The currently-selected item IDs (owned by the view-model).
    let selectedIDs: Set<String>
    /// Called with an item when the user toggles its selection checkbox.
    let onToggle: (SystemCleanItem) -> Void

    var body: some View {
        Section {
            ForEach(items) { item in
                SystemCleanRowView(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    onToggle: { onToggle(item) }
                )
            }
        } header: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(Color.brandSecondary)
                Text(category.displayName)
                    .font(AppFont.title3)
                Text("\(items.count) 项")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
