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

    /// 独立文件夹模式 (v2.3 Phase 5)：bindFolderRoot 后地图渲染所选文件夹
    /// 的内容森林，不再依赖 SmartScan 扫描结果。
    private var folderRoots: [ScanCategory]?

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
        let forest = activeRoots().filter { $0.totalSize > 0 }
        let roots: [any ScanTreeNode] = focusedNode()?.children ?? forest
        segments = SegmentBuilder.flatten(roots: roots)
    }

    /// Whether the SmartScan forest has data (drives the empty-state CTA).
    var hasSmartScanForest: Bool {
        !rootsProvider().filter { $0.totalSize > 0 }.isEmpty
    }

    private func activeRoots() -> [ScanCategory] {
        (folderRoots ?? rootsProvider()).filter { $0.totalSize > 0 }
    }

    /// Maps an arbitrary (granted) folder into the map: immediate
    /// subdirectories become app-bucket rows, files become leaves.
    func bindFolderRoot(_ url: URL, maxChildren: Int = 200) {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var subs: [ScanSubCategory] = []
        for child in contents.prefix(maxChildren) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            if isDir {
                let files = (try? fm.contentsOfDirectory(
                    at: child, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
                )) ?? []
                let leaves = files.prefix(100).compactMap { fileURL -> ScanResult? in
                    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))
                        .flatMap { $0.fileSize.map(Int64.init) } ?? 0
                    guard fileSize > 0 else { return nil }
                    return ScanResult(
                        url: fileURL, path: fileURL.path, title: fileURL.lastPathComponent,
                        fileSize: fileSize, cleanType: .temporary
                    )
                }
                if !leaves.isEmpty {
                    subs.append(ScanSubCategory(
                        subCategoryID: child.lastPathComponent,
                        title: child.lastPathComponent,
                        totalSize: size, directResults: Array(leaves),
                        showAction: false, isPseudoApp: true
                    ))
                }
            } else if size > 0 {
                subs.append(ScanSubCategory(
                    subCategoryID: child.lastPathComponent,
                    title: child.lastPathComponent,
                    totalSize: size,
                    directResults: [ScanResult(
                        url: child, path: child.path, title: child.lastPathComponent,
                        fileSize: size, cleanType: .temporary
                    )],
                    showAction: false, isPseudoApp: true
                ))
            }
        }

        let rootCategory = ScanCategory(
            categoryID: "folder.map",
            title: url.lastPathComponent,
            subItems: subs
        )
        folderRoots = [rootCategory]
        focusPath = []
        rebuild()
    }

    /// Back to the SmartScan forest.
    func clearFolderMode() {
        folderRoots = nil
        focusPath = []
        rebuild()
    }

    private func focusedNode() -> (any ScanTreeNode)? {
        guard let last = focusPath.last else { return nil }
        return findNode(id: last.id, in: activeRoots().map { $0 as any ScanTreeNode })
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
        activeRoots().flatMap { $0.collectSelected() }
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
