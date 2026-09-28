// kWise/Features/Attribution/AttributionPreviewView.swift
//
// P0 验证面（TestFlight 北极星）：黑盒卡 + Top 项（理由可展开）+ 拒答清单。
// 刻意朴素 —— P1 的解剖视图会整体替换它；这里只承载「为什么」满意度的验证。
import SwiftUI
import DesignSystem
import CommonUtils

@MainActor
final class AttributionPreviewViewModel: ObservableObject {
    @Published private(set) var report: AttributionReport?
    @Published private(set) var isLoading = false

    private let service: AttributionService
    private var categoriesProvider: (() -> [ScanCategory])?

    init(service: AttributionService) {
        self.service = service
    }

    /// RootView 在 onAppear 注入（沿用 spaceMapViewModel.rebindRoots 模式）。
    func rebindCategories(_ provider: @escaping () -> [ScanCategory]) {
        categoriesProvider = provider
    }

    func refresh() async {
        guard let categoriesProvider, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        report = await service.attribute(categories: categoriesProvider())
    }

    var topItems: [SpaceAttribution] {
        (report?.items ?? []).sorted { $0.bytes > $1.bytes }.prefix(20).map { $0 }
    }

    var refusedItems: [SpaceAttribution] {
        (report?.refused ?? []).sorted { $0.bytes > $1.bytes }
    }
}

struct AttributionPreviewView: View {
    @StateObject private var viewModel: AttributionPreviewViewModel
    @State private var rulesCorpus: AttributionRuleCorpus?

    init(viewModel: AttributionPreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if let report = viewModel.report {
                blackBoxCard(report.blackBox)
                if report.snapshots == nil {
                    Text("attr.blackbox.unreadable")
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
                Section(header: Text("attr.preview.top")) {
                    ForEach(viewModel.topItems) { item in
                        attributionRow(item)
                    }
                }
                Section(header: Text(String(
                    format: String(localized: String.LocalizationValue("attr.refused.title")),
                    viewModel.refusedItems.count))) {
                    Text("attr.refused.banner")
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(viewModel.refusedItems) { item in
                        attributionRow(item)
                    }
                }
                if let corpus = rulesCorpus {
                    Section {
                        NavigationLink {
                            AttributionRulesView(corpus: corpus)
                        } label: {
                            Text("attr.rules.title")
                        }
                    }
                }
            } else {
                Text("attr.preview.empty")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle(Text("attr.preview.title"))
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("attr.preview.refresh")
            }
            .disabled(viewModel.isLoading)
        }
        .task { loadCorpusAndRefresh() }
    }

    private func loadCorpusAndRefresh() {
        if rulesCorpus == nil {
            rulesCorpus = (Bundle.main.url(forResource: "attribution_rules",
                                           withExtension: "json"))
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? AttributionRuleCorpus.load(from: $0) }
        }
        Task { await viewModel.refresh() }
    }

    @ViewBuilder
    private func blackBoxCard(_ breakdown: BlackBoxBreakdown) -> some View {
        Section(header: Text("attr.blackbox.title")) {
            switch breakdown.status {
            case .reconciled:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.residual")),
                    FileSizeFormatter.abbreviated(from: breakdown.residualBytes)))
                if breakdown.snapshotCount > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.snapshots")),
                        breakdown.snapshotCount))
                }
            case .negativeResidual:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.residual")),
                    FileSizeFormatter.abbreviated(from: 0)))
            case .insufficientData:
                Text("attr.blackbox.insufficient")
            }
        }
    }

    @ViewBuilder
    private func attributionRow(_ item: SpaceAttribution) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                    // （T5 审查裁定，Task 9 落实）证据链恒 4 元：`.lastModified`
                    // 在无日期时 `arguments` 为空数组。此时 `attr.ev.lastModified`
                    // 的 %@ 会以字面量露出（"最后修改 %@"）—— 渲染成空参数行属
                    // 禁止项，因此直接隐藏该行，不渲染占位文案。
                    if evidence.kind == .lastModified, evidence.arguments.isEmpty {
                        EmptyView()
                    } else {
                        Text(AttributionCopy.evidenceText(evidence))
                            .font(AppFont.callout)
                    }
                }
                // （T8 交接）拒答清单混有「规则不敢判」（ruleID 非 nil）与
                // 「未匹配大项」（ruleID == nil）两种来源；notesText 对后者
                // 返回空串 —— 不渲染空 notes 行，即区分开两类条目。
                if !item.notesText.isEmpty {
                    Text(item.notesText)
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AttributionCopy.ownerLabel(item.owner))
                        .font(AppFont.body)
                    Text(AttributionCopy.causeLabel(item.cause))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(FileSizeFormatter.abbreviated(from: item.bytes))
                    .font(AppFont.caption.monospaced())
            }
        }
    }
}

extension SpaceAttribution {
    /// 行内展开的理由链尾行：规则 note（xcstrings key 装配）。
    var notesText: String {
        guard let ruleID else { return "" }
        return String(localized: String.LocalizationValue("attr.notes.\(ruleID)"))
    }
}
