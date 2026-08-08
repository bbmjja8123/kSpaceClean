import SwiftUI
import DesignSystem

struct FilterBarView: View {
    @Binding var activeCategory: DuplicateCategory?
    let counts: [DuplicateCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: NSLocalizedString("All", comment: "All categories filter chip"), count: counts.values.reduce(0, +),
                          isSelected: activeCategory == nil) {
                    activeCategory = nil
                }
                ForEach(DuplicateCategory.allCases, id: \.self) { cat in
                    filterChip(title: cat.displayName, count: counts[cat] ?? 0,
                              isSelected: activeCategory == cat,
                              color: cat.color) {
                        activeCategory = (activeCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(title: String, count: Int, isSelected: Bool,
                           color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.caption)
                Text("\(count)").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? color : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
