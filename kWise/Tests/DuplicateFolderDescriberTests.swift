// kWise/Tests/DuplicateFolderDescriberTests.swift
//
// v2.6 重复文件第二轮 — 目录级关系描述：compose 四分支、bestTopic
// mock vectorLookup（命中 / 低于阈值 / 词不足 / 混合维度）、embedding
// 不可用时 describe 的诚实降级。
import XCTest
import NaturalLanguage
@testable import kWise

final class DuplicateFolderDescriberTests: XCTestCase {

    private var originalProvider: (@Sendable () -> NLEmbedding?)!

    override func setUp() {
        super.setUp()
        originalProvider = DuplicateFolderDescriber.systemEmbeddingProvider
    }

    override func tearDown() {
        DuplicateFolderDescriber.systemEmbeddingProvider = originalProvider
        super.tearDown()
    }

    // MARK: - compose 四分支

    func testComposeWithNoTopicAndNoDays() {
        XCTAssertEqual(DuplicateFolderDescriber.compose(topic: nil, days: nil),
                       "两个文件夹内容完全相同——像是同一项目的两次备份")
    }

    func testComposeWithDaysOnly() {
        let text = DuplicateFolderDescriber.compose(topic: nil, days: 45)
        XCTAssertTrue(text.contains("两个文件夹内容完全相同"))
        XCTAssertTrue(text.contains("45 天"))
    }

    func testComposeWithTopicOnly() {
        let text = DuplicateFolderDescriber.compose(topic: "照片", days: nil)
        XCTAssertTrue(text.contains("「照片」"))
        XCTAssertTrue(text.contains("两次备份"))
    }

    func testComposeWithTopicAndDays() {
        let text = DuplicateFolderDescriber.compose(topic: "项目代码", days: 3)
        XCTAssertTrue(text.contains("「项目代码」"))
        XCTAssertTrue(text.contains("3 天"))
    }

    // MARK: - describe 降级与时间差

    func testDescribeFallsBackToDeterministicWhenEmbeddingUnavailable() {
        DuplicateFolderDescriber.systemEmbeddingProvider = { nil }
        let urls = [URL(fileURLWithPath: "/tmp/a/photo1.jpg")]
        let newest = Date(timeIntervalSinceNow: -90 * 86400)
        let text = DuplicateFolderDescriber.describe(fileURLs: urls, newestDate: newest,
                                                     now: Date())
        XCTAssertTrue(text.contains("90 天"))
        XCTAssertFalse(text.contains("「"), "embedding 不可用时不得编造主题标注")
    }

    func testDescribeWithNoNewestDateOmitsDays() {
        DuplicateFolderDescriber.systemEmbeddingProvider = { nil }
        let text = DuplicateFolderDescriber.describe(
            fileURLs: [URL(fileURLWithPath: "/tmp/a/f.bin")], newestDate: nil)
        XCTAssertFalse(text.contains("天没有更新"))
    }

    func testDescribeWithSameDayModificationOmitsStaleNarrative() {
        DuplicateFolderDescriber.systemEmbeddingProvider = { nil }
        let newest = Date()  // 今天：days == 0，"已经 0 天没有更新" 不成立
        let text = DuplicateFolderDescriber.describe(fileURLs: [], newestDate: newest,
                                                     now: newest)
        XCTAssertFalse(text.contains("天没有更新"))
    }

    // MARK: - topicName / contentWords

    func testTopicNameReturnsNilWithoutEmbedding() {
        let urls = [URL(fileURLWithPath: "/tmp/a/vacation-sunset.jpg")]
        XCTAssertNil(DuplicateFolderDescriber.topicName(fileURLs: urls, embedding: nil))
    }

    func testContentWordsSplitsAndFiltersShortTokens() {
        let urls = [URL(fileURLWithPath: "/tmp/MyTrip_Vacation-2024.jpg"),
                    URL(fileURLWithPath: "/tmp/ab.jpg")]  // "ab" < 3 字符，过滤
        XCTAssertEqual(DuplicateFolderDescriber.contentWords(in: urls),
                       ["mytrip", "vacation", "2024"])
    }

    // MARK: - bestTopic（mock vectorLookup）

    /// 照片域：命中词 → [1,0]，其余（含代码锚点）→ [0,1]。
    private static let photoDomain: Set<String> = [
        "img", "photo", "dng", "heic", "jpg", "照片", "vacation", "sunset",
    ]
    private func photoLookup(_ word: String) -> [Double]? {
        Self.photoDomain.contains(word) ? [1.0, 0.0] : [0.0, 1.0]
    }

    func testBestTopicHitsPhotoAnchors() {
        let topic = DuplicateFolderDescriber.bestTopic(
            words: ["vacation", "sunset"], vectorLookup: photoLookup)
        XCTAssertEqual(topic, "照片")
    }

    func testBestTopicReturnsNilBelowThreshold() {
        // 组件向量与所有锚点正交 → 余弦 0 < 0.45，宁可放弃不硬贴。
        // （锚点词走 [0,1]，组件词走 [1,0]——lookup 必须区分两者。）
        let anchors = Set(DuplicateFolderDescriber.topics.flatMap(\.anchors))
        let topic = DuplicateFolderDescriber.bestTopic(
            words: ["vacation", "sunset"]) { anchors.contains($0) ? [0.0, 1.0] : [1.0, 0.0] }
        XCTAssertNil(topic)
    }

    func testBestTopicReturnsNilWithFewerThanTwoVectors() {
        // 单词 / 全部查不到向量 → nil。
        XCTAssertNil(DuplicateFolderDescriber.bestTopic(words: ["img"], vectorLookup: photoLookup))
        XCTAssertNil(DuplicateFolderDescriber.bestTopic(words: ["img", "photo"]) { _ in nil })
    }

    func testAverageCosineReturnsNilOnMixedDimensions() {
        let score = DuplicateFolderDescriber.averageCosine(
            componentVectors: [[1.0, 0.0], [1.0, 0.0, 0.0]],
            anchors: ["img"],
            vectorLookup: { _ in [1.0, 0.0] })
        XCTAssertNil(score, "混合维度宁可放弃也不给垃圾值")
    }
}
