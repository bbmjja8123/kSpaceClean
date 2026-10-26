// kWise/Intents/KlarisShortcuts.swift
//
// App Shortcuts 注册（Task 10）：Spotlight 顶部结果 / Siri / 快捷指令
// 免配置入口。短语三语（en/zh-Hans/ja——匹配助手意图表的三语先例）。
import AppIntents

struct AskStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.askstatus.title"
    static let description = IntentDescription("intent.askstatus.description", categoryName: "Status")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 快照优先（App Group 内 15 分钟新鲜度），缺则现取。
        if let snap = WidgetSnapshotStore().read(), let disk = snap.disk {
            let used = ByteCountFormatter.string(fromByteCount: disk.usedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: Int64(disk.usedFraction == 0 ? 0 : Double(disk.usedBytes) / disk.usedFraction), countStyle: .file)
            var line = String(localized: String.LocalizationValue("intent.status.used"))
                .replacingOccurrences(of: "{used}", with: used)
                .replacingOccurrences(of: "{total}", with: total)
            if let forecast = snap.forecast, forecast.isReliable {
                line += "\n" + String(localized: String.LocalizationValue("intent.status.forecast"))
                    .replacingOccurrences(of: "{days}", with: "\(forecast.daysToFull)")
            }
            return .result(dialog: IntentDialog(stringLiteral: line))
        }
        let summary = await IntentScanAdapter.scanSummary(scope: AppScope.shared)
        let used = ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file)
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: String.LocalizationValue("intent.status.fallback"))
                .replacingOccurrences(of: "{used}", with: used)))
    }
}

struct KlarisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanIntent(),
                    phrases: ["Scan with \(.applicationName)", "用\(.applicationName)扫描", "\(.applicationName)でスキャン"],
                    shortTitle: "intent.shortcut.scan.title",
                    systemImageName: "magnifyingglass")
        AppShortcut(intent: CleanCacheIntent(),
                    phrases: ["Quick clean with \(.applicationName)", "用\(.applicationName)快捷回收", "\(.applicationName)でクイック整理"],
                    shortTitle: "intent.shortcut.clean.title",
                    systemImageName: "sparkles")
        AppShortcut(intent: AskStatusIntent(),
                    phrases: ["Ask \(.applicationName) about disk", "问\(.applicationName)磁盘状态", "\(.applicationName)にディスク状態を聞く"],
                    shortTitle: "intent.shortcut.status.title",
                    systemImageName: "internaldrive")
    }
}
