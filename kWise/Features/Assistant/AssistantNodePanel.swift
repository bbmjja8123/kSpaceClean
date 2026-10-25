// kWise/Features/Assistant/AssistantNodePanel.swift
//
// 节点问答 (P1 T8) — the assistant chat surface (AssistantView, free-text
// input bar) is retired. Q&A now lives where the user already is: the
// selection detail panel. Zero network, no free-text input — the panel
// offers 4 suggested questions (each pinned by test to hit the matcher
// template table) and renders the answer cards. No match → honest refusal
// (C-5): the model returns nil and the view shows the refusal line instead
// of guessing an answer.
import SwiftUI
import DesignSystem

/// ViewModel behind the detail panel's embedded Q&A section.
///
/// `question → AssistantIntentMatcher.match → AssistantAnswerBuilder.build`
/// — the same deterministic two layers the old chat used, minus the draft
/// text field. `scanResultsProvider` hands the live `ScanResultsViewModel`
/// so data-backed answers (largest files / category summary) stay real.
@MainActor
final class AssistantNodePanelModel: ObservableObject {
    /// Suggested questions shown as chips. Every entry must hit the matcher
    /// template table — `testNodePanelAnswersFromMatcherWithoutChatInput`
    /// pins this (a suggestion the matcher can't answer is a broken promise).
    ///
    /// These strings double as **matcher queries** (they are fed straight to
    /// `AssistantIntentMatcher.match`), so they stay in the template table's
    /// language. UI rendering goes through ``displayText(for:)`` which maps
    /// each canonical question onto a localized chip label — English/Japanese
    /// users tap a translated chip while the matcher still sees a query it
    /// can answer.
    static let suggestedQuestions = [
        "哪些视频最占空间？",
        "磁盘什么时候会满？",
        "清理重复文件",
        "应用残留有哪些？",
    ]

    /// Canonical suggested question → localization key for its chip label.
    private static let displayKeys: [String: String] = [
        "哪些视频最占空间？": "assistant.node.q.videos",
        "磁盘什么时候会满？": "assistant.node.q.diskFull",
        "清理重复文件": "assistant.node.q.duplicates",
        "应用残留有哪些？": "assistant.node.q.appLeftovers",
    ]

    /// Localized chip label for a suggested question; injected question sets
    /// with no mapping render verbatim (they must hit the matcher themselves).
    static func displayText(for question: String) -> String {
        guard let key = displayKeys[question] else { return question }
        return String(localized: String.LocalizationValue(key))
    }

    /// Last built answer, if the last question was understood.
    @Published private(set) var answer: AssistantAnswer?
    /// True when the last question got the honest refusal (no matcher hit).
    @Published private(set) var refused = false
    /// 建议问题集（P2 T6 参数化）：默认即 `suggestedQuestions`（DetailPanel
    /// 行为不变）；复用方（如 T6 下钻页）可注入自己的问题集 —— 注入集同样
    /// 必须命中 matcher 模板表，否则就是给出永远答不了的问题。
    let questions: [String]

    private let matcher = AssistantIntentMatcher()
    private let scanResultsProvider: () -> ScanResultsViewModel?

    init(scanResultsProvider: @escaping () -> ScanResultsViewModel?,
         questions: [String] = AssistantNodePanelModel.suggestedQuestions) {
        self.scanResultsProvider = scanResultsProvider
        self.questions = questions
    }

    /// `nil` = honest "这个问题我答不了" (no fabricated answer, C-5).
    @discardableResult
    func answer(question: String) -> AssistantAnswer? {
        guard let intent = matcher.match(question) else {
            answer = nil
            refused = true
            return nil
        }
        refused = false
        let built = AssistantAnswerBuilder.build(intent: intent,
                                                 scanVM: scanResultsProvider())
        answer = built
        return built
    }
}

/// The embedded Q&A section: suggestion chips + answer card, sized for the
/// narrow (≤280 pt) detail panel — chips stack vertically, card rows wrap.
struct AssistantNodePanelView: View {
    @ObservedObject var model: AssistantNodePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("assistant.node.header")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(model.questions, id: \.self) { question in
                    Button {
                        model.answer(question: question)
                    } label: {
                        Text(AssistantNodePanelModel.displayText(for: question))
                            .font(AppFont.caption)
                            .foregroundStyle(Color.brandPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let answer = model.answer {
                answerCard(answer)
            } else if model.refused {
                Text("assistant.node.refusal")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func answerCard(_ answer: AssistantAnswer) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(answer.headline)
                .font(AppFont.caption)
                .foregroundStyle(Color.textPrimary)
            ForEach(answer.cards) { card in
                HStack(alignment: .firstTextBaseline) {
                    Text(card.title)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(card.detail)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}
