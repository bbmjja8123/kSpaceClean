// kWise/Features/Attribution/AttributionRulesView.swift
//
// 规则可查页（spec §5「规则开放」实体）：把 attribution_rules.json 渲染成人话。
// 用户能逐条看到我们据以判断的规则 —— 对抗「黑盒清理」的第一手证据。
import SwiftUI
import DesignSystem

struct AttributionRuleRow: Equatable, Identifiable {
    let id: String
    let pathGlob: String
    let ownerText: String
    let causeText: String
    let reclaimText: String
    let notesText: String
}

@MainActor
final class AttributionRulesViewModel: ObservableObject {
    @Published private(set) var rows: [AttributionRuleRow] = []

    func load(corpus: AttributionRuleCorpus) {
        rows = corpus.rules.map { rule in
            let glob = rule.match.pathGlob ?? ""
            let ownerText: String
            switch rule.owner {
            case .app(_, let appName): ownerText = appName ?? "bundleID"
            case .system: ownerText = "macOS"
            case .user: ownerText = AttributionCopy.ownerLabel(.user)
            // 语料里的 bundleDir 在运行时按最近 bundleID 目录解析（Task 5 引擎），
            // 规则页没有具体路径可解析 —— 诚实显示「未知归属」，不编造 App 名。
            case .bundleDir: ownerText = AttributionCopy.ownerLabel(.unknown)
            }
            return AttributionRuleRow(
                id: rule.id, pathGlob: glob, ownerText: ownerText,
                causeText: AttributionCopy.causeLabel(rule.cause),
                reclaimText: AttributionCopy.reclaimLabel(rule.reclaim),
                notesText: String(localized: String.LocalizationValue(rule.notesKey)))
        }
    }
}

struct AttributionRulesView: View {
    @StateObject private var viewModel = AttributionRulesViewModel()
    private let corpus: AttributionRuleCorpus

    init(corpus: AttributionRuleCorpus) {
        self.corpus = corpus
    }

    var body: some View {
        List {
            Section {
                Text("attr.rules.subtitle", tableName: nil)
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(viewModel.rows) { row in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(row.notesText)
                        .font(AppFont.body)
                    Text(row.pathGlob)
                        .font(AppFont.caption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: AppSpacing.sm) {
                        Text(row.causeText)
                        Text(row.reclaimText)
                        Text(row.ownerText)
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .navigationTitle(Text("attr.rules.title"))
        .onAppear { viewModel.load(corpus: corpus) }
    }
}
