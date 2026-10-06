// kWise/Tests/CanvasGroupTests.swift
//
// P2 T2 — 画布组组装规则（纯函数，不启扫描）：
// - 空组不出现（条目空或字节 0 → nil，spec §2 动态分组）
// - 五色徽章映射（Reclaimability → BadgeKind）
// - cause 组间 totalBytes 降序 + uniquingKeysWith 路径去重
// - 检测组复用 ToolboxGroup.map 的 reason / honestReclaimable
import XCTest
import DetectionCore
@testable import kWise

final class CanvasGroupTests: XCTestCase {

    // MARK: Fixtures

    private func item(path: String, bytes: Int64,
                      cause: AttributionCause = .cache,
                      reclaim: Reclaimability = .recycles(expectedDays: 7)) -> SpaceAttribution {
        SpaceAttribution(scope: .fileTree, paths: [path], bytes: bytes,
                         owner: .system, cause: cause, reclaim: reclaim,
                         confidence: .certain, source: .rule, ruleID: "test.rule",
                         evidence: [], lastModified: nil)
    }

    private func file(_ path: String, size: Int64,
                      modifiedOffset: TimeInterval,
                      isClone: Bool = false, physical: Int64? = nil) -> DetectionCore.FileItem {
        DetectionCore.FileItem(
            id: UUID(),
            url: URL(fileURLWithPath: path),
            size: size,
            modificationDate: Date(timeIntervalSinceReferenceDate: 700_000_000 + modifiedOffset),
            isAPFSClone: isClone,
            physicalSize: physical)
    }

    private func dupGroup(_ files: [DetectionCore.FileItem]) -> DetectionCore.DuplicateGroup {
        DetectionCore.DuplicateGroup(
            id: UUID(), category: .identical,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count, files: files,
            categoryEvidence: .byteIdentical(sha256: "", byteVerified: false))
    }

    // MARK: 空组不出现

    func testEmptyGroupsNeverAppear() {
        let group = CanvasGroupAssembler.assemble(
            kind: .duplicates, icon: "⧉", entries: [])
        XCTAssertNil(group, "空组不出现（spec §2 动态分组）")
    }

    func testZeroByteEntriesNeverAppear() {
        let entry = CanvasEntry(id: UUID(), title: "a", bytes: 0,
                                badge: .recyclable, detail: nil, target: nil)
        XCTAssertNil(CanvasGroupAssembler.assemble(kind: .duplicates, icon: "⧉", entries: [entry]),
                     "字节 0 的组不出现（诚实原则：0 B 不构成回收机会）")
    }

    // MARK: 五色徽章映射

    func testBadgeMappingFiveColors() {
        XCTAssertEqual(CanvasEntry.badge(forReclaim: .recycles(expectedDays: 3)), .recyclable)
        XCTAssertEqual(CanvasEntry.badge(forReclaim: .resurrects(via: "tmutil")), .attention)
        XCTAssertEqual(CanvasEntry.badge(forReclaim: .permanent), .dataNotJunk)
        XCTAssertEqual(CanvasEntry.badge(forReclaim: .uncertain), .leaveAlone)
    }

    // MARK: cause 组规则

    func testCauseGroupsSortedByBytesDescending() {
        let groups = CanvasGroupAssembler.assembleCauseGroups(from: [
            item(path: "/Users/t/a", bytes: 100, cause: .log),
            item(path: "/Users/t/b", bytes: 900, cause: .cache),
            item(path: "/Users/t/c", bytes: 500, cause: .developerCache),
        ])
        XCTAssertEqual(groups.map(\.id),
                       [.cause(.cache), .cause(.developerCache), .cause(.log)],
                       "cause 组间按 totalBytes 降序")
        XCTAssertEqual(groups.map(\.totalBytes), [900, 500, 100])
    }

