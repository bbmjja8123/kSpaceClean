// kWise/Features/Anatomy/GroupDrillDownView.swift
//
// 分组下钻页（P2 T6，spec §6）：组卡点击区进入的文件级控制面。
// 结构（自上而下）：面包屑（← 解剖 / 组名）→ 组头（icon + 标题 + 诚实字节）
// → 文件级列表（名称 / 位置 / 五色徽章 / 勾选框；默认勾选态按徽章 —— 绿 ✓
// 可回收勾上，其余一律不勾，C4）→ 节点问答（AssistantNodePanel 复用，T8）
// → 底部「预演并清理」（勾选集 → 注入的 onRehearse → 根部统一预演 sheet）。
//
// 红线：本页零清理动作 —— 预演按钮只把勾选集的 targets 交给宿主回调，
// 执行必经 CleanupViewModel.makeRehearsal(targets:) → 确认 →
// executeConfirmedCleanup 的统一预演链（P2 T5 R-统一；1:1 契约 P1 继承）。
//
// 勾选态归 VM（GroupDrillDownModel）所有：面包屑返回销毁视图后再进同一组，
// 由 AnatomyViewModel 的缓存取回同一份 VM —— 勾选原样保留（VM 级契约）。
import SwiftUI
import DesignSystem
import CommonUtils

// MARK: - 勾选态 VM（面包屑返回保持勾选的载体）

/// 下钻页勾选态 VM：`checked` 是唯一事实源，视图只渲染。
/// 默认勾选态按徽章（C4）：`.recyclable` 勾上，其余（迁出/注意/数据/不动）
/// 一律不勾 —— 绝不默认把不确定的项带进清理集。
@MainActor
final class GroupDrillDownModel: ObservableObject {
    /// 所属组（面包屑副行 / 头部渲染）。
    let group: CanvasGroup
    /// 下钻条目全量（cause 组 = 树切片结果；detection 组 = 组内全量）。
    let entries: [CanvasEntry]
    /// 勾选集（entry.id）。
    @Published private(set) var checked: Set<UUID>
    /// QuickLook 可预览缓存（entry.id → 可预览）。`entries` 是 `let` 且
    /// init 之后无任何重设路径，缓存在 init 时一次性冻结 —— 行渲染 /
    /// Space 键取 URL 只查表，绝不在 SwiftUI body 重求值里做文件系统 stat
    /// （每次勾选切换逐行 stat = 主线程卡顿）。
    private let quickLookEligible: [UUID: Bool]

    init(group: CanvasGroup, entries: [CanvasEntry]) {
        self.group = group
        self.entries = entries
        self.checked = Set(entries.filter { $0.badge == .recyclable }.map(\.id))
        var eligible: [UUID: Bool] = [:]
        eligible.reserveCapacity(entries.count)
        for entry in entries {
            eligible[entry.id] = entry.target.map { KWQuickLookEligibility.isPreviewable($0.url) } ?? false
        }
        self.quickLookEligible = eligible
    }

    /// 条目是否可预览（init 时缓存的判定；未知 id 诚实返回 false）。
    func isPreviewable(_ id: UUID) -> Bool { quickLookEligible[id] ?? false }

    func isChecked(_ id: UUID) -> Bool { checked.contains(id) }

    func setChecked(_ id: UUID, _ value: Bool) {
        if value { checked.insert(id) } else { checked.remove(id) }
    }

    func toggle(_ id: UUID) { setChecked(id, !isChecked(id)) }

    /// 勾选集 → 预演 targets：按 entries 顺序 1:1 映射（用户显式勾选的
    /// 非 recyclable 项如实进预演 —— C4 只约束默认态；risk 元数据原样
    /// 携带，由预演 sheet 呈现风险），无 target 的条目跳过。
    var checkedTargets: [CleanupTarget] {
        entries.filter { checked.contains($0.id) }.compactMap(\.target)
    }

    /// 勾选集 → 预演条目（I1，P2 final）：与 `checkedTargets` 同序同过滤，
    /// 但保留 `CanvasEntry` 整体 —— 预演 sheet 需要徽章才能把非绿徽条目
    /// 默认豁免（C4 违约修复）。
    var checkedEntries: [CanvasEntry] {
        entries.filter { checked.contains($0.id) && $0.target != nil }
    }

    /// 勾选集的诚实字节合计 —— 只计带 target 的条目（无 target 的勾选项
    /// 既不预演也不计入，不夸大）。
    var checkedBytes: Int64 {
        entries.filter { checked.contains($0.id) && $0.target != nil }
            .reduce(0) { $0 + $1.bytes }
    }
}

