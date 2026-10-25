// kWise/Features/Anatomy/CanvasGroupCard.swift
//
// 画布组卡（P2 T3，spec §3.4 / §8）：icon + title + subtitle（诚实定性）
// + totalBytes + 动作按钮。按钮文案/行为由 `GroupAction` 决定：
//   .rehearse → 「就地清理」（回调 onRehearse —— T5 接预演链，本任务
//               只注入 closure，视图自身零清理动作）
//   .guidance → 「正确解法」（弹命令面板，展示 reclaim.via 的终端命令）
//   .migrate  → 「迁出引导」（弹迁出说明面板）
//   .none     → 无按钮
// 展开态（默认展开前 2 组，由父视图传 initiallyExpanded）显示组内条目 +
// 五色徽章；条目在**渲染层**截断（prefix(displayEntryLimit) + 「还有 N 项」
// 行）—— 数据层 `CanvasGroup.entries` 保持全量（T6 下钻契约，T2 fix r1）。
import SwiftUI
import DesignSystem
import CommonUtils

/// 组卡的纯映射表（测试钉住；文案改动不破坏映射契约）。
public enum CanvasGroupCardCopy {

    /// GroupAction → 按钮文案；`.none` → nil（无按钮）。
    public static func actionTitle(for action: GroupAction) -> String? {
        switch action {
        case .rehearse:
            return String(localized: String.LocalizationValue("canvas.action.rehearse"))
        case .guidance:
            return String(localized: String.LocalizationValue("canvas.action.guidance"))
        case .migrate:
            return String(localized: String.LocalizationValue("canvas.action.migrate"))
        case .none:
            return nil
        }
    }

    /// 五色徽章 → 语义色（spec §8：绿 ✓ / 蓝 迁出 / 橙 ⚠ / 红 数据 / 灰 不动）。
    public static func color(for badge: BadgeKind) -> Color {
        switch badge {
        case .recyclable: return .success
        case .migrate: return .brandSecondary
        case .attention: return .warning
        case .dataNotJunk: return .danger
        case .leaveAlone: return .textSecondary
        }
    }

    /// 五色徽章 → SF Symbol。
    public static func symbol(for badge: BadgeKind) -> String {
        switch badge {
        case .recyclable: return "checkmark.circle"
        case .migrate: return "arrow.up.right.square"
        case .attention: return "exclamationmark.triangle"
        case .dataNotJunk: return "externaldrive.fill"
        case .leaveAlone: return "hand.raised"
        }
    }

    /// 五色徽章 → 文案（spec §8 文案系统；key 由测试钉住）。
    public static func badgeTitle(for badge: BadgeKind) -> String {
        switch badge {
        case .recyclable:
            return String(localized: String.LocalizationValue("canvas.badge.recyclable"))
        case .migrate:
            return String(localized: String.LocalizationValue("canvas.badge.migrate"))
        case .attention:
            return String(localized: String.LocalizationValue("canvas.badge.attention"))
        case .dataNotJunk:
            return String(localized: String.LocalizationValue("canvas.badge.dataNotJunk"))
        case .leaveAlone:
            return String(localized: String.LocalizationValue("canvas.badge.leaveAlone"))
        }
    }
}

public struct CanvasGroupCard: View {
    public let group: CanvasGroup
    /// 父视图决定默认展开（spec：默认展开前 2 组）；卡片内仍可手动开合。
    public let initiallyExpanded: Bool
    /// 「就地清理」回调 —— T5 接组过滤预演链；本任务注入空实现（视图零清理动作）。
    public var onRehearse: ((CanvasGroup) -> Void)?

    @State private var isExpanded: Bool
    @State private var guidanceText: String = ""
    @State private var showsGuidance = false

    public init(group: CanvasGroup,
                initiallyExpanded: Bool = false,
                onRehearse: ((CanvasGroup) -> Void)? = nil) {
        self.group = group
        self.initiallyExpanded = initiallyExpanded
        self.onRehearse = onRehearse
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    /// 渲染层截断：只显示前 `displayEntryLimit` 条（可测纯函数）。
    public static func displayEntries(in group: CanvasGroup) -> [CanvasEntry] {
        Array(group.entries.prefix(CanvasGroup.displayEntryLimit))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            header
            if isExpanded {
                entriesList
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(Color.bgSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .strokeBorder(Color.separatorColor.opacity(0.6), lineWidth: 1)
        )
        // A11y 审计：整卡可点（宿主 AnatomyView 的 onTapGesture 下钻）——
        // 合并为单个可聚焦元素并暴露按钮特征 + 下钻 hint；卡内「就地清理」
        // 与展开箭头 Button 在合并元素上保留为自定义动作，语义不丢。
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: String.LocalizationValue("canvas.group.a11y.drillHint"))))
        .sheet(isPresented: $showsGuidance) {
            GuidancePanel(text: guidanceText, showsCommand: showsCommandHint)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: group.icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(AppFont.title3)
                Text(group.subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: AppSpacing.sm)
            Text(FileSizeFormatter.abbreviated(from: group.totalBytes))
                .font(AppFont.monoDigit)
                .foregroundStyle(Color.textSecondary)
            actionButton
            Button {
                withAnimation(.easeInOut(duration: KFAnimation.durationFast)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded
                  ? String(localized: String.LocalizationValue("canvas.card.collapse"))
                  : String(localized: String.LocalizationValue("canvas.card.expand")))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch group.action {
        case .rehearse:
            Button {
                onRehearse?(group)
            } label: {
                Text(CanvasGroupCardCopy.actionTitle(for: .rehearse) ?? "")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .guidance(let text):
            Button {
                guidanceText = text
                showsGuidance = true
            } label: {
                Text(CanvasGroupCardCopy.actionTitle(for: group.action) ?? "")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .migrate:
            Button {
                guidanceText = String(
                    localized: String.LocalizationValue("canvas.guidance.migrate.body"))
                showsGuidance = true
            } label: {
                Text(CanvasGroupCardCopy.actionTitle(for: group.action) ?? "")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .none:
            EmptyView()
        }
    }

    /// `.guidance` 面板展示终端命令；`.migrate` 面板展示迁出说明。
    private var showsCommandHint: Bool {
        if case .guidance = group.action { return true }
        return false
    }

    // MARK: Entries（展开态）

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(Self.displayEntries(in: group)) { entry in
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
            if group.truncatedCount > 0 {
                Text(String(
                    format: String(localized: String.LocalizationValue("canvas.entry.more")),
                    group.truncatedCount))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func badgeView(_ badge: BadgeKind) -> some View {
        HStack(spacing: 2) {
            Image(systemName: CanvasGroupCardCopy.symbol(for: badge))
            Text(CanvasGroupCardCopy.badgeTitle(for: badge))
        }
        .font(AppFont.caption)
        .foregroundStyle(CanvasGroupCardCopy.color(for: badge))
    }
}

// MARK: - 命令 / 迁出引导面板

/// `.guidance`（终端命令，如 tmutil）与 `.migrate`（迁出说明）共用的
/// 只读面板。零网络、零执行 —— 命令只展示，用户自行复制。
struct GuidancePanel: View {
    let text: String
    let showsCommand: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("canvas.guidance.title")
                .font(AppFont.title3)
            Text(showsCommand
                 ? String(localized: String.LocalizationValue("canvas.guidance.command.hint"))
                 : String(localized: String.LocalizationValue("canvas.guidance.migrate.intro")))
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
            Text(text)
                .font(AppFont.monoDigit)
                .textSelection(.enabled)
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .fill(Color.bgTertiary.opacity(0.6))
                )
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("canvas.guidance.done")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 460)
    }
}
