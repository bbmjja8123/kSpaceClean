/// Determines checkbox selection state for a tree node.
public enum CheckState: Sendable, Equatable {
    /// No items are selected.
    case unchecked
    /// Alias for `.unchecked` matching the A4 cascade-checkbox spec.
    public static var off: CheckState { .unchecked }
    /// Some, but not all, child items are selected.
    case mixed
    /// All items are selected.
    case checked
    /// Alias for `.checked` matching the A4 cascade-checkbox spec.
    public static var on: CheckState { .checked }

    /// Computes the checkbox state from selection counts.
    public static func from(selected: Bool, total: Int, selectedCount: Int) -> CheckState {
        if selectedCount == 0 { return .unchecked }
        if selectedCount == total { return .checked }
        return .mixed
    }

    /// Rolls child states up into a parent row's tri-state.
    ///
    /// A single `.mixed` child forces the parent to `.mixed` — the pre-fix
    /// per-node logic only counted `.on` children, so one checked leaf under
    /// an otherwise unchecked subtree read as "nothing selected" and the
    /// ancestor chain never showed the tri-state dash. Shared by
    /// `ScanCategory` / `ScanSubCategory` / `ScanAction` so the three
    /// `refreshState()` implementations cannot drift apart again.
    public static func aggregate(_ states: [CheckState]) -> CheckState {
        guard !states.isEmpty else { return .unchecked }
        if states.contains(.mixed) { return .mixed }
        let onCount = states.filter { $0 == .on }.count
        return from(selected: true, total: states.count, selectedCount: onCount)
    }
}