// MARK: - 数据切片（spec §6：原树结构不变，视图按组切片）

/// 下钻页条目来源：cause 组从扫描树按 cause 切片（复用
/// `AttributionService.flatten` 全树展开 + 归因引擎的 cause 映射）；
/// detection 组（重复/相似照片/大文件）直接用 `CanvasGroup.entries`
/// （T2 组装器已产全量，无需重扫）。
enum GroupDrillDownSource {
    static func entries(for group: CanvasGroup,
                        categories: [ScanCategory],
                        engine: AttributionRuleEngine) -> [CanvasEntry] {
        switch group.id {
        case .cause(let cause):
            var results: [ScanResult] = []
            for category in categories {
                AttributionService.flatten(category, into: &results)
            }
            let sliced = CanvasGroupAssembler.deduplicate(entries:
                engine.attribute(results: results)
                    .filter { $0.cause == cause && $0.reclaim != .uncertain }
                    .compactMap { CanvasGroupAssembler.causeEntry(from: $0) })
            // 引擎切片为空（语料缺失 / 树已清）时回退组内全量条目 ——
            // 组卡本就由同一条 flatten→归因管线产出，两者同源，不是伪造。
            return sliced.isEmpty ? group.entries : sliced
        case .duplicates, .similarPhotos, .largeFiles:
            return group.entries
        }
    }
}

// MARK: - View

struct GroupDrillDownView: View {
    let group: CanvasGroup
    /// 下钻条目（cause 组 = 树切片；detection 组 = CanvasEntry 全量）。
    let entries: [CanvasEntry]
    /// 底部「预演并清理」回调 —— 勾选集的条目（target + 徽章）直入根部
    /// 统一预演 sheet（I1：徽章随条目进预演，非绿徽默认豁免）。
    let onRehearse: ([CanvasEntry]) -> Void
    /// 面包屑「← 解剖」回调（宿主关闭下钻页；默认空实现便于预览/测试）。
    var onBack: () -> Void = {}
    /// 节点问答的数据源（扫描页 VM 弱引用；nil 时诚实降级为无数据答案卡）。
    var scanResultsProvider: () -> ScanResultsViewModel? = { nil }

    // 勾选态 VM：宿主传缓存（面包屑返回保持勾选），未传时自建（预览/测试）。
    @StateObject private var model: GroupDrillDownModel
    @StateObject private var nodePanel: AssistantNodePanelModel
    /// QuickLook sheet 当前预览的文件（eye 按钮 / Space 键共同写入）。
    @State private var quickLookURL: URL?

