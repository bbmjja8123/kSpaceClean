import Foundation

/// System maintenance tasks (v2.0 Phase 2 — sandbox-safe redesign).
///
/// The previous implementation shelled out via `Process` to `/usr/bin/mdutil`,
/// `killall`, `purge`, `atsutil`, `lsregister` — none of which can run inside
/// the App Sandbox, so every "run" either failed silently or lied (a C-5
/// violation). kWise is App Store-only and will not use privileged helpers,
/// so each task is now **guidance-only**: kWise explains the task, hands the
/// user a copy-paste Terminal command, and — where the target is inside the
/// user's granted scope (`~/Library/Logs`) — offers a real, engine-backed
/// action instead.
public enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    /// Flush DNS cache to resolve domain resolution issues.
    case dnsFlush = "刷新 DNS 缓存"
    /// Rebuild Spotlight index to fix search anomalies.
    case spotlightRebuild = "重建 Spotlight 索引"
    /// Purge inactive memory to improve system responsiveness.
    case memoryPurge = "释放内存"
    /// Clear font cache to fix font rendering issues.
    case fontCacheRebuild = "重建字体缓存"
    /// Rebuild Launch Services database to fix "Open With" issues.
    case launchServicesRebuild = "重建 Launch Services"
    /// Clear user log files to free disk space — engine-backed.
    case userLogClear = "清理用户日志"

    public var id: String { rawValue }

    /// SF Symbol name corresponding to the maintenance operation.
    public var icon: String {
        switch self {
        case .dnsFlush:
            return "antenna.radiowaves.left.and.right"
        case .spotlightRebuild:
            return "magnifyingglass"
        case .memoryPurge:
            return "memorychip"
        case .fontCacheRebuild:
            return "textformat"
        case .launchServicesRebuild:
            return "gearshape.2"
        case .userLogClear:
            return "doc.text.magnifyingglass"
        }
    }

    /// What this task does.
    public var detail: String {
        switch self {
        case .dnsFlush:
            return "清除 DNS 缓存记录，解决域名解析问题"
        case .spotlightRebuild:
            return "重新建立文件索引，修复搜索异常"
        case .memoryPurge:
            return "强制释放非活跃内存，提升系统响应速度"
        case .fontCacheRebuild:
            return "清除字体缓存，修复字体显示问题"
        case .launchServicesRebuild:
            return "重建应用注册信息，修复打开方式异常"
        case .userLogClear:
            return "将用户日志移入废纸篓，释放磁盘空间（可回滚）"
        }
    }

    /// Copy-paste command for Terminal. `nil` for engine-backed tasks.
    public var terminalCommand: String? {
        switch self {
        case .dnsFlush:
            return "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
        case .spotlightRebuild:
            return "sudo mdutil -E /"
        case .memoryPurge:
            return "sudo purge"
        case .fontCacheRebuild:
            return "sudo atsutil databases -remove && sudo atsutil server -shutdown && sudo atsutil server -ping"
        case .launchServicesRebuild:
            return "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
        case .userLogClear:
            return nil  // Engine-backed — kWise does this itself.
        }
    }

    /// `true` when kWise performs this task itself inside the granted scope
    /// (no Terminal needed). Only tasks under the user's own home qualify.
    public var isEngineBacked: Bool {
        self == .userLogClear
    }

    /// Honest sandbox note shown on every card (C-5: no pretending).
    public var sandboxNote: String {
        isEngineBacked
            ? "由 kWise 直接完成，移入废纸篓可回滚。"
            : "出于 App Store 沙箱限制，此项需在终端中执行。"
    }
}
