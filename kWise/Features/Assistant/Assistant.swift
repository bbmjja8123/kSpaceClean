// kWise/Features/Assistant/Assistant.swift
//
// 本地 AI 清理助手 (v2.0 Phase 8, design decision D6) — zero network.
//
// Three deterministic layers:
//   1. Intent matching — keyword/regex template table over zh-Hans/en/ja.
//   2. Semantic disambiguation — optional `NLEmbedding` (macOS 14+);
//      falls back silently to layer 1 when unavailable.
//   3. Answer building — cards + executable actions routed through the
//      SAME selection/cleanup path as the manual UI (never bypassing risk
//      policy or the free-tier quota).
import Foundation
import NaturalLanguage

// MARK: - Intents

public enum AssistantIntent: Equatable {
    case largestFiles(kind: FileKind?)
    case categorySummary
    case diskForecast
    case duplicates
    case appLeftovers
    case startupItems
    case shredHelp
    case cleanupNow
    case similarPhotos
    case freeUpSpace
    case restoreLastCleanup

    public enum FileKind: String, Equatable {
        case video, image, audio, document, archive
    }
}

// MARK: - Matcher (layer 1 + 2)

public struct AssistantIntentMatcher: Sendable {
    init() {}

    /// Template table: (intent, keywords). Order matters — first hit wins,
    /// and more specific templates are listed first.
    private static let templates: [(intent: AssistantIntent, keywords: [String])] = [
        (.largestFiles(kind: .video), ["视频", "电影", "影片", "video", "movie"]),
        (.largestFiles(kind: .image), ["图片", "照片", "image", "photo"]),
        (.largestFiles(kind: .audio), ["音频", "音乐", "audio", "music"]),
        (.largestFiles(kind: .document), ["文档", "document"]),
        (.largestFiles(kind: .archive), ["压缩包", "zip", "archive"]),
        (.largestFiles(kind: nil), ["大文件", "最占空间", "占空间", "large file", "space"]),
        (.duplicates, ["重复", "duplicate", "dupe"]),
        (.appLeftovers, ["残留", "卸载", "leftover", "uninstall"]),
        (.startupItems, ["启动项", "登录项", "startup", "login item"]),
        // Time-phrased fill-up questions ("什么时候会满" / "何时满") are the
        // forecast intent. These stay compound on purpose: a bare "满" or
        // "占满" would steal `.freeUpSpace`'s "磁盘满了" / "磁盘占满了", which
        // is a cleanup request, not a forecast question.
        (.diskForecast, ["什么时候满", "什么时候会满", "何时满", "何时会满", "多久满",
                         "将满", "预测", "磁盘趋势", "forecast", "disk full"]),
        (.shredHelp, ["粉碎", "彻底删除", "shred", "secure delete"]),
        (.cleanupNow, ["清理", "打扫", "clean up", "clean"]),
        (.similarPhotos, ["相似照片", "重复照片", "截图", "similar photo", "screenshot"]),
        (.freeUpSpace, ["腾出空间", "磁盘满了", "空间不足", "free up space", "disk full"]),
        (.restoreLastCleanup, ["还原", "恢复上次", "撤销清理", "undo", "restore"]),
        (.categorySummary, ["哪里", "什么占了", "占了多少", "空间都去哪", "where is my space", "usage"]),
    ]

    /// Matches an utterance to an intent. `nil` = honestly no idea (the UI
    /// offers example questions instead of guessing).
    public func match(_ utterance: String) -> AssistantIntent? {
        let lowered = utterance.lowercased()

        // Question-shape filter: keep "which/what/how" questions and short
        // imperative phrases, drop unrelated chatter fast.
        for (intent, keywords) in Self.templates {
            for keyword in keywords {
                if lowered.contains(keyword.lowercased()) {
                    // Layer 2 (optional): semantic disambiguation for
                    // near-miss keywords. Guarded so macOS 13 and machines
                    // without zh embeddings silently use layer 1.
                    if Self.confident(keyword: keyword, in: lowered) {
                        return intent
                    }
                }
            }
        }
        return nil
    }

    /// Layer 2 hook. A bare keyword hit is already confident — this exists
    /// so a future embedding-based pass can raise precision without
    /// changing the call sites.
    private static func confident(keyword: String, in utterance: String) -> Bool {
        true
    }