    init(group: CanvasGroup,
                entries: [CanvasEntry],
                onRehearse: @escaping ([CanvasEntry]) -> Void,
                onBack: @escaping () -> Void = {},
                scanResultsProvider: @escaping () -> ScanResultsViewModel? = { nil },
                selectionModel: GroupDrillDownModel? = nil) {
        self.group = group
        self.entries = entries
        self.onRehearse = onRehearse
        self.onBack = onBack
        self.scanResultsProvider = scanResultsProvider
        _model = StateObject(wrappedValue:
            selectionModel ?? GroupDrillDownModel(group: group, entries: entries))
        _nodePanel = StateObject(wrappedValue:
            AssistantNodePanelModel(scanResultsProvider: scanResultsProvider))
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    header
                    fileList
                    Divider()
                    // 节点问答（T8 复用组件）——「关于这组空间」的就地问答。
                    AssistantNodePanelView(model: nodePanel)
                }
                .padding(AppSpacing.md)
            }
            Divider()
            bottomBar
        }
        .background(Color.bgPrimary)
    }

    // MARK: 面包屑（← 解剖 / 组名）

    private var breadcrumb: some View {
        HStack(spacing: AppSpacing.xs) {
            Button(action: onBack) {
                Label("canvas.drilldown.back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandPrimary)
            .help("canvas.drilldown.back")
            Text(group.title)
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(FileSizeFormatter.abbreviated(from: group.totalBytes))
                .font(AppFont.monoDigit)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(AppSpacing.sm)
    }

    // MARK: 组头

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: group.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(AppFont.title3)
                if !group.subtitle.isEmpty {
                    Text(group.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            Text(String(
                format: String(localized: String.LocalizationValue("canvas.entry.count")),
                model.entries.count))
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: 文件级列表（名称 / 位置 / 五色徽章 / 勾选框）

    private var fileList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(model.entries) { entry in
                row(entry)
            }
        }
        // QuickLook sheet 挂在列表层（每行 eye 按钮写 binding）；Space 键
        // 处理器同层只挂一次。既有 KWQuickLookSpaceHandler 的闭包只回传
        // URL、不写 binding —— 这里在闭包内显式落 quickLookURL。
        .kwQuickLookPreview($quickLookURL)
        .kwQuickLookSpaceHandler {
            let url = selectedRowURL()
            quickLookURL = url
            return url
        }
    }

    private func row(_ entry: CanvasEntry) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Toggle(isOn: Binding(
                get: { model.isChecked(entry.id) },
                set: { model.setChecked(entry.id, $0) })) {
                HStack(spacing: AppSpacing.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(AppFont.callout)
                            .lineLimit(1)
                            .help(entry.title)
                        if let detail = entry.detail {
                            Text(detail)
                                .font(AppFont.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(detail)
                        }
                    }
                    Spacer(minLength: AppSpacing.sm)
                    badgeView(entry.badge)
                    Text(FileSizeFormatter.abbreviated(from: entry.bytes))
                        .font(AppFont.numberCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toggleStyle(.checkbox)
            // A11y 审计：裸 Toggle 的可读内容散在标签子视图里——显式 label 用
            // 条目标题，VoiceOver 焦点语义才稳定（与预演 sheet 同口径）。
            .accessibilityLabel(Text(entry.title))
            // 预览按钮（行尾）：只有文件系统里真实存在的常规文件才渲染 ——
            // 目录 / 虚拟条目 / 已消失路径诚实降级为不可预览。可预览性取
            // VM 的 init 缓存，不在 body 重求值里 stat。
            if let url = entry.target?.url, model.isPreviewable(entry.id) {
                Button {
                    quickLookURL = url
                } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: String.LocalizationValue("drill.quicklook.help")))
                .accessibilityLabel(Text(String(localized: String.LocalizationValue("drill.quicklook.help"))))
            }
        }
    }

    /// Space 键的预览目标：勾选集中第一个可预览 target，无则取首行可预览
    /// 项；全部不可预览返回 nil（Space 静默，不出错）。可预览性与行渲染
    /// 同源——只查 VM 的 init 缓存，不在按键路径 stat。
    private func selectedRowURL() -> URL? {
        func previewableURL(_ entry: CanvasEntry) -> URL? {
            guard model.isPreviewable(entry.id),
                  let url = entry.target?.url else { return nil }
            return url
        }
        if let checked = model.entries.first(where: {
            model.isChecked($0.id) && previewableURL($0) != nil
        }) {
            return previewableURL(checked)
        }
        return model.entries.lazy.compactMap(previewableURL).first
    }

    /// 五色徽章 —— 语义映射复用组卡的 `CanvasGroupCardCopy`（色 / Symbol /
    /// 文案三张映射表本就由测试钉住，不另起一份）。
    private func badgeView(_ badge: BadgeKind) -> some View {
        HStack(spacing: 2) {
            Image(systemName: CanvasGroupCardCopy.symbol(for: badge))
            Text(CanvasGroupCardCopy.badgeTitle(for: badge))
        }
        .font(AppFont.caption)
        .foregroundStyle(CanvasGroupCardCopy.color(for: badge))
    }

    // MARK: 底部「预演并清理」（勾选集）

    private var bottomBar: some View {
        HStack {
            Text(String(
                format: String(localized: String.LocalizationValue("canvas.drilldown.selection")),
                model.checkedTargets.count,
                FileSizeFormatter.abbreviated(from: model.checkedBytes)))
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button {
                onRehearse(model.checkedEntries)
            } label: {
                Text("canvas.drilldown.rehearse")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.checkedTargets.isEmpty)
        }
        .padding(AppSpacing.sm)
    }
}

// MARK: - AnatomyViewModel 下钻缓存（面包屑返回保持勾选）

extension AnatomyViewModel {

    /// 取（或建）一组的勾选态 VM —— 面包屑返回后再进同一组，取回的是
    /// 同一份实例，勾选原样保留。plain var 存储 + 非 @Published：body 内
    /// 首次创建的插入不触发 objectWillChange（勾选变化由 VM 自己发布）。
    func drillDownModel(for group: CanvasGroup,
                        entries: [CanvasEntry]) -> GroupDrillDownModel {
        if let cached = drillDownModels[group.id] { return cached }
        let created = GroupDrillDownModel(group: group, entries: entries)
        drillDownModels[group.id] = created
        return created
    }
}
