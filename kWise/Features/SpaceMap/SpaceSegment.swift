// kWise/Features/SpaceMap/SpaceSegment.swift
//
// 空间地图 (v2.0 Phase 4) — segment model + tree flattening.
//
// The sunburst/treemap renders from the *same* `ScanTreeNode` tree the
// results view uses — one source of truth. `SegmentBuilder` walks the
// existential node tree and produces flat, angle-assigned segments; small
// children collapse into a per-parent "其他" bucket so the canvas never
// renders hundreds of micro-arcs.
import Foundation

/// One drawable wedge/rectangle. Angular fields drive the sunburst; the
/// treemap uses `size` + sort order with its own slicer.
public struct SpaceSegment: Identifiable, Equatable {
    public let id: UUID
    /// Friendly display title (already localized by the node).
    public let title: String
    public let size: Int64
    /// Ring index — 0 is the innermost (category) ring.
    public let depth: Int
    /// Angular range in radians, measured clockwise from 12 o'clock.
    public let startAngle: Double
    public let endAngle: Double
    public let risk: RiskLevel
    /// `true` for the aggregated "其他" bucket.
    public let isCollapsedBucket: Bool
    /// `true` when the segment can be drilled into.
    public let hasChildren: Bool
    /// Node backing this segment (reference semantics — selection toggles
    /// propagate to the results tree).
    public let node: any ScanTreeNode

    public static func == (lhs: SpaceSegment, rhs: SpaceSegment) -> Bool {
        lhs.id == rhs.id && lhs.startAngle == rhs.startAngle && lhs.endAngle == rhs.endAngle
    }

    /// Midpoint angle, handy for label placement.
    public var midAngle: Double { (startAngle + endAngle) / 2 }

    /// Fraction of the full circle this segment spans.
    public var fraction: Double { (endAngle - startAngle) / (2 * .pi) }
}

/// Flattens a `ScanTreeNode` forest into sunburst segments.
public enum SegmentBuilder {

    /// Builds segments for one focused level (the node's children).
    ///
    /// - Parameters:
    ///   - roots: children of the currently focused node (top level: categories).
    ///   - maxDepth: how many rings to draw below the focus level.
    ///   - minFraction: children smaller than this fraction of the level
    ///     total collapse into the "其他" bucket.
    /// - Returns: flat segments; angular ranges sum to exactly 2π (size
    ///   conservation), so ring boundaries stay aligned.
    public static func flatten(roots: [any ScanTreeNode],
                               maxDepth: Int = 3,
                               minFraction: Double = 0.02) -> [SpaceSegment] {
        let positive = roots.filter { $0.totalSize > 0 }
        let total = positive.reduce(Int64(0)) { $0 + $1.totalSize }
        guard total > 0 else { return [] }
        var segments: [SpaceSegment] = []
        buildLevel(
            nodes: positive,
            total: total,
            startAngle: 0,
            sweep: 2 * Double.pi,
            depth: 0,
            maxDepth: maxDepth,
            minFraction: minFraction,
            into: &segments
        )
        return segments
    }

    // MARK: - Recursion

    private static func buildLevel(nodes: [any ScanTreeNode],
                                   total: Int64,
                                   startAngle: Double,
                                   sweep: Double,
                                   depth: Int,
                                   maxDepth: Int,
                                   minFraction: Double,
                                   into segments: inout [SpaceSegment]) {
        guard !nodes.isEmpty, total > 0 else { return }

        // Sort largest-first for a stable, DaisyDisk-like ordering.
        let sorted = nodes.sorted { $0.totalSize > $1.totalSize }
        let threshold = Int64(Double(total) * minFraction)
        let major = sorted.filter { $0.totalSize >= threshold }
        let minor = sorted.filter { $0.totalSize < threshold }

        var angle = startAngle

        func emit(_ node: any ScanTreeNode) {
            let fraction = Double(node.totalSize) / Double(total)
            let nodeSweep = fraction * sweep
            let segment = SpaceSegment(
                id: node.id,
                title: node.title,
                size: node.totalSize,
                depth: depth,
                startAngle: angle,
                endAngle: angle + nodeSweep,
                risk: node.riskLevel,
                isCollapsedBucket: false,
                hasChildren: !node.children.isEmpty,
                node: node
            )
            segments.append(segment)
            // Recurse into children within this wedge.
            if depth < maxDepth - 1 {
                let children = node.children.filter { $0.totalSize > 0 }
                let childTotal = children.reduce(Int64(0)) { $0 + $1.totalSize }
                if childTotal > 0 {
                    buildLevel(
                        nodes: children,
                        total: childTotal,
                        startAngle: angle,
                        sweep: nodeSweep,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        minFraction: minFraction,
                        into: &segments
                    )
                }
            }
            angle += nodeSweep
        }

        for node in major { emit(node) }

        // One aggregated bucket per level keeps micro-arcs out of the canvas.
        if !minor.isEmpty {
            let minorTotal = minor.reduce(Int64(0)) { $0 + $1.totalSize }
            let bucketSweep = Double(minorTotal) / Double(total) * sweep
            let bucketNode = CollapsedBucketNode(items: minor)
            segments.append(SpaceSegment(
                id: bucketNode.id,
                title: bucketNode.title,
                size: minorTotal,
                depth: depth,
                startAngle: angle,
                endAngle: angle + bucketSweep,
                risk: .optional,
                isCollapsedBucket: true,
                hasChildren: false,
                node: bucketNode
            ))
        }
    }
}

/// Synthetic node backing the "其他" bucket. Holds no real URLs — tapping it
/// only shows the aggregate, it is not selectable for cleanup.
final class CollapsedBucketNode: ScanTreeNode, @unchecked Sendable {
    let id = UUID()
    let title = "其他"
    let tooltip: String? = nil
    let totalSize: Int64
    let selectedSize: Int64 = 0
    var state: CheckState { get { .off } set {} }
    let children: [any ScanTreeNode] = []
    let riskLevel: RiskLevel = .optional
    let isRecommended: Bool = false
    let showAction: Bool = false
    var isHiddenByFilter: Bool {
        get { false }
        set {}
    }

    private let items: [any ScanTreeNode]

    init(items: [any ScanTreeNode]) {
        self.items = items
        self.totalSize = items.reduce(0) { $0 + $1.totalSize }
    }

    func setState(_ newState: CheckState) {}
    func refreshState() {}
    func collectSelected() -> [URL] { [] }

    /// Member titles for the detail panel.
    var memberTitles: [String] { items.map(\.title) }
}
