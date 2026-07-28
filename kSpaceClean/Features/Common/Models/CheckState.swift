/// Determines checkbox selection state for a tree node.
public enum CheckState: Sendable, Equatable {
    /// No items are selected.
    case unchecked
    /// Some, but not all, child items are selected.
    case mixed
    /// All items are selected.
    case checked

    /// Computes the checkbox state from selection counts.
    public static func from(selected: Bool, total: Int, selectedCount: Int) -> CheckState {
        if selectedCount == 0 { return .unchecked }
        if selectedCount == total { return .checked }
        return .mixed
    }
}
