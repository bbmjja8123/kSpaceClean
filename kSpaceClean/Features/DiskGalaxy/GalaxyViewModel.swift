import Foundation
import DesignSystem

@MainActor
public final class GalaxyViewModel: ObservableObject {
    @Published public var categories: [CategoryGroup] = []
    @Published public var selectedCategory: FileCategory?
    @Published public var breadcrumb: [String] = ["/"]

    public struct CategoryGroup: Identifiable {
        public let id = UUID()
        public let category: FileCategory
        public let totalSize: Double
        public let fileCount: Int
    }

    public func update(with results: [FileEntry]) {
        var groups: [FileCategory: (size: Double, count: Int)] = [:]
        for entry in results {
            let cat = FileCategory(rawValue: entry.category ?? "") ?? .other
            var current = groups[cat] ?? (0, 0)
            current.size += Double(entry.size)
            current.count += 1
            groups[cat] = current
        }
        categories = groups.map { CategoryGroup(category: $0.key, totalSize: $0.value.size, fileCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    public func selectCategory(_ name: String) {
        selectedCategory = FileCategory(rawValue: name)
    }

    public func deselectAll() {
        selectedCategory = nil
    }

    public func drillDown(_ name: String) {
        selectedCategory = FileCategory(rawValue: name)
        breadcrumb.append(name)
    }
}
