// kWise/Features/Anatomy/QuickCleanHeroStates.swift
//
// P2 T9 fix r1 — 画布 hero 的快捷回收门控与结果态（controller 裁定恢复）。
//
// fix r1（Critical 1）：仅 container 权限的用户点「安全快捷回收」会跑一次
// 无意义的管线（扫描只能看到容器内几乎什么都扫不到）。门控回到 UI 层：
// container-only 时 hero 的快捷回收位渲染授权卡（grant 按钮 + 已授权反馈
// + 暂不授权），授权后才出现快捷回收按钮 —— 与被 P2 T9 退役的快捷回收
// 页 `scopeGrantCard`（controller ruling R1）同模式。
//
// fix r1（Important 2）：快捷回收的结果态回到画布 hero —— `.done` 显示
// 「已释放 X」（C-3 真实字节）+「移入废纸篓 · 30 天可还原」诚实披露行；
// `.failed` 显示失败信息。数秒后或用户点「好」回到 idle（状态机由
// SmartCareViewModel.reset() 复位）。
//
// 红线：本文件零清理动作 —— 授权卡只调 AppScope.grant()（PowerScope
// 书签授权），结果卡只复位状态机；执行仍必经根部统一预演链（P2 T5）。
import SwiftUI
import PowerScope
import DesignSystem

// MARK: - 门控（纯逻辑，测试钉住）

/// 快捷回收的授权门控。管线启动权（RootView onQuickClean / 菜单栏
/// quickClean）与按钮渲染权（AnatomyView hero）都必须经过这里。
enum QuickCleanGate {
    /// container-only 时不允许启动快捷回收管线（扫描将一无所获）。
    static func allowsPipeline(_ level: ScopeLevel) -> Bool {
        level == .homeGranted
    }

    /// container-only 时 hero 的快捷回收位渲染授权卡。
    static func showsGrantCard(_ level: ScopeLevel) -> Bool {
        level == .containerOnly
    }
}

// MARK: - 授权卡（container-only 时的快捷回收位）

struct QuickCleanGrantCard: View {
    /// 授权动作（注入 AppScope.grant 的包装，便于预览/测试）。
    let onGrant: () -> Void
    /// 「暂不授权」——收起卡片；快捷回收保持不可用（诚实降级）。
    let onSkip: () -> Void
    /// 授权请求已发出（NSOpenPanel 期间按钮防重入）。
    var isGranting = false

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "lock.open")
                .font(.system(size: 32))
                .foregroundStyle(Color.brandAccent)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("canvas.grant.title")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("canvas.grant.subtitle")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(action: onGrant) {
                Text("canvas.grant.button")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGranting)
            Button(action: onSkip) {
                Text("canvas.grant.skip")
            }
            .buttonStyle(.bordered)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

/// 「暂不授权」后的诚实降级行：没有假按钮，保留再授权入口。
struct QuickCleanGrantDeclinedRow: View {
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "lock")
                .foregroundStyle(Color.textSecondary)
            Text("canvas.grant.declined")
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button(action: onGrant) {
                Text("canvas.grant.button")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - 结果卡（done / failed）

/// 结果卡文案（纯函数，测试钉住字节行渲染）。
enum QuickCleanResultCopy {
    /// C-3：真实释放字节进标题行（与画布构成条/菜单栏同一格式化口径）。
    static func doneTitle(freedBytes: Int64) -> String {
        String(format: String(localized: String.LocalizationValue("canvas.quickclean.done.title")),
               SharedByteFormat.formatBytes(freedBytes))
    }

    static var doneDetail: String {
        String(localized: String.LocalizationValue("canvas.quickclean.done.detail"))
    }

    static var failedTitle: String {
        String(localized: String.LocalizationValue("canvas.quickclean.failed.title"))
    }

    static var dismissTitle: String {
        String(localized: String.LocalizationValue("canvas.quickclean.result.dismiss"))
    }
}

/// hero 结果态卡：`.done(freedBytes)` / `.failed(message)` 两态。
struct QuickCleanResultCard: View {
    /// `.done` / `.failed` 才是本卡的承载态（宿主据此决定渲染）。
    static func isResultState(_ state: SmartCareState) -> Bool {
        if case .done = state { return true }
        if case .failed = state { return true }
        return false
    }

    let state: SmartCareState
    /// 用户点「好」→ 状态机复位回 idle（auto-dismiss 由宿主 task 驱动）。
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            switch state {
            case .done(let freedBytes, _):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.success)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(QuickCleanResultCopy.doneTitle(freedBytes: freedBytes))
                        .font(AppFont.title2)
                        .foregroundStyle(Color.textPrimary)
                    Text(QuickCleanResultCopy.doneDetail)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.warning)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(QuickCleanResultCopy.failedTitle)
                        .font(AppFont.title2)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            default:
                // 只承载结果态；非结果态传入属调用方契约错误，渲染空。
                EmptyView()
            }
            Spacer()
            Button(action: onDismiss) {
                Text(QuickCleanResultCopy.dismissTitle)
            }
            .buttonStyle(.bordered)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.brandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}