    /// zh embedding availability probe (macOS 14+). Kept public for tests
    /// to document the gate without loading NLEmbedding in CI.
    public static var semanticLayerAvailable: Bool {
        if #available(macOS 14, *) {
            return NLEmbedding.wordEmbedding(for: .simplifiedChinese) != nil
                || NLEmbedding.wordEmbedding(for: .english) != nil
        }
        return false
    }
}

// MARK: - Answers

public struct AssistantAnswer: Equatable {
    public struct Card: Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let detail: String
        public let nodeID: UUID?
        // P2 T9：`actionTitle/actionDestination` 诚实删除 —— 卡片按钮原先
        // 跳转的 `.duplicates/.appUninstall/.startupItems/.shredder/.photoClean`
        // 导航面已全部退役；画布上「去哪处理」由组卡与下钻页承接，答案卡
        // 不再提供通往不存在表面的假按钮。

        public init(title: String, detail: String, nodeID: UUID? = nil) {
            self.id = UUID()
            self.title = title
            self.detail = detail
            self.nodeID = nodeID
        }

        public static func == (lhs: Card, rhs: Card) -> Bool { lhs.id == rhs.id }
    }

    public let headline: String
    public let cards: [Card]
    public let suggestions: [String]

    public init(headline: String, cards: [Card], suggestions: [String] = []) {
        self.headline = headline
        self.cards = cards
        self.suggestions = suggestions
    }
}

/// Builds answers from the current scan tree (via `ScanResultsViewModel`).
@MainActor
enum AssistantAnswerBuilder {

    static let exampleQuestions = [
        String(localized: String.LocalizationValue("assistant.suggestion.videos")),
        String(localized: String.LocalizationValue("assistant.suggestion.diskFull")),
        String(localized: String.LocalizationValue("assistant.suggestion.duplicates")),
        String(localized: String.LocalizationValue("assistant.suggestion.appLeftovers")),
    ]

