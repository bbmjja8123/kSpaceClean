// kWise/Features/SpaceMap/SpaceMapViewModel.swift
import Foundation
import Combine

/// Drives the 空间地图 surface (v2.0 Phase 4).
///
/// The map renders from the *same* `ScanCategory` forest the results tree
/// uses — a ⌘-click on a wedge toggles the underlying `ScanTreeNode.state`,
/// so selection, cleanup and freed-bytes stay consistent with the results
/// view (single source of truth).
@MainActor
public final class SpaceMapViewModel: ObservableObject {
    /// Sunburst vs. slice-diced treemap.
    public enum Mode: String, CaseIterable {
        case sunburst
        case treemap
    }

    @Published public private(set) var mode: Mode = .sunburst
    @Published public private(set) var segments: [SpaceSegment] = []
    /// Breadcrumb chain from the root to the focused node.
    @Published public private(set) var focusPath: [Breadcrumb] = []

    /// Weak-ish hold on the tree root so segments can rebuild on focus
    /// changes. The categories are owned by `ScanResultsViewModel`.
    private var rootsProvider: () -> [ScanCategory]

    public struct Breadcrumb: Identifiable, Equatable {
        public let id: UUID
        public let title: String
    }

    public init(rootsProvider: @escaping () -> [ScanCategory] = { [] }) {
        self.rootsProvider = rootsProvider
    }

    /// Late-binds the scan forest (the app root wires this in `.onAppear`
    /// because `@StateObject` initializers cannot read the environment).
    public func rebindRoots(_ provider: @escaping () -> [ScanCategory]) {
        self.rootsProvider = provider
        rebuild()
    }

    // MARK: - Building

    /// Rebuilds segments at the current focus level.
    public func rebuild() {
        let forest = rootsProvider().filter { $0.totalSize > 0 }
        let roots: [any ScanTreeNode] = focusedNode()?.children ?? forest
        segments = SegmentBuilder.flatten(roots: roots)
    }

    private func focusedNode() -> (any ScanTreeNode)? {
        guard let last = focusPath.last else { return nil }
        return findNode(id: last.id, in: rootsProvider().map { $0 as any ScanTreeNode })
    }

    private func findNode(id: UUID, in nodes: [any ScanTreeNode]) -> (any ScanTreeNode)? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = findNode(id: id, in: node.children) { return hit }
        }
        return nil
    }

    // MARK: - Interaction

    /// Tap a segment: leaf → toggle nothing (details only); branch → drill in.
    public func tap(_ segment: SpaceSegment, modifierHeld: Bool = false) {
        if modifierHeld {
            toggleSelection(segment)
            return
        }
        guard segment.hasChildren, !segment.isCollapsedBucket else { return }
        focusPath.append(Breadcrumb(id: segment.id, title: segment.title))
        rebuild()
    }

    /// Pop to a breadcrumb level (`.id` of nil = root).
    public func popTo(levelID: UUID?) {
        if let levelID {
            while let last = focusPath.last, last.id != levelID {
                focusPath.removeLast()
            }
        } else {
            focusPath.removeAll()
        }
        rebuild()
    }

    /// ⌘-click: toggle the underlying node's checked state so the map and
    /// the results tree stay in sync.
    public func toggleSelection(_ segment: SpaceSegment) {
        guard !segment.isCollapsedBucket else { return }
        let node = segment.node
        switch node.state {
        case .checked:
            node.setState(.unchecked)
        case .unchecked, .mixed:
            node.setState(.checked)
        }
        rebuild()
    }

    /// URLs currently checked under the focused subtree (for the clean CTA).
    public func collectSelectedURLs() -> [URL] {
        let forest = rootsProvider()
        return forest.flatMap { $0.collectSelected() }
    }

    // MARK: - Mode

    public func setMode(_ newMode: Mode) {
        mode = newMode
    }

    /// Total bytes visible at the current focus level.
    public var focusedTotalSize: Int64 {
        segments.reduce(0) { $0 + $1.size }
    }
}
