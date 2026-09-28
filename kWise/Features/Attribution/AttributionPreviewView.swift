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
                blackBoxCard(report)
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
                // final review M6：清单为空时整段折叠 —— 「（0 项）」的空 header
                // 与「这些项判断不了」横幅在无内容时都是噪音，且与事实不符。
                if !viewModel.refusedItems.isEmpty {
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

    /// final review I1：诚实化重写。旧卡「黑盒空间（快照与系统保留）」是错误归类 ——
    /// 扫描树只覆盖 8 个清理类目根，残差 ≈ 全部普通用户数据（文档/照片/应用/系统区域），
    /// 把它叫「快照与系统保留」是对用户数据的误导。新卡只陈述事实：
    /// 这部分空间在本次扫描范围之外、不是垃圾；快照数与未匹配小项在 >0 时如实补充。
    @ViewBuilder
    private func blackBoxCard(_ report: AttributionReport) -> some View {
        let breakdown = report.blackBox
        Section(header: Text("attr.blackbox.uncovered.title")) {
            switch breakdown.status {
            case .reconciled:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.uncovered.body")),
                    FileSizeFormatter.abbreviated(from: breakdown.residualBytes)))
                if report.unattributedBytes > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.unattributed")),
                        FileSizeFormatter.abbreviated(from: report.unattributedBytes)))
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
                if breakdown.snapshotCount > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.snapshots")),
                        breakdown.snapshotCount))
                        .font(AppFont.callout)
                        .foregroundStyle(Color.textSecondary)
                }
            case .negativeResidual:
                // final review I3：残差为负说明口径对不上（如 purgeable 重复计入），
                // 此时没有任何可信数字 —— 诚实承认数据不足，绝不伪造「约 0 B」。
                Text("attr.blackbox.insufficient")
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
