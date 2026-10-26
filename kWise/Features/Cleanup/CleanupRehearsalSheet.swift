// kWise/Features/Cleanup/CleanupRehearsalSheet.swift
//
// 清理预演（spec §5 Rehearsal）：执行前的最后一道人签。逐项 = 路径 + 大小 +
// 风险徽章 + 「为什么可以回收」（归因在）或诚实「无归因信息」（归因缺）。
// 红线：确认只执行预演过的清单——sheet 关闭即作废，不缓存跨面板。
import SwiftUI
import DesignSystem
import CommonUtils

struct CleanupRehearsalSheet: View {
    let items: [RehearsalItem]
    /// 预演语境（P2 T5 统一句式）：组头入口带组名（如「应用缓存」），
    /// hero 快捷回收 / 下钻入口为 nil。只作说明副行，确认/执行契约不变。
    var context: String? = nil
    /// r1 fix（Critical 1）：确认必须**携带被勾选的子集** —— sheet 的
    /// exempt 勾选只改本地显示集合，执行方（VM）不知道它；因此 onConfirm
    /// 传出 `confirmedItems` 的 targets，执行集合以传入为准。
    let onConfirm: ([CleanupTarget]) -> Void
    let onCancel: () -> Void
    /// r1 fix（Important 3）：执行中禁用确认按钮（双击守卫的 UI 侧，
    /// VM 侧另有同步 `isCleaning` 守卫兜底）。
    var isExecuting: Bool = false
    /// Task 6（预演安全感叙事）：true = 条目来自废纸篓的永久处置路径，
    /// 页脚必须诚实标注「不可回滚」；false（默认）= 移入废纸篓，30 天
    /// 内可回滚（History 入口）。机制本任务落地，垃圾桶来源组由后续任务置 true。
    let isPermanent: Bool
    /// I1（P2 final）：初始豁免集 = 带非 `.recyclable` 徽章的条目（C4）——
    /// 「数据·不属垃圾」等项绝不默认进清理集；无徽章条目默认勾选。
    @State private var exemptedPaths: Set<String>

    init(items: [RehearsalItem],
         context: String? = nil,
         onConfirm: @escaping ([CleanupTarget]) -> Void,
         onCancel: @escaping () -> Void,
         isExecuting: Bool = false,
         isPermanent: Bool = false) {
        self.items = items
        self.context = context
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.isExecuting = isExecuting
        self.isPermanent = isPermanent
        _exemptedPaths = State(initialValue: CleanupRehearsal.defaultExemptedPaths(for: items))
    }