    static func build(intent: AssistantIntent,
                             scanVM: ScanResultsViewModel?) -> AssistantAnswer {
        switch intent {
        case .largestFiles(let kind):
            return largestFiles(kind: kind, scanVM: scanVM)
        case .categorySummary:
            return categorySummary(scanVM: scanVM)
        case .diskForecast:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.diskForecast")),
                cards: [],
                suggestions: exampleQuestions
            )
        case .duplicates:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.duplicates")),
                cards: [AssistantAnswer.Card(
                    title: String(localized: String.LocalizationValue("assistant.card.duplicates.title")),
                    detail: String(localized: String.LocalizationValue("assistant.card.duplicates.detail"))
                )],
                suggestions: exampleQuestions
            )
        case .appLeftovers:
            // fix r1（Important 3）：逐项卸载界面随 P2 T9 退役 —— 不得再
            // 宣传用户无法触达的「清除残留 / 30 天备份回滚」行动承诺；
            // 系统状态条目前只是分类摘要（无真实计数），也不得宣称它
            // 「显示现状」。
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.appLeftovers")),
                cards: [AssistantAnswer.Card(
                    title: String(localized: String.LocalizationValue("assistant.card.appLeftovers.title")),
                    detail: String(localized: String.LocalizationValue("assistant.card.appLeftovers.detail"))
                )],
                suggestions: exampleQuestions
            )
        case .startupItems:
            // fix r1（Important 4）：逐项停用/恢复界面随 P2 T9 退役 ——
            // 同样只做诚实交代，不做不可达的行动承诺。
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.startupItems")),
                cards: [AssistantAnswer.Card(
                    title: String(localized: String.LocalizationValue("assistant.card.startupItems.title")),
                    detail: String(localized: String.LocalizationValue("assistant.card.startupItems.detail"))
                )],
                suggestions: exampleQuestions
            )
        case .shredHelp:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.shredHelp")),
                cards: [AssistantAnswer.Card(
                    title: String(localized: String.LocalizationValue("assistant.card.shred.title")),
                    detail: String(localized: String.LocalizationValue("assistant.card.shred.detail"))
                )],
                suggestions: exampleQuestions
            )
        case .cleanupNow:
            // P1 T5/T6 后的事实口径：首页是空间解剖页，唯一回收入口是页内
            // 「安全快捷回收」按钮（Smart Care 已降级为次级页）。
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.cleanupNow")),
                cards: [],
                suggestions: exampleQuestions
            )
        case .similarPhotos:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.similarPhotos")),
                cards: [AssistantAnswer.Card(
                    title: String(localized: String.LocalizationValue("assistant.card.photos.title")),
                    detail: String(localized: String.LocalizationValue("assistant.card.photos.detail"))
                )],
                suggestions: exampleQuestions
            )
        case .freeUpSpace:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.freeUpSpace")),
                cards: [],
                suggestions: exampleQuestions
            )
        case .restoreLastCleanup:
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.restoreLastCleanup")),
                cards: [],
                suggestions: exampleQuestions
            )
        }
    }

    private static func largestFiles(kind: AssistantIntent.FileKind?,
                                     scanVM: ScanResultsViewModel?) -> AssistantAnswer {
        // Walk the scan tree; leaf entries only, sorted by size.
        var leaves: [(title: String, size: Int64, id: UUID)] = []
        if let scanVM {
            for category in scanVM.categories {
                for sub in category.subItems {
                    for action in sub.actions {
                        for entry in action.results {
                            if let kind, !matchesKind(kind, entry: entry) { continue }
                            leaves.append((entry.title, entry.fileSize, entry.id))
                        }
                    }
                }
            }
        }
        leaves.sort { $0.size > $1.size }

        let kindName: String
        switch kind {
        case .video: kindName = String(localized: String.LocalizationValue("assistant.kind.video"))
        case .image: kindName = String(localized: String.LocalizationValue("assistant.kind.image"))
        case .audio: kindName = String(localized: String.LocalizationValue("assistant.kind.audio"))
        case .document: kindName = String(localized: String.LocalizationValue("assistant.kind.document"))
        case .archive: kindName = String(localized: String.LocalizationValue("assistant.kind.archive"))
        case nil: kindName = String(localized: String.LocalizationValue("assistant.kind.file"))
        }

        guard !leaves.isEmpty else {
            return AssistantAnswer(
                headline: String(
                    format: String(localized: String.LocalizationValue("assistant.answer.largestFilesNone")),
                    kindName
                ),
                cards: [],
                suggestions: exampleQuestions
            )
        }
        let cards = leaves.prefix(5).map { entry in
            AssistantAnswer.Card(
                title: entry.title,
                detail: SharedByteFormat.formatBytes(entry.size),
                nodeID: entry.id
            )
        }
        return AssistantAnswer(
            headline: String(
                format: String(localized: String.LocalizationValue("assistant.answer.largestFilesTop")),
                cards.count, kindName
            ),
            cards: cards,
            suggestions: exampleQuestions
        )
    }

    private static func matchesKind(_ kind: AssistantIntent.FileKind, entry: ScanResult) -> Bool {
        let ext = entry.url.pathExtension.lowercased()
        switch kind {
        case .video: return ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
        case .image: return ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"].contains(ext)
        case .audio: return ["mp3", "aac", "wav", "flac", "m4a", "aiff"].contains(ext)
        case .document: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages"].contains(ext)
        case .archive: return ["zip", "tar", "gz", "rar", "7z", "dmg"].contains(ext)
        }
    }

    private static func categorySummary(scanVM: ScanResultsViewModel?) -> AssistantAnswer {
        guard let scanVM, !scanVM.categories.isEmpty else {
            return AssistantAnswer(
                headline: String(localized: String.LocalizationValue("assistant.answer.categorySummaryEmpty")),
                cards: [],
                suggestions: exampleQuestions
            )
        }
        let cards = scanVM.categories
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(5)
            .map { category in
                AssistantAnswer.Card(
                    title: category.title,
                    detail: SharedByteFormat.formatBytes(category.totalSize),
                    nodeID: category.id
                )
            }
        return AssistantAnswer(
            headline: String(localized: String.LocalizationValue("assistant.answer.categorySummary")),
            cards: cards,
            suggestions: exampleQuestions
        )
    }
}

// MARK: - ViewModel (retired)

// The chat-era `AssistantViewModel` (draft field + `respond(to:)`) was
// removed with AssistantView in P1 T8; the detail panel's
// `AssistantNodePanelModel` (AssistantNodePanel.swift) now owns the
// question → matcher → builder flow without a free-text input.

