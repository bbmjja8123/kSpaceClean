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
    case dnsFlush = "Flush DNS cache"
    /// Rebuild Spotlight index to fix search anomalies.
    case spotlightRebuild = "Rebuild Spotlight index"
    /// Purge inactive memory to improve system responsiveness.
    case memoryPurge = "Purge inactive memory"
    /// Clear font cache to fix font rendering issues.
    case fontCacheRebuild = "Rebuild font cache"
    /// Rebuild Launch Services database to fix "Open With" issues.
    case launchServicesRebuild = "Rebuild Launch Services"
    /// Clear user log files to free disk space — engine-backed.
    case userLogClear = "Clean user logs"

    public var id: String { rawValue }

    /// Localized, user-visible task title (rendered on the maintenance row).
    public var title: String {
        switch self {
        case .dnsFlush:
            return String(localized: String.LocalizationValue("maintenance.task.dnsFlush.title"))
        case .spotlightRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.spotlightRebuild.title"))
        case .memoryPurge:
            return String(localized: String.LocalizationValue("maintenance.task.memoryPurge.title"))
        case .fontCacheRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.fontCacheRebuild.title"))
        case .launchServicesRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.launchServicesRebuild.title"))
        case .userLogClear:
            return String(localized: String.LocalizationValue("maintenance.task.userLogClear.title"))
        }
    }

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
            return String(localized: String.LocalizationValue("maintenance.task.dnsFlush.detail"))
        case .spotlightRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.spotlightRebuild.detail"))
        case .memoryPurge:
            return String(localized: String.LocalizationValue("maintenance.task.memoryPurge.detail"))
        case .fontCacheRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.fontCacheRebuild.detail"))
        case .launchServicesRebuild:
            return String(localized: String.LocalizationValue("maintenance.task.launchServicesRebuild.detail"))
        case .userLogClear:
            return String(localized: String.LocalizationValue("maintenance.task.userLogClear.detail"))
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
            ? String(localized: String.LocalizationValue("maintenance.note.engineBacked"))
            : String(localized: String.LocalizationValue("maintenance.note.terminalRequired"))
    }
}