    private var confirmedItems: [RehearsalItem] {
        items.filter { !exemptedPaths.contains($0.target.url.path) }
    }
    private var totalBytes: Int64 {
        confirmedItems.reduce(0) { $0 + $1.target.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("attr.rehearsal.title")
                .font(AppFont.title2)
            if let context {
                Text(context)
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("attr.rehearsal.banner")
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)

            List {
                ForEach(items) { item in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { !exemptedPaths.contains(item.target.url.path) },
                            set: { on in
                                if on { exemptedPaths.remove(item.target.url.path) }
                                else { exemptedPaths.insert(item.target.url.path) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.target.url.lastPathComponent)
                                    .font(AppFont.body)
                                reasonLine(item)
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        // A11y 审计：豁免 Toggle 需要显式 label（文件名 + 可回收
                        // 原因）与 hint——VoiceOver 用户才知道在勾什么、勾了会怎样。
                        .accessibilityLabel(Text("\(item.target.url.lastPathComponent)，\(reasonSpokenText(item))"))
                        .accessibilityHint(Text(String(localized: String.LocalizationValue("attr.rehearsal.a11y.exemptHint"))))
                        Spacer()
                        // I1：五色徽章列 —— 与画布/下钻行同一语义映射
                        //（CanvasGroupCardCopy，色/Symbol/文案三表测试钉住）。
                        if let badge = item.badge {
                            HStack(spacing: 2) {
                                Image(systemName: CanvasGroupCardCopy.symbol(for: badge))
                                Text(CanvasGroupCardCopy.badgeTitle(for: badge))
                            }
                            .font(AppFont.caption)
                            .foregroundStyle(CanvasGroupCardCopy.color(for: badge))
                            .help(CanvasGroupCardCopy.badgeTitle(for: badge))
                        }
                        Text(FileSizeFormatter.abbreviated(from: item.target.size))
                            .font(AppFont.caption.monospaced())
                    }
                }
            }
            .frame(minHeight: 240)

            // Task 6（预演安全感叙事）：页脚承诺行 —— 默认路径承诺 30 天
            // 废纸篓回滚（History 一键回滚）；垃圾桶来源的永久路径诚实
            // 标注不可回滚（不夸大、不隐瞒，C-6 同一口径）。置于总计行
            // 下方作小字 caption，不改变 560×480 固定布局预算。
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format:
                    String(localized: String.LocalizationValue("attr.rehearsal.total")),
                    FileSizeFormatter.abbreviated(from: totalBytes),
                    confirmedItems.count, items.count))
                    .font(AppFont.body)
                Text(String(localized: String.LocalizationValue(
                    isPermanent ? "attr.rehearsal.permanentNote" : "attr.rehearsal.rollbackNote")))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
            HStack {
                Spacer()
                Button(role: .cancel) { onCancel() } label: { Text("attr.rehearsal.cancel") }
                    .disabled(isExecuting)
                Button {
                    // 只把用户仍然勾选的子集交给执行方（r1 Critical 1）。
                    onConfirm(confirmedItems.map(\.target))
                } label: { Text("attr.rehearsal.confirm") }
                    .disabled(confirmedItems.isEmpty || isExecuting)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private func reasonLine(_ item: RehearsalItem) -> some View {
        if let attribution = item.attribution {
            // P0 契约：ruleID==nil 的拒答项/推测项不渲染 notes 行（诚实降级）。
            // r1 fix（Important 2）：key 先拼接再构造 LocalizationValue ——
            // 插值写法会把 key 变成 "attr.notes.%@"，查表必失配而渲染裸 key。
            if item.attribution?.confidence == .certain,
               let ruleID = attribution.ruleID {
                Text(String(localized: String.LocalizationValue("attr.notes." + ruleID)))
                    .lineLimit(2)
            } else if attribution.confidence == .probable {
                Text(String(format:
                    String(localized: String.LocalizationValue("attr.confidence.probable.reason")),
                    AttributionCopy.causeLabel(attribution.cause)))
            } else {
                Text("attr.rehearsal.noReason")
            }
        } else {
            Text("attr.rehearsal.noReason")
        }
    }

    /// reasonLine 的纯文本镜像（a11y label 用）：与 reasonLine 同一分支、
    /// 同一批 key（attr.notes.* / probable reason / noReason），口径不漂移。
    private func reasonSpokenText(_ item: RehearsalItem) -> String {
        guard let attribution = item.attribution else {
            return String(localized: String.LocalizationValue("attr.rehearsal.noReason"))
        }
        if attribution.confidence == .certain,
           let ruleID = attribution.ruleID {
            return String(localized: String.LocalizationValue("attr.notes." + ruleID))
        } else if attribution.confidence == .probable {
            return String(format:
                String(localized: String.LocalizationValue("attr.confidence.probable.reason")),
                AttributionCopy.causeLabel(attribution.cause))
        }
        return String(localized: String.LocalizationValue("attr.rehearsal.noReason"))
    }
}

/// sheet(item:) 载体 —— `[RehearsalItem]` 本身不是 `Identifiable`，
/// 包一层并每次预演生成新 id，保证关闭后再弹必然重建（勾选状态不跨面板残留）。
struct RehearsalSheetPayload: Identifiable {
    let id = UUID()
    let items: [RehearsalItem]
    /// 组头入口的组名等语境（nil = hero / 下钻入口）。
    var context: String? = nil
    /// Task 6：true = 永久路径（垃圾桶来源大项，后续任务接入）；
    /// false（默认）= 移入废纸篓可回滚。RootView 三处组装点均默认 false。
    var isPermanent: Bool = false
}
