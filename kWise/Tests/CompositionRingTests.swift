// kWise/Tests/CompositionRingTests.swift
//
// Task 9：hero 迷你比例环 —— 折叠数学（RingFold）纯函数单测。
// 「其他」片按 `isOther` 哨兵判别（不伪造 GroupKind）。
import XCTest
@testable import kWise

final class CompositionRingTests: XCTestCase {
    private func slice(_ id: GroupKind, _ f: Double) -> RingSliceModel {
        RingSliceModel(id: id, fraction: f)
    }

    func testFoldKeepsTopNAndMergesRest() {
        let slices = [slice(.largeFiles, 0.4), slice(.duplicates, 0.25),
                      slice(.similarPhotos, 0.15), slice(.cause(.cache), 0.12),
                      slice(.cause(.log), 0.08)]
        let folded = RingFold.fold(slices, top: 3)
        XCTAssertEqual(folded.count, 4, "top3 + 其他")
        XCTAssertEqual(folded.last?.fraction ?? 0, 0.20, accuracy: 0.001, "其余合并")
        // 「其他」用 isOther 哨兵判别 —— id 只是占位，不是语义。
        XCTAssertEqual(folded.last?.isOther ?? false, true, "合并片必须 isOther")
        XCTAssertEqual(folded.prefix(3).allSatisfy { !$0.isOther }, true,
                       "前 N 片不是「其他」")
        XCTAssertEqual(folded.prefix(3).map(\.fraction),
                       [0.4, 0.25, 0.15], "前 N 按份额降序保留")
    }

    func testFoldConservesTotal() {
        let slices = (0..<9).map { _ in slice(.cause(.cache), 1.0 / Double(9)) }
        let total = RingFold.fold(slices, top: 3).reduce(0) { $0 + $1.fraction }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001, "角度守恒")
    }

    func testEmptySlicesGiveEmptyFold() {
        XCTAssertTrue(RingFold.fold([], top: 3).isEmpty)
    }

    func testFoldNoOpWhenWithinTop() {
        let slices = [slice(.largeFiles, 0.7), slice(.duplicates, 0.3)]
        let folded = RingFold.fold(slices, top: 3)
        XCTAssertEqual(folded, slices, "片数 ≤ top 时不折叠、不出「其他」")
    }

    func testFoldMarksNoOtherWhenRestIsZero() {
        let slices = [slice(.largeFiles, 1.0), slice(.duplicates, 0.0),
                      slice(.similarPhotos, 0.0), slice(.cause(.cache), 0.0)]
        let folded = RingFold.fold(slices, top: 3)
        // 剩余合计为 0 → 不产生「其他」合并片（前 N 原样保留，含零份额片；
        // 视图层对 fraction ≤ 0 的片不绘制、生产侧 compositionSlices 也不产
        // 生零份额组 —— 空组不出现）。
        XCTAssertEqual(folded.count, 3)
        XCTAssertEqual(folded.allSatisfy { !$0.isOther }, true)
    }
}
