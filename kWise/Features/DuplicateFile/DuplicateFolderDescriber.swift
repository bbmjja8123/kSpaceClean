import Foundation
import NaturalLanguage


/// 目录级重复组的关系描述引擎 (v2.6 第二轮)：NLEmbedding 主题标注 +
/// 确定性更新时间差合成。纯内存、零网络；embedding 不可用或置信度
/// 不足时诚实降级为确定性描述（宁可少说，不给编造的主题）。
enum DuplicateFolderDescriber {

    /// 系统 embedding 提供器。生产路径尝试 zh → en 词向量；测试可临时
    /// 替换（如 `{ nil }`）强制走确定性降级分支。测试须 tearDown 恢复原值。
    static var systemEmbeddingProvider: @Sendable () -> NLEmbedding? = {
        NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)
    }

    /// 主题锚点：文件名词向量质心 vs 主题锚点词组。
    static let topics: [(name: String, anchors: [String])] = [
        ("项目代码", ["swift", "py", "git", "source", "build", "代码"]),
        ("照片", ["img", "photo", "dng", "heic", "jpg", "照片"]),
        ("发票文档", ["invoice", "receipt", "pdf", "发票", "账单"]),
        ("音乐", ["mp3", "flac", "track", "音乐", "album"]),
        ("视频素材", ["clip", "mov", "mp4", "footage", "视频"]),
        ("设计稿", ["sketch", "psd", "figma", "设计"]),
    ]

    /// 主题命中的余弦阈值（与 ResidueGroupingEngine 一致：低于阈值视为
    /// 没把握，回退确定性描述而不是硬贴标签）。
    static let topicThreshold = 0.45

    // MARK: - 主入口

    /// 合成「主题标注 + 更新时间差」的关系描述。`embedding` 可注入
    /// （测试）；nil 时走 ``systemEmbeddingProvider``。
    static func describe(fileURLs: [URL],
                         newestDate: Date?,
                         now: Date = Date(),
                         embedding: NLEmbedding? = nil) -> String {
        let resolved = embedding ?? systemEmbeddingProvider()
        let topic = topicName(fileURLs: fileURLs, embedding: resolved)
        // days == 0（两份刚同步过）不构成"旧备份"叙事，归入无时间差分支。
        let days = newestDate.flatMap {
            let d = max(0, Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0)
            return d > 0 ? d : nil
        }
        return compose(topic: topic, days: days)
    }

    /// 四分支文案合成（纯函数，全分支可测）：
    /// 有主题 + 有时间差 / 有主题 / 只有时间差 / 全无。
    static func compose(topic: String?, days: Int?) -> String {
        switch (topic, days) {
        case (.some(let name), .some(let d)):
            return String(format: "这看起来是「%@」相关的备份副本——其中一个已经 %lld 天没有更新，像是同一项目的旧备份",
                          name, d)
        case (.some(let name), nil):
            return String(format: "这看起来是「%@」相关的备份副本——像是同一项目的两次备份", name)
        case (nil, .some(let d)):
            return String(format: "两个文件夹内容完全相同——其中一个已经 %lld 天没有更新，像是同一项目的旧备份", d)
        case (nil, nil):
            return "两个文件夹内容完全相同——像是同一项目的两次备份"
        }
    }

    // MARK: - 主题标注

    /// 文件名词向量质心 → 最贴近的主题名。embedding 不可用、词太少、
    /// 无向量或低于阈值 → nil（调用方回退确定性描述）。
    static func topicName(fileURLs: [URL], embedding: NLEmbedding?) -> String? {
        guard let embedding else { return nil }
        return bestTopic(words: contentWords(in: fileURLs)) { embedding.vector(for: $0) }
    }

    /// 文件名 → 候选词（≥3 字符，按路径分隔/标点切分，小写）。
    static func contentWords(in fileURLs: [URL]) -> [String] {
        fileURLs.flatMap { url in
            url.deletingPathExtension().lastPathComponent
                .split(whereSeparator: { "/-_ .".contains($0) })
                .map { $0.lowercased() }
        }.filter { $0.count >= 3 }
    }

    /// 词质心 vs 各主题锚点质心的最高余弦（`vectorLookup` 注入，纯函数、
    /// 可离线测试命中 / 低于阈值 / 词不足三种走向）。
    static func bestTopic(words: [String],
                          vectorLookup: (String) -> [Double]?) -> String? {
        let componentVectors = words.compactMap(vectorLookup)
        guard componentVectors.count >= 2 else { return nil }

        var best: (name: String, score: Double)?
        for (name, anchors) in topics {
            guard let score = averageCosine(componentVectors: componentVectors,
                                            anchors: anchors,
                                            vectorLookup: vectorLookup) else { continue }
            if score >= topicThreshold, score > (best?.score ?? -1) {
                best = (name, score)
            }
        }
        return best?.name
    }

    /// 组件质心 vs 锚点质心的余弦相似度。任一侧无向量或出现混合维度
    /// （异常注入）→ nil，宁可放弃标注也不给垃圾值。
    static func averageCosine(componentVectors: [[Double]],
                              anchors: [String],
                              vectorLookup: (String) -> [Double]?) -> Double? {
        let anchorVectors = anchors.compactMap(vectorLookup)
        guard !componentVectors.isEmpty, !anchorVectors.isEmpty else { return nil }
        let dim = componentVectors[0].count
        guard componentVectors.allSatisfy({ $0.count == dim }),
              anchorVectors.allSatisfy({ $0.count == dim }) else { return nil }
        return cosineSimilarity(centroid(of: componentVectors), centroid(of: anchorVectors))
    }

    /// 两个等长向量的余弦相似度；零向量或维度不一致 → nil。
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count else { return nil }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (a.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        let magB = (b.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        guard magA > 0, magB > 0 else { return nil }
        return dot / (magA * magB)
    }

    private static func centroid(of vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        let dim = vectors[0].count
        var sum = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim { sum[i] += v[i] }
        }
        return sum.map { $0 / Double(vectors.count) }
    }
}
