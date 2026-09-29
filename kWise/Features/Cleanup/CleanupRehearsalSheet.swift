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
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var exemptedPaths: Set<String> = []

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
                        Spacer()
                        Text(FileSizeFormatter.abbreviated(from: item.target.size))
                            .font(AppFont.caption.monospaced())
                    }
                }
            }
            .frame(minHeight: 240)

            HStack {
                Text(String(format:
                    String(localized: String.LocalizationValue("attr.rehearsal.total")),
                    FileSizeFormatter.abbreviated(from: totalBytes),
                    confirmedItems.count, items.count))
                    .font(AppFont.body)
                Spacer()
                Button(role: .cancel) { onCancel() } label: { Text("attr.rehearsal.cancel") }
                Button { onConfirm() } label: { Text("attr.rehearsal.confirm") }
                    .disabled(confirmedItems.isEmpty)
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
            if item.attribution?.confidence == .certain,
               let ruleID = attribution.ruleID {
                Text(String(localized: String.LocalizationValue("attr.notes.\(ruleID)")))
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
}

/// sheet(item:) 载体 —— `[RehearsalItem]` 本身不是 `Identifiable`，
/// 包一层并每次预演生成新 id，保证关闭后再弹必然重建（勾选状态不跨面板残留）。
struct RehearsalSheetPayload: Identifiable {
    let id = UUID()
    let items: [RehearsalItem]
}
