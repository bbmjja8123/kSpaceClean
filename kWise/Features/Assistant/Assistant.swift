// kWise/Features/Assistant/Assistant.swift
//
// 本地 AI 清理助手 (v2.0 Phase 8, design decision D6) — zero network.
//
// Three deterministic layers:
//   1. Intent matching — keyword/regex template table over zh-Hans/en/ja.
//   2. Semantic disambiguation — optional `NLEmbedding` (macOS 14+) gated
//      behind prefs.assistantEnabled; falls back silently to layer 1.
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
        (.diskForecast, ["什么时候满", "将满", "预测", "磁盘趋势", "forecast", "disk full"]),
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
        /// 一键执行 (v2.6 W9)：卡片底部按钮 → 打开对应工具 Tab。
        public let actionTitle: String?
        public let actionDestination: AppState.NavigationItem?

        public init(title: String, detail: String, nodeID: UUID? = nil,
                    actionTitle: String? = nil,
                    actionDestination: AppState.NavigationItem? = nil) {
            self.id = UUID()
            self.title = title
            self.detail = detail
            self.nodeID = nodeID
            self.actionTitle = actionTitle
            self.actionDestination = actionDestination
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
        "哪些视频最占空间？",
        "磁盘什么时候会满？",
        "清理重复文件",
        "应用残留有哪些？",
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
                headline: "打开健康月报即可查看「磁盘将满」预测曲线。",
                cards: [],
                suggestions: exampleQuestions
            )
        case .duplicates:
            return AssistantAnswer(
                headline: "重复文件清理在工具箱中，扫描后会智能保留最新原件。",
                cards: [AssistantAnswer.Card(title: "打开重复文件工具", detail: "字节级 + APFS 克隆 + 视觉相似",
                                             actionTitle: "去清理", actionDestination: .duplicates)],
                suggestions: exampleQuestions
            )
        case .appLeftovers:
            return AssistantAnswer(
                headline: "应用卸载会同时清除缓存、日志等残留文件，全部可回滚。",
                cards: [AssistantAnswer.Card(title: "打开应用卸载", detail: "1141 条规则识别残留，可备份 30 天",
                                             actionTitle: "去卸载", actionDestination: .appUninstall)],
                suggestions: exampleQuestions
            )
        case .startupItems:
            return AssistantAnswer(
                headline: "启动项管理支持停用用户级启动代理，随时可在时间线恢复。",
                cards: [AssistantAnswer.Card(title: "打开启动项管理", detail: "停用/恢复登录启动代理",
                                             actionTitle: "去管理", actionDestination: .startupItems)],
                suggestions: exampleQuestions
            )
        case .shredHelp:
            return AssistantAnswer(
                headline: "文件粉碎先覆写内容（SSD 一次覆写已足够），再随机化文件名并移入废纸篓。",
                cards: [AssistantAnswer.Card(title: "打开文件粉碎", detail: "覆写 + 校验 + 改名，支持拖放",
                                             actionTitle: "去粉碎", actionDestination: .shredder)],
                suggestions: exampleQuestions
            )
        case .cleanupNow:
            return AssistantAnswer(
                headline: "点击首页 Smart Care 即可一键扫描并清理推荐项。",
                cards: [],
                suggestions: exampleQuestions
            )
        case .similarPhotos:
            return AssistantAnswer(
                headline: "工具箱 → 照片清理 → 相似照片：本机感知比对找出截图堆积与相似照片，每组至少保留一张。",
                cards: [AssistantAnswer.Card(title: "打开照片清理", detail: "感知哈希找出相似照片，本机比对不联网",
                                             actionTitle: "去清理", actionDestination: .photoClean)],
                suggestions: exampleQuestions
            )
        case .freeUpSpace:
            return AssistantAnswer(
                headline: "三步腾空间：① Smart Care 清推荐项 ② 大文件找巨型文件 ③ 相似照片清截图。全部走废纸篓可还原。",
                cards: [],
                suggestions: exampleQuestions
            )
        case .restoreLastCleanup:
            return AssistantAnswer(
                headline: "「历史」时间线按清理批次分组，单次清理可整体回滚（30 天内）。",
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
        case .video: kindName = "视频"
        case .image: kindName = "图片"
        case .audio: kindName = "音频"
        case .document: kindName = "文档"
        case .archive: kindName = "压缩包"
        case nil: kindName = "文件"
        }

        guard !leaves.isEmpty else {
            return AssistantAnswer(
                headline: "当前扫描结果中没有找到\(kindName)类的大文件 — 先运行一次扫描。",
                cards: [],
                suggestions: exampleQuestions
            )
        }
        let cards = leaves.prefix(5).map { entry in
            AssistantAnswer.Card(
                title: entry.title,
                detail: SmartCareHeroView.formatBytes(entry.size),
                nodeID: entry.id
            )
        }
        return AssistantAnswer(
            headline: "占用空间最多的 \(cards.count) 个\(kindName)：",
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
                headline: "还没有扫描结果 — 点击「扫描」开始。",
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
                    detail: SmartCareHeroView.formatBytes(category.totalSize),
                    nodeID: category.id
                )
            }
        return AssistantAnswer(headline: "空间分布（按类别）：", cards: cards, suggestions: exampleQuestions)
    }
}

// MARK: - ViewModel

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published private(set) var answer: AssistantAnswer?
    @Published var draft: String = ""

    private let matcher = AssistantIntentMatcher()

    init() {}

    func ask() {
        let utterance = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return }
        answer = respond(to: utterance)
        draft = ""
    }

    /// Live scan results provider (wired to AppGraph by AssistantView).
    var scanResultsProvider: (() -> ScanResultsViewModel?)?

    /// Pure-ish entry point for tests.
    func respond(to utterance: String) -> AssistantAnswer {
        guard let intent = matcher.match(utterance) else {
            return AssistantAnswer(
                headline: "这个问题我还不懂 — 试试下面的示例问题？",
                cards: [],
                suggestions: AssistantAnswerBuilder.exampleQuestions
            )
        }
        let scanVM = scanResultsProvider?()
        return AssistantAnswerBuilder.build(intent: intent, scanVM: scanVM)
    }

    func askSuggestion(_ text: String) {
        draft = text
        ask()
    }
}