    func testCauseGroupsDeduplicateByPathKeepingLarger() {
        let groups = CanvasGroupAssembler.assembleCauseGroups(from: [
            item(path: "/Users/t/dup.bin", bytes: 100, cause: .cache),
            item(path: "/Users/t/dup.bin", bytes: 800, cause: .cache),
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.count, 1,
                       "同一路径只出现一次（uniquingKeysWith 去重）")
        XCTAssertEqual(groups[0].entries[0].bytes, 800, "保留字节更大（更诚实）的一条")
        XCTAssertEqual(groups[0].totalBytes, 800)
    }

    func testUncertainItemsNeverEnterCauseGroups() {
        // reclaim == .uncertain 的项只能出现在拒答清单 —— 绝不进 CanvasGroup。
        let groups = CanvasGroupAssembler.assembleCauseGroups(from: [
            item(path: "/Users/t/chat", bytes: 400, cause: .chatFiles, reclaim: .uncertain),
        ])
        XCTAssertTrue(groups.isEmpty, "「我不敢判的」不占 CanvasGroup（虚线卡单独渲染）")
    }

    // MARK: 拒答虚线卡数据

    func testUncertainCardDerivedFromRefused() {
        XCTAssertNil(CanvasGroupAssembler.uncertainCard(from: []),
                     "拒答清单为空时不渲染虚线卡")
        let card = CanvasGroupAssembler.uncertainCard(from: [
            item(path: "/Users/t/x", bytes: 300, reclaim: .uncertain),
            item(path: "/Users/t/y", bytes: 200, reclaim: .uncertain),
        ])
        XCTAssertEqual(card?.totalBytes, 500)
        XCTAssertEqual(card?.items.count, 2)
    }

    // MARK: 检测组 — 复用 ToolboxGroup.map 的 reason / honestReclaimable

    func testDuplicatesGroupHonestBytesAndRecyclableBadge() {
        let engineGroup = dupGroup([
            file("/Users/t/a copy.zip", size: 100, modifiedOffset: 0),
            file("/Users/t/a.zip", size: 100, modifiedOffset: 100),
        ])
        let mapped = ToolboxGroup.map(engineGroup, strategy: .keepNewest, scanRoots: [])
        let group = CanvasGroupAssembler.assembleDuplicates(from: [mapped])

        XCTAssertNotNil(group)
        XCTAssertEqual(group?.id, .duplicates)
        XCTAssertEqual(group?.totalBytes, 100, "honestReclaimable：size × (n−1)")
        XCTAssertEqual(group?.entries.count, 1, "只有被选中的多余副本成为条目")
        XCTAssertEqual(group?.entries.first?.badge, .recyclable)
        XCTAssertEqual(group?.entries.first?.bytes, 100)
        XCTAssertEqual(group?.action, .rehearse, "重复组动词：就地清理")
    }

    func testAllCloneGroupSkippedAsZeroByte() {
        // APFS 克隆集共享物理块 —— 诚实回收字节为 0，整组不出现。
        let engineGroup = dupGroup([
            file("/Users/t/orig", size: 100, modifiedOffset: 0, isClone: true, physical: 42),
            file("/Users/t/clone", size: 100, modifiedOffset: 100, isClone: true, physical: 42),
        ])
        let mapped = ToolboxGroup.map(engineGroup, strategy: .keepNewest, scanRoots: [])
        XCTAssertNil(CanvasGroupAssembler.assembleDuplicates(from: [mapped]),
                     "克隆集 honestReclaimable == 0 → 空组不出现")
    }

    func testPhotosGroupReusesReasonsAndRehearseAction() {
        let engineGroup = dupGroup([
            file("/Users/t/IMG_1.jpg", size: 200, modifiedOffset: 0),
            file("/Users/t/IMG_2.jpg", size: 200, modifiedOffset: 100),
        ])
        let mapped = ToolboxGroup.map(engineGroup, strategy: .keepNewest, scanRoots: [])
        let group = CanvasGroupAssembler.assemblePhotos(from: [mapped])

        XCTAssertNotNil(group)
        XCTAssertEqual(group?.id, .similarPhotos)
        XCTAssertEqual(group?.entries.first?.badge, .recyclable)
        XCTAssertEqual(group?.action, .rehearse)
        XCTAssertEqual(group?.totalBytes, 200)
    }

    func testLargeFilesGroupMigrateBadgeAndAction() {
        let group = CanvasGroupAssembler.assembleLargeFiles(from: [
            LargeOldFileEntry(url: URL(fileURLWithPath: "/Users/t/big.mov"), size: 1_000,
                              modificationDate: Date()),
            LargeOldFileEntry(url: URL(fileURLWithPath: "/Users/t/big2.mov"), size: 500,
                              modificationDate: Date()),
        ])
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.id, .largeFiles)
        XCTAssertEqual(group?.totalBytes, 1_500)
        XCTAssertEqual(group?.entries.first?.badge, .migrate, "大文件蓝徽：迁出引导")
        XCTAssertEqual(group?.action, .migrate, "大文件组动词：迁出")
    }

    func testLargeFilesEmptyBecomesNil() {
        XCTAssertNil(CanvasGroupAssembler.assembleLargeFiles(from: []))
    }

    // MARK: 全量条目 + truncatedCount（fix r1：截断移展示层）

    func testFullEntriesRetainedWithTruncatedCount() {
        // 30 条目（无 target → 以 id 兜底去重键，互不合并）。
        let entries = (0..<30).map { i in
            CanvasEntry(title: "f\(i)", bytes: Int64(100 + i), badge: .recyclable)
        }
        let group = CanvasGroupAssembler.assemble(
            kind: .largeFiles, icon: "externaldrive", entries: entries)

        XCTAssertNotNil(group)
        XCTAssertEqual(group?.entries.count, 30,
                       "数据层保留全量条目 —— T6 下钻必须能看到 21+ 条目")
        XCTAssertEqual(group?.truncatedCount, 10,
                       "组卡展示层（prefix 20）之外还有 10 条")
        XCTAssertEqual(group?.totalBytes, entries.reduce(Int64(0)) { $0 + $1.bytes })
    }

    func testTruncatedCountZeroAtOrBelowDisplayLimit() {
        let entries = (0..<20).map { i in
            CanvasEntry(title: "f\(i)", bytes: 1, badge: .recyclable)
        }
        let group = CanvasGroupAssembler.assemble(
            kind: .duplicates, icon: "doc.on.doc", entries: entries)
        XCTAssertEqual(group?.truncatedCount, 0, "恰在展示上限内 → 不显示「还有 N 项」")
    }
}
